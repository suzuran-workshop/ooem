import Foundation
import BetterDictationCore

/// 一次听写的状态机：idle → listening → finishing → idle
///
/// 识别结果**边到边打**进焦点窗口，不在 GUI 里回显。
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

    private let config = IFlytekConfig.resolved()
    private let audio = AudioCapture()
    private let typer = LiveTyper()
    private var client: IFlytekClient?
    private var finishTask: Task<Void, Never>?
    /// 已完成分段的文本；服务端 VAD 提前收尾时会累积到这里
    private var committed = ""

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
        typer.reset()
        committed = ""
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
        typer.reset()
        committed = ""

        do {
            try audio.start()
        } catch {
            onError?("无法启动麦克风：\(error.localizedDescription)")
            return
        }
        guard startSession() else {
            audio.stop()
            return
        }
        state = .listening
    }

    /// 建立/重建一段 ASR 会话；返回是否成功。
    @MainActor
    @discardableResult
    private func startSession() -> Bool {
        let client = IFlytekClient(config: config)
        client.onPartial = { [weak self] accumulated in
            guard let self else { return }
            // 边识别边注入：只补新增部分（含之前已完成的分段）
            if !self.typer.update(accumulated: self.committed + accumulated) {
                self.onError?("文本注入失败，请检查辅助功能权限")
            }
        }
        client.onError = { [weak self] error in
            self?.onError?("识别出错：\(error.localizedDescription)")
        }
        // 服务端 VAD 判定说完：把本段并入 committed，然后无缝开新会话
        client.onAutoFinish = { [weak self] text in
            guard let self, self.state == .listening else { return }
            self.committed += text
            _ = self.typer.update(accumulated: self.committed)
            self.startSession()
            log("分段收尾，已续接新会话（累计 \(self.committed.count) 字）")
        }

        do {
            try client.start()
        } catch {
            onError?("无法建立识别连接：\(error.localizedDescription)")
            return false
        }

        self.client = client
        audio.onPCM = { [weak client] pcm in client?.feed(pcm16: pcm) }
        return true
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
            // 终稿只补增量；已注入部分不会重复
            let combined = self.committed + text
            if !combined.isEmpty, !self.typer.update(accumulated: combined) {
                self.onError?("文本注入失败，请检查辅助功能权限")
            }
            client?.abort()
            self.typer.reset()
            self.committed = ""
            self.state = .idle
        }
    }
}
