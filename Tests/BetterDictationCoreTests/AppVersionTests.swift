import Testing
@testable import BetterDictationCore

@Suite("版本号")
struct AppVersionTests {

    @Test("marketing 是合法的 x.y.z，tag 由它派生")
    func marketingVersion() {
        let parts = AppVersion.marketing.split(separator: ".")
        #expect(parts.count >= 3)
        #expect(parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        #expect(AppVersion.tag == "v" + AppVersion.marketing)
    }

    @Test("display 就是版本号")
    func display() {
        #expect(AppVersion.display == AppVersion.marketing)
    }
}
