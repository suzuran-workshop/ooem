import Foundation
import BetterDictationCore

/// 一次听写的状态机：idle → listening → finishing → idle
///
/// 讯飞私有端点只在**会话收尾**时吐结果，所以这里用本地 VAD 把音频切成
/// 一段段「说完的话」：停顿一到就结束当前会话、拿到文字立即注入，
/// 然后等下一段语音再新建会话。识别结果全程只进焦点窗口，不在 GUI 回显。
final class DictationController {

    enum State: Equatable {
        case idle
        case listening
        case finishing

        var display: String {
            switch self {
            case .idle: return "就绪"
            case .listening: return "聆听中…"
            case .finishing: return "识别中…"
            }
        }
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    /// 主线程回调
    var onStateChange: ((State) -> Void)?
    var onError: ((String) -> Void)?

    /// 轮换会话时等待旧会话终稿的上限；到点用已累积文本兜底
    private static let rotateFinishTimeout: TimeInterval = 3
    /// 按下停止后等待终稿的上限
    private static let stopFinishTimeout: TimeInterval = 4
    /// 等待语音起始时保留的预卷：200ms @16k/mono PCM16
    private static let preRollBytes = 6_400

    private let config = IFlytekConfig.resolved()
    private let audio = AudioCapture()
    private let typer = LiveTyper()
    private let router = AudioRouter()
    private let segmentQueue = DispatchQueue(label: "io.xrl.betterdictation.segment")
    private var segmenter = SpeechSegmenter()

    private var client: IFlytekClient?
    private var rotatingClient: IFlytekClient?
    private var rotateTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?

    /// 轮换期间是否又检测到语音（决定新会话立刻建立还是等语音）
    private var speechActive = false
    private var rotating = false
    /// 已完成的会话文本；每段收尾时并入
    private var committed = ""
    /// 每次开始/取消都自增，异步任务用它识别自己是否已过期
    private var generation = 0
    private var reportedInjectionFailure = false

    // MARK: - 对外

    func toggle() {
        switch state {
        case .idle: start()
        case .listening: stop()
        case .finishing: break
        }
    }

    func cancel() {
        guard state != .idle else { return }
        generation += 1
        finishTask?.cancel()
        finishTask = nil
        rotateTask?.cancel()
        rotateTask = nil

        audio.onPCM = nil
        audio.stop()
        client?.abort()
        client = nil
        rotatingClient?.abort()
        rotatingClient = nil
        router.stop()

        typer.reset()
        committed = ""
        speechActive = false
        rotating = false
        segmentQueue.sync { segmenter.reset() }
        state = .idle
        log("听写已取消")
    }

    // MARK: - 流程

    private func start() {
        Task { @MainActor in
            let granted = await Permissions.requestMicrophone()
            guard granted else {
                self.onError?("缺少麦克风权限，请在系统设置中授权")
                return
            }
            self.startAudio()
        }
    }

    @MainActor
    private func startAudio() {
        generation += 1
        let gen = generation

        typer.reset()
        committed = ""
        speechActive = false
        rotating = false
        reportedInjectionFailure = false
        segmentQueue.sync { segmenter.reset() }

        do {
            try audio.start()
        } catch {
            onError?("无法启动麦克风：\(error.localizedDescription)")
            return
        }

        // 先等语音：静音期只保留预卷，避免长停顿里空转 ASR 会话
        router.stop()
        router.beginBuffering(maxBytes: Self.preRollBytes)
        audio.onPCM = { [weak self] pcm in
            guard let self else { return }
            self.router.push(pcm)
            self.segmentQueue.async { [weak self] in
                guard let self else { return }
                let events = self.segmenter.consume(pcm)
                guard !events.isEmpty else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, gen == self.generation else { return }
                    events.forEach(self.handle)
                }
            }
        }
        state = .listening
        log("听写开始，等待语音")
    }

    @MainActor
    private func handle(_ event: SpeechSegmenter.Event) {
        switch event {
        case .speechStarted:
            speechActive = true
            guard state == .listening, !rotating, client == nil else { return }
            _ = startSession(gen: generation)

        case .commit:
            speechActive = false
            requestRotation()
        }
    }

    /// 建立一段 ASR 会话，并把暂存的音频补喂进去。
    @MainActor
    @discardableResult
    private func startSession(gen: Int) -> Bool {
        guard gen == generation else { return false }

        let client = IFlytekClient(config: config)
        client.onPartial = { [weak self, weak client] text in
            guard let self, let client, self.isCurrent(client) else { return }
            self.inject(segment: text)
        }
        client.onError = { [weak self, weak client] error in
            guard let self else { return }
            if let client, !self.isCurrent(client) { return }
            self.onError?("识别出错：\(error.localizedDescription)")
        }
        // 服务端 VAD 自己收尾（本地 VAD 没抓住的兜底）：并入本段并等下一段语音
        client.onAutoFinish = { [weak self, weak client] text in
            guard let self, let client, self.isCurrent(client) else { return }
            self.serverFinishedSegment(text: text)
        }

        do {
            try client.start()
        } catch {
            onError?("无法建立识别连接：\(error.localizedDescription)")
            return false
        }

        self.client = client
        activateRoute(to: client)
        log("ASR 会话建立")
        return true
    }

