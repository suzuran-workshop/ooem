import AppKit
import BetterDictationCore

final class StatusItemController: NSObject, NSMenuDelegate {

    var onToggle: (() -> Void)?
    var onBind: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onOpenLog: (() -> Void)?
    var onQuit: (() -> Void)?
    var onFixPermissions: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenuItem = NSMenuItem(title: "就绪", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "开始听写", action: #selector(toggleTapped), keyEquivalent: "")
    private let bindMenuItem = NSMenuItem(title: "绑定唤醒键…", action: #selector(bindTapped), keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "开机自启", action: #selector(launchAtLoginTapped), keyEquivalent: "")
    private let permissionMenuItem = NSMenuItem(title: "检查权限", action: #selector(permissionTapped), keyEquivalent: "")

    override init() {
        super.init()
        buildMenu()
        statusItem.button?.image = StatusIcon.image(for: .idle)
        statusItem.button?.toolTip = "BetterDictation \(AppVersion.display)"
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        bindMenuItem.target = self
        menu.addItem(bindMenuItem)

        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)

        let logItem = NSMenuItem(title: "打开日志", action: #selector(logTapped), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())
        let versionItem = NSMenuItem(
            title: "BetterDictation \(AppVersion.display)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "退出 BetterDictation", action: #selector(quitTapped), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func update(state: DictationController.State, binding: HotkeyBinding?) {
        bindMenuItem.title = "绑定唤醒键…（当前：\(binding?.label ?? "未绑定")）"

        switch state {
        case .idle:
            statusMenuItem.title = "就绪 · \(binding?.label ?? "未绑定")"
            toggleMenuItem.title = "开始听写"
        case .listening:
            statusMenuItem.title = "聆听中…"
            toggleMenuItem.title = "停止并完成"
        case .finishing:
            statusMenuItem.title = "识别中…"
            toggleMenuItem.title = "识别中…"
        }
        toggleMenuItem.isEnabled = state != .finishing

        statusItem.button?.image = StatusIcon.image(for: state)
    }

    func refreshPermissions() {
        let mic = Permissions.microphoneAuthorized ? "✅" : "❌"
        let ax = Permissions.accessibilityGranted ? "✅" : "❌"
        permissionMenuItem.title = "权限：麦克风 \(mic)　辅助功能 \(ax)"
    }

    func refreshLaunchAtLogin() {
        launchAtLoginMenuItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleTapped() { onToggle?() }
    @objc private func bindTapped() { onBind?() }
    @objc private func launchAtLoginTapped() { onToggleLaunchAtLogin?() }
    @objc private func logTapped() { onOpenLog?() }
    @objc private func quitTapped() { onQuit?() }
    @objc private func permissionTapped() { onFixPermissions?() }

    func menuWillOpen(_ menu: NSMenu) {
        refreshPermissions()
        refreshLaunchAtLogin()
    }
}
