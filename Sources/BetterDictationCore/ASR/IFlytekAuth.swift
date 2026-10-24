import Foundation
import CryptoKit

/// 讯飞 `hmac-sha256` 签名（headers = host / date / request-line）。
public enum IFlytekAuth {

    public static func rfc1123(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.string(from: date)
    }

    public static func signature(host: String, path: String, date: String, secret: String) -> String {
        let signStr = "host: \(host)\ndate: \(date)\nGET \(path) HTTP/1.1"
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(signStr.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    /// `hmac username="…", algorithm="hmac-sha256", headers="host date request-line", signature="…"`
    public static func authorizationHeader(config: IFlytekConfig, date: String) -> String {
        let sig = signature(host: config.host, path: config.path, date: date, secret: config.apiSecret)
        return "hmac username=\"\(config.apiKey)\", algorithm=\"hmac-sha256\", "
            + "headers=\"host date request-line\", signature=\"\(sig)\""
    }

    /// 完整 wss URL；authorization 为 base64(header) 后再 URL 编码。
    public static func signedURL(config: IFlytekConfig, date: Date = Date()) -> URL {
        let dateStr = rfc1123(date)
        let auth = authorizationHeader(config: config, date: dateStr)
        let authB64 = Data(auth.utf8).base64EncodedString()

        var comps = URLComponents()
        comps.scheme = "wss"
        comps.host = config.host
        comps.path = config.path
        comps.queryItems = [
            URLQueryItem(name: "date", value: dateStr),
            URLQueryItem(name: "host", value: config.host),
            URLQueryItem(name: "authorization", value: authB64),
        ]
        return comps.url!
    }
}
