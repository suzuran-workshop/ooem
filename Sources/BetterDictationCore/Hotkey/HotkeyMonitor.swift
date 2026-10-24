import Foundation
import AppKit

/// 在 HID 层监听并（可选）吞掉指定按键。
/// 需要「辅助功能」权限；未授权时 tap 静默失效。
public final class HotkeyMonitor {

    public var binding: HotkeyBinding?
    /// 触发热键（主线程）
    public var onTrigger: (() -> Void)?
    /// 绑定模式捕获到按键（主线程）
    public var onCapture: ((HotkeyBinding) -> Void)?

    public var isCapturing = false
    /// 听写进行中才开启：吞掉 Esc 用作取消
    public var isEscapeEnabled = false
    public var onEscape: (() -> Void)?
    public private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// 已吞掉 keyDown 的键，其 keyUp 也一并吞掉
    private var swallowedKeys: Set<Int> = []

    /// kCGEventSystemDefined（14）—— CoreGraphics 未在 Swift 侧命名
    static let systemDefinedEventType = CGEventType(rawValue: 14)!

    public init() {}

    // MARK: - 生命周期

    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return true }
        guard AXIsProcessTrusted() else {
            log("热键监听未启动：缺少辅助功能权限")
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << HotkeyMonitor.systemDefinedEventType.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("热键监听创建失败（CGEventTapCreate 返回 nil）")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        log("热键监听已启动")
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    // MARK: - 事件处理

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系统会因超时/用户输入禁用 tap，必须重开
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("事件 tap 被系统禁用，已重新启用")
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == HotkeyMonitor.systemDefinedEventType.rawValue {
            return handleSystemDefined(event: event)
        }
        switch type {
        case .keyDown, .keyUp:
            return handleKey(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if type == .keyDown, !isRepeat {
            if code == 53, isEscapeEnabled {
                DispatchQueue.main.async { [weak self] in self?.onEscape?() }
                return nil
            }
            if isCapturing {
                isCapturing = false
                let binding = HotkeyBinding.key(code)
                swallowedKeys.insert(code)
                DispatchQueue.main.async { [weak self] in self?.onCapture?(binding) }
                return nil
            }
            if binding?.kind == .key, binding?.code == code, !isCapturing {
                swallowedKeys.insert(code)
                DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
                return nil
            }
        }

        if type == .keyUp, swallowedKeys.contains(code) {
            swallowedKeys.remove(code)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleSystemDefined(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data1 = nsEvent.data1
        let nxKeyType = Int((data1 & 0xFFFF_0000) >> 16)
        let isDown = ((data1 & 0x0000_FF00) >> 8) == 0x0A

        guard isDown else { return Unmanaged.passUnretained(event) }

        if isCapturing {
            isCapturing = false
            let binding = HotkeyBinding.systemDefined(nxKeyType)
            DispatchQueue.main.async { [weak self] in self?.onCapture?(binding) }
            return nil
        }
        if binding?.kind == .systemDefined, binding?.code == nxKeyType {
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy,
                               type: CGEventType,
                               event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
