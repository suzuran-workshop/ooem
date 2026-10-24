import Foundation

/// 本地语音活动检测：把连续 PCM 切成「一段话」。
///
/// 讯飞私有端点只在**会话收尾**时吐结果（见 `docs/DECISIONS.md` D13），
/// 因此客户端必须自己判断「用户说完了」，主动结束当前会话，才能做到边说边打。
///
/// 判定采用带回滞的能量阈值：高于 `speechThreshold` 记为说话，低于
/// `silenceThreshold` 记为静音，中间地带沿用上一帧，避免噪声抖动反复切段。
public struct SpeechSegmenter: Sendable {

    public enum Event: Equatable, Sendable {
        /// 本段第一处语音（用于按需建立 ASR 会话，避免长时间静音空转）
        case speechStarted
        /// 本段结束（停顿够长，或连续说话超过上限），应立刻收尾会话
        case commit
    }

    public struct Config: Equatable, Sendable {
        public var sampleRate: Int
        /// 能量统计粒度
        public var frameMs: Int
        /// 进入「说话」的 RMS 阈值（满幅 = 1.0）
        public var speechThreshold: Float
        /// 回到「静音」的 RMS 阈值
        public var silenceThreshold: Float
        /// 触发收尾所需的连续静音时长
        public var commitSilenceMs: Int
        /// 连续说话上限；到点后等下一个静音帧就收尾，避免文字无限延迟
        public var maxSegmentMs: Int
        /// 到达上限后触发收尾所需的静音时长（只等一个词间的小间隙）
        public var forcedSilenceMs: Int
        /// 认定为「开始说话」所需的最短语音
        public var minSpeechMs: Int

        public init(sampleRate: Int = 16_000,
                    frameMs: Int = 40,
                    speechThreshold: Float = 0.010,
                    silenceThreshold: Float = 0.005,
                    commitSilenceMs: Int = 250,
                    maxSegmentMs: Int = 12_000,
                    forcedSilenceMs: Int = 80,
                    minSpeechMs: Int = 80) {
            self.sampleRate = sampleRate
            self.frameMs = frameMs
            self.speechThreshold = speechThreshold
            self.silenceThreshold = silenceThreshold
            self.commitSilenceMs = commitSilenceMs
            self.maxSegmentMs = maxSegmentMs
            self.forcedSilenceMs = forcedSilenceMs
            self.minSpeechMs = minSpeechMs
        }
    }

    public let config: Config

    private var pending = Data()
    private var speaking = false
    private var segmentHasSpeech = false
    private var speechMs = 0
    private var silenceMs = 0
    private var forceCommit = false

    public init(config: Config = Config()) {
        self.config = config
    }

    /// 当前是否处于说话状态（含中间地带的沿用状态）
    public var isSpeaking: Bool { speaking }
    /// 本段已累计的语音时长
    public var currentSegmentMs: Int { speechMs }

    /// 喂入任意长度的 PCM16LE（16k/mono），返回本次触发的边界事件。
    public mutating func consume(_ pcm: Data) -> [Event] {
        guard !pcm.isEmpty else { return [] }
        pending.append(pcm)

        let frameSamples = max(1, config.sampleRate * config.frameMs / 1000)
        let frameBytes = frameSamples * 2
        var events: [Event] = []
        var offset = 0

        while pending.count - offset >= frameBytes {
            let level = Self.rms(pending, offset: offset, samples: frameSamples)
            offset += frameBytes
            if let event = classify(level) { events.append(event) }
        }

        if offset > 0 { pending.removeFirst(offset) }
        return events
    }

    /// 会话边界处重置（不做跨会话的语音累计）。
    public mutating func reset() {
        pending.removeAll(keepingCapacity: false)
        speaking = false
        segmentHasSpeech = false
        speechMs = 0
        silenceMs = 0
        forceCommit = false
    }

    // MARK: - 内部

    private mutating func classify(_ level: Float) -> Event? {
        if level >= config.speechThreshold {
            speaking = true
        } else if level <= config.silenceThreshold {
            speaking = false
        }

        if speaking {
            speechMs += config.frameMs
            silenceMs = 0
            if speechMs >= config.maxSegmentMs { forceCommit = true }
            if !segmentHasSpeech, speechMs >= config.minSpeechMs {
                segmentHasSpeech = true
                return .speechStarted
            }
            return nil
        }

        // 还没成段：静音直接清零，避免零星噪声把 speechMs 累起来
        guard segmentHasSpeech else {
            speechMs = 0
            return nil
        }

        silenceMs += config.frameMs
        let threshold = forceCommit ? config.forcedSilenceMs : config.commitSilenceMs
        guard silenceMs >= threshold else { return nil }

        resetSegment()
        return .commit
    }

    private mutating func resetSegment() {
        speaking = false
        segmentHasSpeech = false
        speechMs = 0
        silenceMs = 0
        forceCommit = false
    }

    static func rms(_ data: Data, offset: Int, samples: Int) -> Float {
        guard samples > 0 else { return 0 }
        var sum: Double = 0
        data.withUnsafeBytes { raw in
            for i in 0 ..< samples {
                let value = raw.loadUnaligned(fromByteOffset: offset + i * 2, as: Int16.self)
                let normalized = Double(value) / 32_768.0
                sum += normalized * normalized
            }
        }
        return Float((sum / Double(samples)).squareRoot())
    }
}
