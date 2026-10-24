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
