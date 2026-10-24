import Foundation
import BetterDictationCore

// 端到端冒烟：把一段 16kHz / mono / PCM16LE 原始音频喂给真实讯飞会话。
// 用法：bd-smoke <pcm16le-16k.raw> [--realtime]

let args = CommandLine.arguments
guard args.count >= 2, let url = URL(string: "file://" + args[1]) else {
    print("用法: bd-smoke <pcm16le-16k.raw> [--realtime]")
    exit(2)
}
let realtime = args.contains("--realtime")
let pcm = try Data(contentsOf: url)
print("音频字节: \(pcm.count)（\(pcm.count / 32) ms）")

// --segment：模拟 App 的本地分段策略，验证「停顿即出字」
if args.contains("--segment") {
    await runSegmented(pcm: pcm, realtime: realtime)
    exit(0)
}

let client = IFlytekClient(config: IFlytekConfig.resolved())
client.onPartial = { print("  partial: \($0)") }
client.onError = { print("  error: \($0.localizedDescription)") }

do {
    try client.start()
} catch {
    print("启动失败: \(error)")
    exit(1)
}

let chunkBytes = iflytekFrameSamples * 2
var offset = 0
while offset < pcm.count {
    let end = min(offset + chunkBytes, pcm.count)
    client.feed(pcm16: pcm.subdata(in: offset ..< end))
    offset = end
    if realtime { usleep(80_000) }
}

let final = await client.finish()
print("终稿: \(final)")
client.abort()
exit(final.isEmpty ? 1 : 0)


/// 按本地 VAD 切段、逐段建会话，模拟 App 的边说边打。
func runSegmented(pcm: Data, realtime: Bool) async {
    let started = Date()
    func elapsed() -> String { String(format: "%5.2fs", Date().timeIntervalSince(started)) }

    var segmenter = SpeechSegmenter()
    var client: IFlytekClient?
    var preRoll = Data()
    var offset = 0
    var segmentCount = 0

    func finishSegment() async {
        guard let current = client else { return }
        client = nil
        let text = await current.finish(timeout: 3)
        current.abort()
        segmentCount += 1
        print("\(elapsed()) [段 \(segmentCount)] \(text)")
    }

    while offset < pcm.count {
        let end = min(offset + iflytekFrameSamples * 2, pcm.count)
        let chunk = pcm.subdata(in: offset ..< end)
        offset = end

        for event in segmenter.consume(chunk) {
            switch event {
            case .speechStarted:
                if client == nil {
                    let created = IFlytekClient(config: IFlytekConfig.resolved())
                    do {
                        try created.start()
                        if !preRoll.isEmpty { created.feed(pcm16: preRoll) }
                        preRoll.removeAll(keepingCapacity: true)
                        client = created
                    } catch {
                        print("\(elapsed()) 连接失败: \(error.localizedDescription)")
                    }
                }
            case .commit:
                await finishSegment()
            }
        }

        if let client {
            client.feed(pcm16: chunk)
        } else {
            preRoll.append(chunk)
            let limit = 6_400
            if preRoll.count > limit { preRoll.removeFirst(preRoll.count - limit) }
        }

        if realtime { usleep(80_000) }
    }

    await finishSegment()
    print("\(elapsed()) 完成，共 \(segmentCount) 段")
}
