import Foundation

/// 一次听写会话：URLSession WebSocket 推流 + 流式结果累积。
///
/// 协议要点（见 docs/DECISIONS.md D2）：
/// - 首帧合并 business / common / 音频，`status: 1`
/// - 后续帧仅 `data`，`status: 1`
/// - 尾帧 `status: 2`（必须携带音频，无音频时发静音兜底）
public final class IFlytekClient {

    public enum ClientError: LocalizedError {
        case badURL
        case notRunning

        public var errorDescription: String? {
            switch self {
            case .badURL: return "签名 URL 生成失败"
            case .notRunning: return "WebSocket 未连接"
            }
        }
    }

    /// 中间结果（累积全文），主线程回调。
    public var onPartial: ((String) -> Void)?
    /// 错误，主线程回调。
    public var onError: ((Error) -> Void)?

    private let config: IFlytekConfig
    private let queue = DispatchQueue(label: "io.xrl.betterdictation.asr")

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var framer = AudioFramer()

    private var accumulated = ""
    private var firstFrameSent = false
    private var stoppedFeeding = false
    private var resolved = false
    private var inflightSends = 0
    private let maxInflightSends = 64

    private let deviceID = IFlytekFrame.deviceID()
    private var uidSequence = 0

    private var finishContinuation: CheckedContinuation<String, Never>?
    private var timeoutWork: DispatchWorkItem?

    public init(config: IFlytekConfig) {
        self.config = config
    }

    deinit { teardown() }

    // MARK: - 生命周期

    public func start() throws {
        guard let url = URL(string: IFlytekAuth.signedURL(config: config).absoluteString) else {
            throw ClientError.badURL
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // 服务端不回显子协议：只发不协商（URLSession 允许缺失回显）
        request.setValue("dumb-increment-protocol", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveLoop(task)
        log("ASR 会话开始 \(config.host)\(config.path)")
    }

    public func feed(pcm16: Data) {
        queue.async { [weak self] in
            guard let self, !self.stoppedFeeding, !self.resolved else { return }
            for frame in self.framer.push(pcm16: pcm16) {
                self.send(frame: frame, status: 1)
            }
        }
    }

    /// 收尾并等待终稿；超时以已累积文本兜底。
    public func finish(timeout: TimeInterval = 6) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(returning: ""); return }
                if self.resolved {
                    cont.resume(returning: self.accumulated)
                    return
                }
                self.stoppedFeeding = true
                self.finishContinuation = cont

                var tail = self.framer.flush()
                if tail == nil || tail!.isEmpty {
                    tail = Data(repeating: 0, count: 320) // 全程无音频兜底
                }
                self.send(frame: tail!, status: 2)

                let work = DispatchWorkItem { [weak self] in self?.resolveFinal() }
                self.timeoutWork = work
                self.queue.asyncAfter(deadline: .now() + timeout, execute: work)
            }
        }
    }

    public func abort() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stoppedFeeding = true
            self.resolveFinal()
        }
    }

    // MARK: - 内部

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handleIncoming(Data(text.utf8))
                case .data(let data): self.handleIncoming(data)
                @unknown default: break
                }
                self.receiveLoop(task)
            case .failure(let error):
                self.queue.async { [weak self] in
                    guard let self, !self.resolved else { return }
                    self.reportError(error)
                    self.resolveFinal()
                }
            }
        }
    }

    private func handleIncoming(_ data: Data) {
        queue.async { [weak self] in
            guard let self, !self.resolved else { return }
            if ProcessInfo.processInfo.environment["IFLYTEK_DEBUG"] == "1" {
                log("ASR <- \(String(data: data, encoding: .utf8) ?? "<binary>")")
            }
            let (event, text) = IFlytekResponse.parse(data, accumulated: self.accumulated)
            self.accumulated = text
            switch event {
            case .partial:
                let snapshot = text
                DispatchQueue.main.async { self.onPartial?(snapshot) }
            case .finished:
                self.resolveFinal()
            case .failure(let code, let message):
                self.reportError(NSError(domain: "iflytek", code: code,
                                         userInfo: [NSLocalizedDescriptionKey: message]))
                self.resolveFinal()
            case .ignored:
                break
            }
        }
    }

    private func send(frame: Data, status: Int) {
        guard let task, task.state == .running else {
            reportError(ClientError.notRunning)
            return
        }
        // 背压保护：积压超过阈值直接丢帧（宁可丢音频，不要爆内存）
        guard inflightSends < maxInflightSends else { return }

        let payload: Data
        if !firstFrameSent {
            firstFrameSent = true
            uidSequence += 1
            payload = IFlytekFrame.firstFrame(
                config: config, pcm: frame, status: status,
                deviceID: deviceID, uid: IFlytekFrame.uid(sequence: uidSequence)
            )
        } else {
            payload = IFlytekFrame.followFrame(pcm: frame, status: status)
        }
        guard let text = String(data: payload, encoding: .utf8) else { return }

        inflightSends += 1
        task.send(.string(text)) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.inflightSends -= 1
                if let error { self.reportError(error) }
            }
        }
    }

    private func resolveFinal() {
        guard !resolved else { return }
        resolved = true
        timeoutWork?.cancel()
        timeoutWork = nil

        let text = accumulated
        let cont = finishContinuation
        finishContinuation = nil
        teardown()
        cont?.resume(returning: text)
        log("ASR 会话结束：\(text.isEmpty ? "(空)" : text)")
    }

    private func teardown() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func reportError(_ error: Error) {
        log("ASR 错误：\(error.localizedDescription)")
        DispatchQueue.main.async { self.onError?(error) }
    }
}
