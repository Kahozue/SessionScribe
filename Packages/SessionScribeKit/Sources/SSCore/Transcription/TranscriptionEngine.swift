import AVFoundation

/// 一段待轉寫音訊與其媒體時間。buffer 由餵入端持有獨佔拷貝，
/// 引擎內部如需保留必須自行複製或轉換，故可安全跨隔離。
public struct AudioSlice: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    /// 此 buffer 起點的媒體時間（秒，不含暫停）。
    public let startSeconds: Double

    public init(buffer: AVAudioPCMBuffer, startSeconds: Double) {
        self.buffer = buffer
        self.startSeconds = startSeconds
    }

    public var durationSeconds: Double {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }

    public var endSeconds: Double {
        startSeconds + durationSeconds
    }
}

public struct EngineInfo: Equatable, Sendable {
    public let name: String
    public let isOnDevice: Bool

    public init(name: String, isOnDevice: Bool) {
        self.name = name
        self.isOnDevice = isOnDevice
    }
}

public enum EngineAvailability: Equatable, Sendable {
    case available
    case requiresDownload
    case unsupported
}

/// volatile 轉寫更新：只存在記憶體，UI 就地替換顯示，永不落盤
/// （核心可靠性原則 5）。
public struct VolatileUpdate: Equatable, Sendable {
    public let text: String
    public let startSeconds: Double

    public init(text: String, startSeconds: Double) {
        self.text = text
        self.startSeconds = startSeconds
    }
}

/// ASR 引擎抽象（規格書第五節）。UI 與領域層只依賴本 protocol，
/// 具體引擎在 SSTranscription：AppleSpeechEngine、LegacySFSpeechEngine、Mock。
/// 使用順序：先訂閱兩個 stream，再 start，之後逐 slice feed，最後 finish。
public protocol TranscriptionEngine: Sendable {
    var info: EngineInfo { get }
    func availability(for locale: Locale) async -> EngineAvailability
    /// 含模型下載引導（AssetInventory）。
    func prepare(locale: Locale) async throws
    func start(sessionID: String, locale: Locale) async throws
    func feed(_ slice: AudioSlice) async throws
    func finish() async throws
    func finalizedSegments() async -> AsyncStream<TranscriptSegment>
    func volatileUpdates() async -> AsyncStream<VolatileUpdate>
    /// 詞彙提示（v0.2 名詞表第二層）：在 start 前傳入要偏向辨識的術語。
    /// 不支援的引擎用預設 no-op。
    func setContextualStrings(_ strings: [String]) async
}

extension TranscriptionEngine {
    public func setContextualStrings(_ strings: [String]) async {}
}
