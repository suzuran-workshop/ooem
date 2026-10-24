import AppKit

/// 极简浮层：只用于「绑定按键」和「错误提示」，听写过程完全不打扰。
/// 强制深色外观，避免浅色模式下变成一块白色圆角。
final class HUDController {

    private var panel: NSPanel?
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var hideWork: DispatchWorkItem?

    private let panelWidth: CGFloat = 420

    init() {
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.maximumNumberOfLines = 3
        messageLabel.alignment = .center
        messageLabel.preferredMaxLayoutWidth = panelWidth - 36
    }

    // MARK: - 对外

    func show(_ message: String, autoHideAfter: TimeInterval? = nil) {
        hideWork?.cancel()
        hideWork = nil

        messageLabel.stringValue = message
        layoutPanel()
        panel?.orderFrontRegardless()

        if let delay = autoHideAfter {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    // MARK: - 布局

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            messageLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            messageLabel.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])

        panel.contentView = effect
        return panel
    }

    /// 惰性创建浮层；首次显示时才建 NSWindow。
    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let created = makePanel()
        panel = created
        return created
    }

    private func layoutPanel() {
        let panel = ensurePanel()

        let textHeight = messageLabel.sizeThatFits(
            NSSize(width: panelWidth - 36, height: .greatestFiniteMagnitude)
        ).height
        let height = max(44, textHeight + 22)

        guard let screen = NSScreen.main else { return }
        panel.setFrame(
            NSRect(x: screen.visibleFrame.midX - panelWidth / 2,
                   y: screen.visibleFrame.minY + 110,
                   width: panelWidth,
                   height: height),
            display: true,
            animate: false
        )
    }
}
