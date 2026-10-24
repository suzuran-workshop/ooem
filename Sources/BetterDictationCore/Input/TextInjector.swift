import Foundation
import CoreGraphics
import ApplicationServices

/// 把文本逐段注入当前焦点窗口（CGEvent Unicode，绕过输入法）。
public enum TextInjector {

    /// 按 UTF-16 码元上限切块，绝不拆开代理对 / 组合字符。
    public static func split(_ text: String, maxUnits: Int = 16) -> [String] {
        guard maxUnits > 0, !text.isEmpty else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var current = ""
        var units = 0
        for char in text {
            let n = char.utf16.count
            if units + n > maxUnits, !current.isEmpty {
                chunks.append(current)
                current = ""
                units = 0
            }
            current.append(char)
            units += n
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// @return 是否成功注入（缺少辅助功能权限时返回 false）
    @discardableResult
    public static func type(_ text: String, intervalMs: UInt32 = 6) -> Bool {
        guard !text.isEmpty else { return true }
        guard AXIsProcessTrusted() else {
            log("文本注入失败：缺少辅助功能权限")
            return false
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        for chunk in split(text) {
            let units = Array(chunk.utf16)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            down.post(tap: .cghidEventTap)
            usleep(intervalMs * 1000)

            // 抬起事件不携带字符，避免部分应用重复插入
            up.post(tap: .cghidEventTap)
            usleep(intervalMs * 1000)
        }
        return true
    }

    /// 连续退格（keyCode 51 = delete）。
    @discardableResult
    public static func backspace(_ count: Int, intervalMs: UInt32 = 6) -> Bool {
        guard count > 0 else { return true }
        guard AXIsProcessTrusted() else {
            log("退格失败：缺少辅助功能权限")
            return false
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        for _ in 0 ..< count {
            CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
            usleep(intervalMs * 1000)
            CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
            usleep(intervalMs * 1000)
        }
        return true
    }
}

/// 一次注入计划：先退格 `backspaces` 个字符，再输入 `insert`。
public struct LiveTypingPlan: Equatable {
    public let backspaces: Int
    public let insert: String
    public init(backspaces: Int, insert: String) {
        self.backspaces = backspaces
        self.insert = insert
    }
    public var isNoop: Bool { backspaces == 0 && insert.isEmpty }
}

/// 边识别边打字：把服务端的「累积全文」与「已注入内容」做差，
/// 只补新增部分；若服务端修正了已注入内容，回退到公共前缀后重打。
public final class LiveTyper {

    public private(set) var injected = ""

    public init() {}

    public func reset() { injected = "" }

    public static func plan(injected: String, accumulated: String) -> LiveTypingPlan {
        if accumulated.hasPrefix(injected) {
            return LiveTypingPlan(backspaces: 0, insert: String(accumulated.dropFirst(injected.count)))
        }
        let a = Array(injected)
        let b = Array(accumulated)
        var common = 0
        while common < a.count, common < b.count, a[common] == b[common] { common += 1 }
        return LiveTypingPlan(backspaces: a.count - common, insert: String(b[common...]))
    }

    /// @return 是否注入成功
    @discardableResult
    public func update(accumulated: String) -> Bool {
        let step = LiveTyper.plan(injected: injected, accumulated: accumulated)
        guard !step.isNoop else { return true }
        if step.backspaces > 0, !TextInjector.backspace(step.backspaces) { return false }
        if !step.insert.isEmpty, !TextInjector.type(step.insert) { return false }
        injected = accumulated
        return true
    }
}
