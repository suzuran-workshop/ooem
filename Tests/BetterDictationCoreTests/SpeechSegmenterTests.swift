import Foundation
import Testing
@testable import BetterDictationCore

@Suite("本地语音分段")
struct SpeechSegmenterTests {

    private func tone(ms: Int, amplitude: Float = 0.1) -> Data {
        let count = 16_000 * ms / 1000
        var samples = [Int16](repeating: 0, count: count)
        for i in 0 ..< count {
            let v = amplitude * 32_767 * Float(sin(2 * Double.pi * 440 * Double(i) / 16_000))
            samples[i] = Int16(v)
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func silence(ms: Int) -> Data {
        Data(repeating: 0, count: 16_000 * ms / 1000 * 2)
    }

    @Test("首段语音只发一次 speechStarted")
    func speechStartsOnce() {
        var segmenter = SpeechSegmenter()
        let events = segmenter.consume(tone(ms: 400))
        #expect(events == [.speechStarted])
        #expect(segmenter.isSpeaking)
    }

    @Test("静音不足阈值不收尾，够了才 commit")
    func commitAfterSilence() {
        var segmenter = SpeechSegmenter()
        _ = segmenter.consume(tone(ms: 300))

        #expect(segmenter.consume(silence(ms: 200)).isEmpty)
        #expect(segmenter.consume(silence(ms: 120)) == [.commit])
        #expect(!segmenter.isSpeaking)
    }

    @Test("纯静音不产生任何事件")
    func silenceAlone() {
        var segmenter = SpeechSegmenter()
        #expect(segmenter.consume(silence(ms: 2000)).isEmpty)
    }

    @Test("短促噪声不建立会话")
    func shortNoiseIgnored() {
        var segmenter = SpeechSegmenter()
        #expect(segmenter.consume(tone(ms: 40)).isEmpty)
        #expect(segmenter.consume(silence(ms: 80)).isEmpty)
        #expect(segmenter.currentSegmentMs == 0)
    }

    @Test("超过最长段后，词间小间隙即收尾")
    func forcedCommitAtMaxSegment() {
        var config = SpeechSegmenter.Config()
        config.maxSegmentMs = 400
        config.commitSilenceMs = 500
        config.forcedSilenceMs = 80
        var segmenter = SpeechSegmenter(config: config)

        let start = segmenter.consume(tone(ms: 600))
        #expect(start == [.speechStarted])
        #expect(segmenter.consume(silence(ms: 80)) == [.commit])
    }

    @Test("到上限后若一直没静音，音频继续累积而不是丢弃")
    func capWaitsForGap() {
        var config = SpeechSegmenter.Config()
        config.maxSegmentMs = 400
        var segmenter = SpeechSegmenter(config: config)

        // 连续 2 秒：超过上限也不会自己切，整段仍在本段里
        #expect(segmenter.consume(tone(ms: 2000)) == [.speechStarted])
        #expect(segmenter.currentSegmentMs == 2000)

        // 直到出现 80ms 词间间隙才收尾
        #expect(segmenter.consume(silence(ms: 80)) == [.commit])
    }

    @Test("跨任意切块边界结果一致")
    func chunkBoundariesIrrelevant() {
        var whole = SpeechSegmenter()
        let audio = tone(ms: 300) + silence(ms: 400)
        let expected = whole.consume(audio)

        var split = SpeechSegmenter()
        var actual: [SpeechSegmenter.Event] = []
        var offset = 0
        let chunk = 137
        while offset < audio.count {
            let end = min(offset + chunk, audio.count)
            actual += split.consume(audio.subdata(in: offset ..< end))
            offset = end
        }
        #expect(actual == expected)
        #expect(expected == [.speechStarted, .commit])
    }

    @Test("reset 清空累计")
    func resetClearsState() {
        var segmenter = SpeechSegmenter()
        _ = segmenter.consume(tone(ms: 400))
        segmenter.reset()
        #expect(segmenter.consume(silence(ms: 1000)).isEmpty)
        #expect(segmenter.currentSegmentMs == 0)
    }
}

@Suite("音频路由")
struct AudioRouterTests {

    @Test("暂存后按序补喂，再安装 sink")
    func buffersThenActivates() {
        let router = AudioRouter()
        var received: [Data] = []

        router.beginBuffering()
        router.push(Data([1]))
        router.push(Data([2]))

        let first = router.activate { received.append($0) }
        #expect(first == [Data([1]), Data([2])])

        let second = router.activate { received.append($0) }
        #expect(second.isEmpty)

        router.push(Data([3]))
        #expect(received == [Data([3])])
    }

    @Test("预卷模式只保留最近音频")
    func preRollTrimsOldAudio() {
        let router = AudioRouter()
        router.beginBuffering(maxBytes: 6)
        router.push(Data(repeating: 1, count: 4))
        router.push(Data(repeating: 2, count: 4))
        router.push(Data(repeating: 3, count: 4))

        let chunks = router.activate(nil)
        #expect(chunks.map(\.count).reduce(0, +) <= 6)
        #expect(chunks.last == Data(repeating: 3, count: 4))
    }

    @Test("stop 丢弃暂存")
    func stopDropsBuffer() {
        let router = AudioRouter()
        router.beginBuffering()
        router.push(Data([1]))
        router.stop()
        #expect(!router.hasPending)
        #expect(router.activate(nil).isEmpty)
    }
}
