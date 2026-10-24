import AppKit

/// 屏幕底部中央的非激活浮层：显示状态与实时转写。
final class HUDController {

    private var panel: NSPanel?
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private var hideWork: DispatchWorkItem?

    private let panelWidth: CGFloat = 520
    private let horizontalInset: CGFloat = 18
    private let maxBodyWidth: CGFloat = 484

    init() {
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = .labelColor
        bodyLabel.maximumNumberOfLines = 4
        bodyLabel.preferredMaxLayoutWidth = maxBodyWidth
    }

    // MARK: - 对外

    func show(title: String, body: String = "", autoHideAfter: TimeInterval? = nil) {
        hideWork?.cancel()
        hideWork = nil

        titleLabel.stringValue = title
        bodyLabel.stringValue = body
        bodyLabel.isHidden = body.isEmpty

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
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
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
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true

        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -horizontalInset),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),
        ])

        panel.contentView = effect
        return panel
    }

    private func layoutPanel() {
        let panel = panel ?? {
            let p = makePanel()
            panel = p
            return p
        }()

        var height: CGFloat = 12 + 16 + 12
        if !bodyLabel.stringValue.isEmpty {
            let size = bodyLabel.sizeThatFits(NSSize(width: maxBodyWidth, height: .greatestFiniteMagnitude))
            height += 4 + size.height
        }
        height = max(height, 52)

        guard let screen = NSScreen.main else { return }
        let frame = NSRect(
            x: screen.visibleFrame.midX - panelWidth / 2,
            y: screen.visibleFrame.minY + 96,
            width: panelWidth,
            height: height
        )
        panel.setFrame(frame, display: true, animate: false)
    }
}
