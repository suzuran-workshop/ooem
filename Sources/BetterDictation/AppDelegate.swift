import AppKit
import BetterDictationCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let dictation = DictationController()
    private let hotkey = HotkeyMonitor()
    private let hud = HUDController()
    private let statusItem = StatusItemController()

    private var permissionTimer: Timer?
    private var didAutoPromptBinding = false

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        wireActions()

        statusItem.update(state: .idle, binding: Settings.binding)
        statusItem.refreshPermissions()

        hotkey.binding = Settings.binding
        requestInitialPermissions()
        startPermissionSupervisor()

        log("BetterDictation 启动，绑定：\(Settings.binding?.label ?? "未绑定")")
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        dictation.cancel()
        hotkey.stop()
    }

    // MARK: - 接线

    private func wireActions() {
        statusItem.onToggle = { [weak self] in self?.dictation.toggle() }
        statusItem.onBind = { [weak self] in self?.beginBinding() }
        statusItem.onOpenLog = { NSWorkspace.shared.open(logFileURL()) }
        statusItem.onQuit = { NSApp.terminate(nil) }
        statusItem.onFixPermissions = { [weak self] in self?.handlePermissionRequest() }

        dictation.onStateChange = { [weak self] state, partial in
            guard let self else { return }
            self.statusItem.update(state: state, binding: Settings.binding)
            self.hotkey.isEscapeEnabled = (state == .listening || state == .finishing)

            switch state {
            case .listening:
                self.hud.show(title: "聆听中…（再按一次结束）", body: partial)
            case .finishing:
                self.hud.show(title: "识别中…", body: partial)
            case .idle:
                self.hud.hide()
            }
        }

        dictation.onError = { [weak self] message in
            self?.hud.show(title: "出错了", body: message, autoHideAfter: 4)
            log("错误：\(message)")
        }

        hotkey.onTrigger = { [weak self] in self?.dictation.toggle() }
        hotkey.onCapture = { [weak self] binding in self?.finishBinding(binding) }
        hotkey.onEscape = { [weak self] in self?.dictation.cancel() }
    }

    // MARK: - 权限

    private func requestInitialPermissions() {
        Task {
            _ = await Permissions.requestMicrophone()
            await MainActor.run { self.statusItem.refreshPermissions() }
        }
        if !Permissions.accessibilityGranted {
            Permissions.promptAccessibility()
        }
    }

    /// 权限可能在运行期间才被授予 —— 定期重试，免得用户还得重启 App
    private func startPermissionSupervisor() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.supervise()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
        supervise()
    }

    private func supervise() {
        statusItem.refreshPermissions()

        if !hotkey.isRunning, Permissions.accessibilityGranted {
            hotkey.start()
        }

        if hotkey.isRunning, Settings.binding == nil, !didAutoPromptBinding {
            didAutoPromptBinding = true
            beginBinding()
        }
    }

    private func handlePermissionRequest() {
        if !Permissions.accessibilityGranted {
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
        }
        if !Permissions.microphoneAuthorized {
            Permissions.openMicrophoneSettings()
        }
    }

    // MARK: - 绑定

    private func beginBinding() {
        guard hotkey.isRunning else {
            hud.show(title: "需要辅助功能权限",
                     body: "系统设置 → 隐私与安全性 → 辅助功能，勾选 BetterDictation",
                     autoHideAfter: 5)
            handlePermissionRequest()
            return
        }
        hotkey.isCapturing = true
        hud.show(title: "绑定唤醒键", body: "请按下想用的按键（推荐 F5）")
        log("进入绑定模式")
    }

    private func finishBinding(_ binding: HotkeyBinding) {
        Settings.binding = binding
        hotkey.binding = binding
        statusItem.update(state: dictation.state, binding: binding)
        hud.show(title: "已绑定 \(binding.label)",
                 body: "按 \(binding.label) 开始，再按一次结束并输入",
                 autoHideAfter: 2.5)
        log("绑定完成：\(binding.kind.rawValue) \(binding.code) (\(binding.label))")
    }
}
