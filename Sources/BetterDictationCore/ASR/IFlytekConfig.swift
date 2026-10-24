import Foundation

/// 讯飞私有 ASR 端点配置。
///
/// 凭据来源见 `docs/DECISIONS.md` D1：与本机已安装讯飞输入法的互操作分析所得，
/// 设备级、仅供本机个人使用。env 可逐字段覆盖，便于凭据轮换。
public struct IFlytekConfig: Equatable, Sendable {
    public var host: String
    public var path: String
    public var appID: String
    public var apiKey: String
    public var apiSecret: String

    public static let defaultHost = "100ime-iat-api.xfyun.cn"
    public static let defaultPath = "/v2/iat"

    public init(host: String = IFlytekConfig.defaultHost,
                path: String = IFlytekConfig.defaultPath,
                appID: String,
                apiKey: String,
                apiSecret: String) {
        self.host = host
        self.path = path
        self.appID = appID
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }

    /// base64(JSON) 内置凭据 —— 开箱即用，无需任何配置。
    static let builtinCredentialsB64 =
        "eyJhcGlLZXkiOiIxNTQ2MTQwMjgyNmM4MzYwZWJjZjEyNzBjYmJhODhlNSIsImFwaVNlY3JldCI6InNIOHYyd1NTeHhIVHkxVU5mTjZkRmFTcVZqbG1SN0JCIiwiYXBwSWQiOiIxMDBJTUUifQ=="

    public static func builtin() -> IFlytekConfig {
        guard
            let data = Data(base64Encoded: builtinCredentialsB64),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let key = obj["apiKey"], let secret = obj["apiSecret"]
        else {
            return IFlytekConfig(appID: "100IME", apiKey: "", apiSecret: "")
        }
        return IFlytekConfig(appID: obj["appId"] ?? "100IME", apiKey: key, apiSecret: secret)
    }

    /// 内置凭据 ⊕ env 逐字段覆盖。
    public static func resolved(env: [String: String] = ProcessInfo.processInfo.environment) -> IFlytekConfig {
        let base = builtin()
        return IFlytekConfig(
            appID: env["BETTERDICTATION_IFLYTEK_APP_ID"] ?? base.appID,
            apiKey: env["BETTERDICTATION_IFLYTEK_API_KEY"] ?? base.apiKey,
            apiSecret: env["BETTERDICTATION_IFLYTEK_API_SECRET"] ?? base.apiSecret
        )
    }
}
