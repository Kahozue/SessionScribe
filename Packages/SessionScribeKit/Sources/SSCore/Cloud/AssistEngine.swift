import Foundation

/// 可個別選本地/雲端的功能。capability 決定吃文字類或語音類供應商槽。
public enum AssistFeature: String, Codable, Sendable, CaseIterable {
    case offlineTranscript, liveASR, summary, events, translation

    public enum Capability: Sendable { case text, audio }

    public var capability: Capability {
        switch self {
        case .offlineTranscript, .liveASR: .audio
        case .summary, .events, .translation: .text
        }
    }
}

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

public enum AssistResolver {
    /// 由供應商與 key 直接建 chat client（測試連線、低階用）。
    public static func makeClient(provider: CloudProviderConfig, key: String) -> CloudLLMClient? {
        guard !key.isEmpty, let url = URL(string: provider.baseURL) else { return nil }
        switch provider.format {
        case .openAICompatible:
            return OpenAICompatibleClient(baseURL: url, apiKey: key, model: provider.model)
        case .anthropic:
            return AnthropicClient(baseURL: url, apiKey: key, model: provider.model)
        case .gemini:
            return GeminiClient(baseURL: url, apiKey: key, model: provider.model)
        }
    }

    /// 依 feature 取 chat client；任一條件不滿足回 nil（Local Only 程式層強制）。
    public static func client(settings: CloudLLMSettings, keychain: KeychainStore,
                              feature: AssistFeature) -> CloudLLMClient? {
        guard settings.enabled, settings.engine(for: feature) == .cloud,
              let provider = settings.provider(for: feature),
              let key = try? keychain.secret(account: provider.id), !key.isEmpty else {
            return nil
        }
        return makeClient(provider: provider, key: key)
    }

    /// 依 offlineTranscript feature 取 STT client；需供應商支援 STT。
    public static func sttClient(settings: CloudLLMSettings,
                                 keychain: KeychainStore) -> CloudSTTClient? {
        let feature = AssistFeature.offlineTranscript
        guard settings.enabled, settings.engine(for: feature) == .cloud,
              let provider = settings.provider(for: feature), provider.format.supportsSTT,
              let key = try? keychain.secret(account: provider.id), !key.isEmpty,
              let url = URL(string: provider.baseURL) else {
            return nil
        }
        switch provider.format {
        case .openAICompatible:
            return OpenAISTTClient(baseURL: url, apiKey: key, model: provider.model)
        case .gemini:
            return GeminiSTTClient(baseURL: url, apiKey: key, model: provider.model)
        case .anthropic:
            return nil
        }
    }

    public static func eventOrganizer(settings: CloudLLMSettings,
                                      keychain: KeychainStore) -> EventOrganizing {
        if let client = client(settings: settings, keychain: keychain, feature: .events) {
            return CloudEventOrganizer(client: client)
        }
        return LocalEventOrganizer()
    }

    public static func summarizer(settings: CloudLLMSettings,
                                  keychain: KeychainStore) -> TranscriptSummarizing {
        if let client = client(settings: settings, keychain: keychain, feature: .summary) {
            return CloudTranscriptSummarizer(client: client)
        }
        return LocalTranscriptSummarizer()
    }
}
