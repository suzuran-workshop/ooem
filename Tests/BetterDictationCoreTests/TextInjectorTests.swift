import Foundation
import Testing
@testable import BetterDictationCore

@Suite("文本切块")
struct TextInjectorTests {

    @Test("不超码元预算且可无损拼接")
    func chunkRespectsUnitBudget() {
        let text = String(repeating: "a", count: 40)
        let chunks = TextInjector.split(text, maxUnits: 16)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf16.count <= 16 })
    }

    @Test("不拆开代理对")
    func neverSplitsSurrogatePair() {
        let text = "abc" + String(repeating: "😀", count: 5)
        let chunks = TextInjector.split(text, maxUnits: 3)
        #expect(chunks.joined() == text)
        for chunk in chunks {
            #expect(chunk.utf16.count != 1)
        }
    }

    @Test("空串")
    func empty() {
        #expect(TextInjector.split("").isEmpty)
    }

    @Test("中文按字符切")
    func chineseChunking() {
        let text = "无敌的东海帝皇闪亮登场"
        let chunks = TextInjector.split(text, maxUnits: 4)
        #expect(chunks.joined() == text)
        #expect(chunks.first == "无敌的东")
    }
}

@Suite("热键绑定")
struct HotkeyBindingTests {

    @Test("键名映射")
    func keyName() {
        #expect(HotkeyBinding.key(96).label == "F5")
        #expect(HotkeyBinding.key(97).label == "F6")
        #expect(HotkeyBinding.systemDefined(16).label == "PlayPause")
        #expect(HotkeyBinding.systemDefined(99).label == "NXKey(99)")
    }

    @Test("Codable 往返")
    func codableRoundTrip() throws {
        let binding = HotkeyBinding.key(96)
        let data = try JSONEncoder().encode(binding)
        #expect(try JSONDecoder().decode(HotkeyBinding.self, from: data) == binding)
    }
}
