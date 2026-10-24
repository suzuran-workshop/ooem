import Foundation

/// 音频路由：在「直送当前 ASR 会话」与「暂存」之间原子切换。
///
/// 轮换会话需要先结束旧连接、再建立新连接，中间有一小段空窗；
/// 把这段时间的 PCM 暂存下来，等新会话就绪后原样补喂，避免吞字。
public final class AudioRouter: @unchecked Sendable {

    private let lock = NSLock()
    private var sink: ((Data) -> Void)?
    private var pending: [Data] = []
    private var pendingBytes = 0
    private var buffering = false
    private var maxBytes: Int?

    public init() {}

    /// 音频线程调用：有会话直送，暂存中则入队。
    public func push(_ pcm: Data) {
        guard !pcm.isEmpty else { return }
        lock.lock()
        if buffering {
            pending.append(pcm)
            pendingBytes += pcm.count
            if let maxBytes { trimLocked(limit: maxBytes) }
            lock.unlock()
            return
        }
        let target = sink
        lock.unlock()
        target?(pcm)
    }

    /// 主线程：开始暂存。
    /// - Parameter maxBytes: 非空时只保留最近的音频（等待语音时的预卷）；
    ///   传 nil 表示不裁剪（轮换期间必须保全部音频）。
    public func beginBuffering(maxBytes: Int? = nil) {
        lock.lock()
        buffering = true
        self.maxBytes = maxBytes
        if let maxBytes { trimLocked(limit: maxBytes) }
        lock.unlock()
    }

    /// 主线程：安装 sink 并结束暂存。
    /// 若此刻仍有暂存，返回这些音频且**继续保持暂存**，调用方喂完后需要再调一次；
    /// 返回空数组表示切换完成。
    public func activate(_ sink: ((Data) -> Void)?) -> [Data] {
        lock.lock()
        if !pending.isEmpty {
            let out = pending
            pending.removeAll(keepingCapacity: false)
            pendingBytes = 0
            lock.unlock()
            return out
        }
        self.sink = sink
        buffering = false
        maxBytes = nil
        lock.unlock()
        return []
    }

    /// 丢弃暂存并断开输出。
    public func stop() {
        lock.lock()
        sink = nil
        pending.removeAll(keepingCapacity: false)
        pendingBytes = 0
        buffering = false
        maxBytes = nil
        lock.unlock()
    }

    public var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pending.isEmpty
    }

    public var isBuffering: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffering
    }

    private func trimLocked(limit: Int) {
        while pendingBytes > limit, !pending.isEmpty {
            pendingBytes -= pending.removeFirst().count
        }
    }
}
