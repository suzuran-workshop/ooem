import Foundation

/// 80ms @16k —— 讯飞实况客户端的推流节奏（1280 样本）。
public let iflytekFrameSamples = 1280
public let iflytekSampleRate = 16_000

/// 把任意长度的 PCM16 流攒成固定 80ms 帧。
public struct AudioFramer {
    private var pending: [Int16] = []

    public init() {}

    /// 喂入 PCM16LE 字节流，吐出凑满的整帧（每帧 1280 样本的原始字节）。
    public mutating func push(pcm16: Data) -> [Data] {
        let count = pcm16.count / 2
        guard count > 0 else { return [] }
        var samples = [Int16](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { dst in
            pcm16.copyBytes(to: dst)
        }
        pending.append(contentsOf: samples)

        var frames: [Data] = []
        var offset = 0
        while pending.count - offset >= iflytekFrameSamples {
            let slice = pending[offset ..< offset + iflytekFrameSamples]
            frames.append(slice.withUnsafeBufferPointer { Data(buffer: $0) })
            offset += iflytekFrameSamples
        }
        if offset > 0 { pending.removeFirst(offset) }
        return frames
    }

    /// 取出残余（不足一帧的尾段），无残余返回 nil。
    public mutating func flush() -> Data? {
        guard !pending.isEmpty else { return nil }
        let rest = pending
        pending.removeAll(keepingCapacity: false)
        return rest.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public mutating func reset() { pending.removeAll(keepingCapacity: false) }
}

/// 首帧 / 后续帧的 JSON 构造。
public enum IFlytekFrame {
    public static let business: [String: Any] = [
        "aue": "raw",
        "ent": "sms16k",
        "eos": 4000,
        "vad_enable": true,
        "vad_speech_tail": 4000,
        "vad_timeout": 4000,
    ]

    public static func deviceID() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let b64 = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "=", with: "")
        return "bd" + b64.prefix(18) + "v"
    }

    public static func uid(sequence: Int, now: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: now)
        let p = { (v: Int?, w: Int) in String(format: "%0\(w)d", v ?? 0) }
        let stamp = "\(String(format: "%02d", (c.year ?? 2000) % 100))\(p(c.month, 2))\(p(c.day, 2))\(p(c.hour, 2))\(p(c.minute, 2))\(p(c.second, 2))"
        let ms = (c.nanosecond ?? 0) / 1_000_000
        return stamp + p(ms, 3) + String(sequence)
    }

    public static func firstFrame(config: IFlytekConfig, pcm: Data, status: Int,
                                  deviceID: String, uid: String) -> Data {
        let payload: [String: Any] = [
            "business": business,
            "common": [
                "app_id": config.appID,
                "app.ver": "better-dictation-0.1",
                "device_id": deviceID,
                "device.imei": deviceID,
                "device.imsi": deviceID,
                "uid": uid,
            ],
            "data": audioPayload(pcm, status: status),
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    public static func followFrame(pcm: Data, status: Int) -> Data {
        let payload: [String: Any] = ["data": audioPayload(pcm, status: status)]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private static func audioPayload(_ pcm: Data, status: Int) -> [String: Any] {
        [
            "audio": pcm.base64EncodedString(),
            "encoding": "raw",
            "format": "audio/L16;rate=16000",
            "status": status,
        ]
    }
}

/// 服务端下行帧的判定结果。
public enum IFlytekEvent: Equatable {
    /// 流式中间结果（增量字）
    case partial(String)
    /// 会话终止，携带累积全文
    case finished(String)
    /// 服务端返回非 0 code
    case failure(code: Int, message: String)
    /// 无需处理
    case ignored
}

public enum IFlytekResponse {

    private struct Envelope: Decodable {
        struct DataBlock: Decodable {
            struct Result: Decodable {
                struct Segment: Decodable {
                    struct Candidate: Decodable { let w: String? }
                    let cw: [Candidate]?
                }
                let ls: Bool?
                let ws: [Segment]?
            }
            let result: Result?
            let status: Int?
        }
        let code: Int?
        let message: String?
        let data: DataBlock?
    }

    /// 解析一帧下行，`accumulated` 为已累积文本，返回事件与新的累积文本。
    public static func parse(_ json: Data, accumulated: String) -> (event: IFlytekEvent, text: String) {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: json) else {
            return (.ignored, accumulated)
        }
        if let code = env.code, code != 0 {
            return (.failure(code: code, message: env.message ?? ""), accumulated)
        }
        var text = accumulated
        let piece = (env.data?.result?.ws ?? [])
            .flatMap { $0.cw ?? [] }
            .compactMap { $0.w }
            .joined()
        if !piece.isEmpty { text += piece }

        let isFinal = (env.data?.result?.ls ?? false) || (env.data?.status == 2)
        if isFinal { return (.finished(text), text) }
        if !piece.isEmpty { return (.partial(piece), text) }
        return (.ignored, text)
    }
}
