import AppKit
import BetterDictationCore

final class StatusItemController: NSObject, NSMenuDelegate {

    var onToggle: (() -> Void)?
    var onBind: (() -> Void)?
    var onOpenLog: (() -> Void)?
    var onQuit: (() -> Void)?
    var onFixPermissions: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenuItem = NSMenuItem(title: "就绪", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "开始听写", action: #selector(toggleTapped), keyEquivalent: "")
    private let bindMenuItem = NSMenuItem(title: "绑定唤醒键…", action: #selector(bindTapped), keyEquivalent: "")
    private let permissionMenuItem = NSMenuItem(title: "检查权限", action: #selector(permissionTapped), keyEquivalent: "")

    private var bindingLabel = "未绑定"

    override init() {
        super.init()
        buildMenu()
        setIcon("mic")
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

        menu.addItem(.separator())

        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)

        let logItem = NSMenuItem(title: "打开日志", action: #selector(logTapped), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 BetterDictation", action: #selector(quitTapped), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func setIcon(_ symbolName: String) {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BetterDictation") else { return }
        image.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "BetterDictation"
    }

    func update(state: DictationController.State, binding: HotkeyBinding?) {
        bindingLabel = binding?.label ?? "未绑定"
        bindMenuItem.title = "绑定唤醒键…（当前：\(bindingLabel)）"

        switch state {
        case .idle:
            statusMenuItem.title = "就绪 · \(bindingLabel)"
            toggleMenuItem.title = "开始听写"
            setIcon("mic")
        case .listening:
            statusMenuItem.title = "聆听中…"
            toggleMenuItem.title = "停止并输入"
            setIcon("mic.fill")
        case .finishing:
            statusMenuItem.title = "识别中…"
            toggleMenuItem.title = "识别中…"
            setIcon("waveform")
        }
        toggleMenuItem.isEnabled = state != .finishing
    }

    func refreshPermissions() {
        let mic = Permissions.microphoneAuthorized ? "✅" : "❌"
        let ax = Permissions.accessibilityGranted ? "✅" : "❌"
        permissionMenuItem.title = "权限：麦克风 \(mic)　辅助功能 \(ax)"
    }

    // MARK: - Actions

    @objc private func toggleTapped() { onToggle?() }
    @objc private func bindTapped() { onBind?() }
    @objc private func logTapped() { onOpenLog?() }
    @objc private func quitTapped() { onQuit?() }
    @objc private func permissionTapped() { onFixPermissions?() }

    func menuWillOpen(_ menu: NSMenu) {
        refreshPermissions()
    }
}
