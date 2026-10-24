import Foundation
import BetterDictationCore

/// 一次听写的状态机：idle → listening → finishing → idle
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
        didSet { onStateChange?(state, partial) }
    }
    private(set) var partial: String = "" {
        didSet { onStateChange?(state, partial) }
    }

    /// (state, partial text) —— 主线程
    var onStateChange: ((State, String) -> Void)?
    var onError: ((String) -> Void)?

    private let config = IFlytekConfig.resolved()
    private let audio = AudioCapture()
    private var client: IFlytekClient?
    private var finishTask: Task<Void, Never>?

    var isBusy: Bool { state != .idle }

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
        finishTask?.cancel()
        finishTask = nil
        audio.onPCM = nil
        audio.stop()
        client?.abort()
        client = nil
        partial = ""
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
        let client = IFlytekClient(config: config)
        client.onPartial = { [weak self] text in
            self?.partial = text
        }
        client.onError = { [weak self] error in
            self?.onError?("识别出错：\(error.localizedDescription)")
        }

        do {
            try client.start()
        } catch {
            onError?("无法建立识别连接：\(error.localizedDescription)")
            return
        }

        audio.onPCM = { [weak client] pcm in client?.feed(pcm16: pcm) }
        do {
            try audio.start()
        } catch {
            client.abort()
            onError?("无法启动麦克风：\(error.localizedDescription)")
            return
        }

        self.client = client
        partial = ""
        state = .listening
    }

    private func stop() {
        guard state == .listening else { return }
        audio.onPCM = nil
        audio.stop()
        state = .finishing

        let client = self.client
        self.client = nil
        finishTask = Task { @MainActor in
            let text = await client?.finish() ?? ""
            if Task.isCancelled { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !TextInjector.type(trimmed) {
                    self.onError?("文本注入失败，请检查辅助功能权限")
                }
            }
            client?.abort()
            self.partial = ""
            self.state = .idle
        }
    }
}
