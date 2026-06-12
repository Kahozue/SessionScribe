import Synchronization

/// 媒體時間時鐘：以累計音訊 frame 數除以取樣率得出秒數。
/// pause 期間無 buffer 流入，時間自然停止；錄音寫入與轉寫共用同一個實例，
/// 兩條時間軸天然一致（架構文件第四節）。
public final class MediaClock: Sendable {
    public let sampleRate: Double
    private let accumulatedFrames = Mutex<Int64>(0)

    public init(sampleRate: Double) {
        precondition(sampleRate > 0, "sampleRate 必須為正數")
        self.sampleRate = sampleRate
    }

    /// 目前媒體時間（秒，從錄音起點累計，不含暫停）。
    public var currentSeconds: Double {
        Double(accumulatedFrames.withLock { $0 }) / sampleRate
    }

    /// 每收到一個音訊 buffer 即以其 frame 數推進。
    public func advance(frames: Int) {
        precondition(frames >= 0, "frames 不得為負")
        accumulatedFrames.withLock { $0 += Int64(frames) }
    }

    public func reset() {
        accumulatedFrames.withLock { $0 = 0 }
    }
}
