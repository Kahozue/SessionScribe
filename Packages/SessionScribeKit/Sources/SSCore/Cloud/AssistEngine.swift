import Foundation

/// 整理器抽象：本機（FoundationModels）與雲端共用同一介面，供 UI 路由。
public protocol EventOrganizing: Sendable {
    func organize(_ events: [StructuredEvent], locale: Locale,
                  progress: @Sendable (Double) -> Void) async throws -> [StructuredEvent]
    func generateEvents(from segments: [TranscriptSegment], sessionID: String,
                        locale: Locale) async throws -> [StructuredEvent]
}

public protocol TranscriptSummarizing: Sendable {
    func summarize(from segments: [TranscriptSegment], sessionID: String,
                   locale: Locale) async throws -> TranscriptSummary
}

/// 本機包裝：轉呼既有 EventOrganizer 靜態方法。
public struct LocalEventOrganizer: EventOrganizing {
    public init() {}
    public func organize(_ events: [StructuredEvent], locale: Locale,
                         progress: @Sendable (Double) -> Void) async throws -> [StructuredEvent] {
        try await EventOrganizer.organize(events, locale: locale, progress: progress)
    }
    public func generateEvents(from segments: [TranscriptSegment], sessionID: String,
                               locale: Locale) async throws -> [StructuredEvent] {
        try await EventOrganizer.generateEvents(from: segments, sessionID: sessionID, locale: locale)
    }
}

public struct LocalTranscriptSummarizer: TranscriptSummarizing {
    public init() {}
    public func summarize(from segments: [TranscriptSegment], sessionID: String,
                          locale: Locale) async throws -> TranscriptSummary {
        try await TranscriptSummarizer.generateSummary(from: segments, sessionID: sessionID, locale: locale)
    }
}