    /// 把 router 暂存的音频原子地交给新会话（可能分多轮，因为喂的同时还在录音）。
    @MainActor
    private func activateRoute(to client: IFlytekClient) {
        while true {
            let chunks = router.activate { pcm in client.feed(pcm16: pcm) }
            if chunks.isEmpty { break }
            for chunk in chunks { client.feed(pcm16: chunk) }
        }
    }

    /// 本地 VAD 判定一段说完：收尾旧会话 → 注入文字 → 等下一段语音。
    @MainActor
    private func requestRotation() {
        guard state == .listening, !rotating, let old = client else { return }

        rotating = true
        rotatingClient = old
        client = nil
        // 收尾/握手期间不丢音，全部暂存
        router.beginBuffering(maxBytes: nil)

        let gen = generation
        rotateTask = Task { @MainActor in
            let text = await old.finish(timeout: Self.rotateFinishTimeout)
            old.abort()
            guard gen == self.generation else { return }

            self.rotateTask = nil
            self.rotatingClient = nil
            self.commit(segment: text)
            self.rotating = false
            self.resumeAfterRotation(gen: gen)
        }
    }

    /// 一段收尾后的去向：有语音就立刻开新会话，没语音就只留预卷。
    @MainActor
    private func resumeAfterRotation(gen: Int) {
        guard gen == generation else { return }

        switch state {
        case .listening:
            if speechActive {
                if !startSession(gen: gen) {
                    router.beginBuffering(maxBytes: Self.preRollBytes)
                }
            } else {
                router.beginBuffering(maxBytes: Self.preRollBytes)
            }

        case .finishing:
            // 用户在轮换期间按了停止：把暂存的声音也送进一次会话再收尾
            if speechActive || router.hasPending {
                if startSession(gen: gen) {
                    finishListeningSession(gen: gen)
                } else {
                    router.stop()
                    finishAll()
                }
            } else {
                router.stop()
                finishAll()
            }

        case .idle:
            router.stop()
        }
    }

    /// 服务端 VAD 主动结束会话（会话已由客户端自行 teardown）。
    @MainActor
    private func serverFinishedSegment(text: String) {
        guard state == .listening, !rotating, client != nil else { return }
        rotating = true
        rotatingClient = nil
        client = nil
        router.beginBuffering(maxBytes: nil)

        commit(segment: text)
        rotating = false
        resumeAfterRotation(gen: generation)
    }

    private func stop() {
        guard state == .listening else { return }
        state = .finishing

        audio.onPCM = nil
        audio.stop()

        // 轮换任务收尾后会看到 .finishing，自行把暂存音频送进新会话再结束
        if rotating { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // 轮换可能在上一行之后开始；交给轮换任务收尾
            if self.rotating { return }
            guard self.client != nil else {
                self.router.stop()
                self.finishAll()
                return
            }
            self.finishListeningSession(gen: self.generation)
        }
    }

    @MainActor
    private func finishListeningSession(gen: Int) {
        guard gen == generation else { return }
        guard let old = client else {
            router.stop()
            finishAll()
            return
        }

        client = nil
        router.stop()
        finishTask = Task { @MainActor in
            let text = await old.finish(timeout: Self.stopFinishTimeout)
            old.abort()
            guard gen == self.generation else { return }

            self.finishTask = nil
            self.commit(segment: text)
            self.finishAll()
        }
    }

    @MainActor
    private func finishAll() {
        client = nil
        rotatingClient = nil
        speechActive = false
        rotating = false
        router.stop()
        typer.reset()
        committed = ""
        segmentQueue.sync { segmenter.reset() }
        state = .idle
    }

    // MARK: - 注入

    private func isCurrent(_ client: IFlytekClient) -> Bool {
        self.client === client
    }

    /// 注入「已提交文本 + 当前会话文本」；只补增量，服务端修正时自动回退重打。
    @MainActor
    private func inject(segment: String) {
        let target = committed + segment
        guard !target.isEmpty else { return }
        if !typer.update(accumulated: target), !reportedInjectionFailure {
            reportedInjectionFailure = true
            onError?("文本注入失败，请检查辅助功能权限")
        }
    }

    /// 一段会话收官：并入 committed，并保证终稿已注入。
    @MainActor
    private func commit(segment: String) {
        committed += segment
        inject(segment: "")
    }
}
