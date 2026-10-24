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
            var units = Array(chunk.utf16)
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
}
