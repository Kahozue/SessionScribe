import Foundation

/// 即時翻譯引擎抽象（規格 1.2 Phase 3）。比照 TranscriptionEngine 的分層：
/// 協定在 SSCore，Apple 實作在 SSTranscription，Mock 供測試。
public protocol LiveTranslator: Sendable {
    /// 備妥來源→目標的翻譯（含必要時下載模型）。錄音前呼叫。
    func prepare(source: Locale.Language, target: Locale.Language) async throws
    /// 翻譯一段文字，回傳譯文。
    func translate(_ text: String) async throws -> String
}

/// 一段 finalized 逐字稿的譯文，以 segmentID 對應原段落。
public struct TranslatedSegment: Sendable, Equatable {
    public let segmentID: String
    public let text: String

    public init(segmentID: String, text: String) {
        self.segmentID = segmentID
        self.text = text
    }
}
