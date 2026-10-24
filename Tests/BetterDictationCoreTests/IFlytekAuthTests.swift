import Foundation
import Testing
@testable import BetterDictationCore

@Suite("讯飞签名与凭据")
struct IFlytekAuthTests {

    private let cfg = IFlytekConfig(
        appID: "100IME",
        apiKey: "15461402826c8360ebcf1270cbba88e5",
        apiSecret: "sH8v2wSSxxHTy1UNfN6dFaSqVjlmR7BB"
    )

    /// 真实会话 golden 向量（2026-10-15 15:28:44 GMT）
    @Test("复现真实会话签名")
    func signatureMatchesGoldenVector() {
        let sig = IFlytekAuth.signature(
            host: "100ime-iat-api.xfyun.cn",
            path: "/v2/iat",
            date: "Thu, 15 Oct 2026 15:28:44 GMT",
            secret: cfg.apiSecret
        )
        #expect(sig == "/WlV8Lvm9L9qGw4rn//WpVlYschhJD5IWVPN2lRNP7M=")
    }

    @Test("RFC1123 GMT 日期格式")
    func rfc1123Format() throws {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 15
        comps.hour = 15; comps.minute = 28; comps.second = 44
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "GMT"))
        let date = try #require(cal.date(from: comps))
        #expect(IFlytekAuth.rfc1123(date) == "Thu, 15 Oct 2026 15:28:44 GMT")
    }

    @Test("签名 URL 结构完整")
    func signedURLContainsDecodableAuthorization() throws {
        let url = IFlytekAuth.signedURL(config: cfg)
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.scheme == "wss")
        #expect(comps.host == "100ime-iat-api.xfyun.cn")
        #expect(comps.path == "/v2/iat")

        let authB64 = try #require(comps.queryItems?.first { $0.name == "authorization" }?.value)
        let authData = try #require(Data(base64Encoded: authB64))
        let decoded = try #require(String(data: authData, encoding: .utf8))
        #expect(decoded.contains("username=\"15461402826c8360ebcf1270cbba88e5\""))
        #expect(decoded.contains("algorithm=\"hmac-sha256\""))
        #expect(decoded.contains("headers=\"host date request-line\""))
    }

    @Test("内置凭据可解码")
    func builtinCredentialsDecode() {
        let builtin = IFlytekConfig.builtin()
        #expect(builtin.apiKey == cfg.apiKey)
        #expect(builtin.apiSecret == cfg.apiSecret)
        #expect(builtin.appID == "100IME")
    }

    @Test("env 逐字段覆盖")
    func envOverridesPerField() {
        let resolved = IFlytekConfig.resolved(env: [
            "BETTERDICTATION_IFLYTEK_API_KEY": "k2",
            "BETTERDICTATION_IFLYTEK_APP_ID": "app2",
        ])
        #expect(resolved.apiKey == "k2")
        #expect(resolved.apiSecret == cfg.apiSecret)
        #expect(resolved.appID == "app2")
    }
}
