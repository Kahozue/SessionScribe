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

/// 依設定挑整理器/摘要器；任一條件不滿足都回本機（Local Only 程式層強制）。
/// 只有「總開關開 AND 引擎=雲端 AND 有 active 供應商 AND key 存在」才建構雲端 client。
public enum AssistResolver {
    public static func client(settings: CloudLLMSettings, keychain: KeychainStore) -> CloudLLMClient? {
        guard settings.enabled, settings.engine == .cloud,
              let provider = settings.activeProvider,
              let key = try? keychain.secret(account: provider.id), !key.isEmpty,
              let url = URL(string: provider.baseURL) else {
            return nil
        }
        switch provider.format {
        case .openAICompatible:
            return OpenAICompatibleClient(baseURL: url, apiKey: key, model: provider.model)
        case .anthropic:
            return AnthropicClient(baseURL: url, apiKey: key, model: provider.model)
        case .gemini:
            return GeminiClient(baseURL: url, apiKey: key, model: provider.model)
        }
    }

    public static func eventOrganizer(settings: CloudLLMSettings, keychain: KeychainStore) -> EventOrganizing {
        if let client = client(settings: settings, keychain: keychain) {
            return CloudEventOrganizer(client: client)
        }
        return LocalEventOrganizer()
    }

    public static func summarizer(settings: CloudLLMSettings, keychain: KeychainStore) -> TranscriptSummarizing {
        if let client = client(settings: settings, keychain: keychain) {
            return CloudTranscriptSummarizer(client: client)
        }
        return LocalTranscriptSummarizer()
    }
}
