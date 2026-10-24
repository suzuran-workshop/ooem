import Foundation
import AVFoundation

/// 麦克风采集 → 16kHz / 单声道 / PCM16LE。
public final class AudioCapture {

    public enum CaptureError: LocalizedError {
        case noInputDevice
        case converterUnavailable

        public var errorDescription: String? {
            switch self {
            case .noInputDevice: return "找不到可用的输入设备"
            case .converterUnavailable: return "音频格式转换器创建失败"
            }
        }
    }

    public var onPCM: ((Data) -> Void)?
    public private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    public init() {}

    public static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func requestMicrophone() async -> Bool {
        switch microphoneStatus {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        default: return false
        }
    }

    public func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: Double(iflytekSampleRate),
                                         channels: 1,
                                         interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: target)
        else { throw CaptureError.converterUnavailable }

        self.converter = converter
        self.targetFormat = target

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.convert(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        log("音频采集启动 \(Int(inFormat.sampleRate))Hz \(inFormat.channelCount)ch → 16000Hz mono")
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        targetFormat = nil
        isRunning = false
        log("音频采集停止")
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let target = targetFormat else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, out.frameLength > 0, let channel = out.int16ChannelData?[0] else { return }
        let data = Data(bytes: channel, count: Int(out.frameLength) * MemoryLayout<Int16>.size)
        onPCM?(data)
    }
}
