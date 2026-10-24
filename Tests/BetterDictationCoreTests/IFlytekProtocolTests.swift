import Foundation
import Testing
@testable import BetterDictationCore

@Suite("音频分帧")
struct AudioFramerTests {

    @Test("凑满 80ms 整帧，余量留到 flush")
    func emits80msFrames() {
        var framer = AudioFramer()
        let frames = framer.push(pcm16: Data(repeating: 0, count: 2000 * 2))
        #expect(frames.count == 1)
        #expect(frames[0].count == iflytekFrameSamples * 2)
        #expect(framer.flush()?.count == 720 * 2)
        #expect(framer.flush() == nil)
    }

    @Test("跨块累积")
    func accumulatesAcrossChunks() {
        var framer = AudioFramer()
        #expect(framer.push(pcm16: Data(repeating: 0, count: 1000 * 2)).isEmpty)
        #expect(framer.push(pcm16: Data(repeating: 0, count: 1000 * 2)).count == 1)
        #expect(framer.flush()?.count == 720 * 2)
    }

    @Test("空输入")
    func emptyInput() {
        var framer = AudioFramer()
        #expect(framer.push(pcm16: Data()).isEmpty)
        #expect(framer.flush() == nil)
    }
}

@Suite("下行帧解析")
struct IFlytekResponseTests {

    @Test("中间结果累积")
    func partialAccumulates() {
        let json = #"{"code":0,"message":"success","sid":"iat1","data":{"result":{"sn":1,"ls":false,"ws":[{"cw":[{"w":"你"},{"w":"好"}]}]},"status":0}}"#
        let (event, text) = IFlytekResponse.parse(Data(json.utf8), accumulated: "前")
        #expect(event == .partial("你好"))
        #expect(text == "前你好")
    }

    @Test("ls 终止")
    func finalByLS() {
        let json = #"{"code":0,"data":{"result":{"sn":2,"ls":true,"ws":[{"cw":[{"w":"。"}]}]},"status":2}}"#
        let (event, text) = IFlytekResponse.parse(Data(json.utf8), accumulated: "你好")
        #expect(event == .finished("你好。"))
        #expect(text == "你好。")
    }

    @Test("错误码")
    func failureCode() {
        let json = #"{"code":10165,"message":"invalid authorization"}"#
        let (event, _) = IFlytekResponse.parse(Data(json.utf8), accumulated: "")
        #expect(event == .failure(code: 10165, message: "invalid authorization"))
    }

    @Test("畸形帧不影响累计")
    func ignoresMalformed() {
        let (event, text) = IFlytekResponse.parse(Data("not json".utf8), accumulated: "保持")
        #expect(event == .ignored)
        #expect(text == "保持")
    }

    @Test("首帧 / 后续帧 JSON 结构")
    func frameShape() throws {
        let cfg = IFlytekConfig(appID: "100IME", apiKey: "k", apiSecret: "s")
        let data = IFlytekFrame.firstFrame(config: cfg, pcm: Data([1, 2, 3, 4]),
                                           status: 1, deviceID: "dev", uid: "u1")
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let business = try #require(obj["business"] as? [String: Any])
        #expect(business["aue"] as? String == "raw")
        let common = try #require(obj["common"] as? [String: Any])
        #expect(common["app_id"] as? String == "100IME")
        let audio = try #require(obj["data"] as? [String: Any])
        #expect(audio["encoding"] as? String == "raw")
        #expect(audio["format"] as? String == "audio/L16;rate=16000")
        #expect(audio["status"] as? Int == 1)

        let follow = IFlytekFrame.followFrame(pcm: Data([9, 9]), status: 2)
        let fobj = try #require(try JSONSerialization.jsonObject(with: follow) as? [String: Any])
        #expect(fobj["business"] == nil)
        #expect((fobj["data"] as? [String: Any])?["status"] as? Int == 2)
    }
}
