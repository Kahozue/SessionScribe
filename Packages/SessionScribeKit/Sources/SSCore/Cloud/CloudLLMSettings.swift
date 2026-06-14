import Foundation

public enum AssistEngineKind: String, Codable, Sendable, CaseIterable {
    case local, cloud
}

/// 單一供應商設定（不含 API key；key 存 Keychain，以 id 為 account）。
public struct CloudProviderConfig: Codable, Equatable, Sendable, Identifiable {
    public static let defaultOpenAISTTModel = "gpt-4o-mini-transcribe"

    public var id: String
    public var format: CloudProviderFormat
    public var displayName: String
    public var baseURL: String
    public var model: String

    public init(id: String, format: CloudProviderFormat, displayName: String,
                baseURL: String, model: String) {
        self.id = id; self.format = format; self.displayName = displayName
        self.baseURL = baseURL; self.model = model
    }

    /// 設定頁「新增」用的常見供應商樣板（使用者仍可改 base URL/model）。
    public static let builtInTemplates: [CloudProviderConfig] = [
        .init(id: "openai", format: .openAICompatible, displayName: "OpenAI",
              baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        .init(id: "deepseek", format: .openAICompatible, displayName: "DeepSeek",
              baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        .init(id: "anthropic", format: .anthropic, displayName: "Anthropic",
              baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-6"),
        .init(id: "gemini", format: .gemini, displayName: "Gemini",
              baseURL: "https://generativelanguage.googleapis.com", model: "gemini-2.0-flash"),
    ]

    /// 語音類「新增供應商」用的樣板。OpenAI 相容文字模型（例如 gpt-4o-mini）
    /// 不能直接用於 /audio/transcriptions，因此語音槽有自己的 STT 預設值。
    public static let builtInAudioTemplates: [CloudProviderConfig] = [
        .init(id: "openai-stt", format: .openAICompatible, displayName: "OpenAI",
              baseURL: "https://api.openai.com/v1", model: defaultOpenAISTTModel),
        .init(id: "gemini-stt", format: .gemini, displayName: "Gemini",
              baseURL: "https://generativelanguage.googleapis.com", model: "gemini-2.0-flash"),
    ]
}

public struct CloudLLMSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var providers: [CloudProviderConfig]
    /// 以 AssistFeature.rawValue 為鍵；未列出者視為本機。
    public var featureEngines: [String: AssistEngineKind]
    public var textProviderID: String?
    public var audioProviderID: String?

    public init(enabled: Bool = false, providers: [CloudProviderConfig] = [],
                featureEngines: [String: AssistEngineKind] = [:],
                textProviderID: String? = nil, audioProviderID: String? = nil) {
        self.enabled = enabled
        self.providers = providers
        self.featureEngines = featureEngines
        self.textProviderID = textProviderID
        self.audioProviderID = audioProviderID
    }

    // MARK: 讀取輔助

    public func engine(for feature: AssistFeature) -> AssistEngineKind {
        featureEngines[feature.rawValue] ?? .local
    }

    public mutating func setEngine(_ kind: AssistEngineKind, for feature: AssistFeature) {
        featureEngines[feature.rawValue] = kind
    }

    public func providerID(for feature: AssistFeature) -> String? {
        switch feature.capability {
        case .text: textProviderID
        case .audio: audioProviderID
        }
    }

    public func provider(for feature: AssistFeature) -> CloudProviderConfig? {
        guard let id = providerID(for: feature) else { return nil }
        return providers.first { $0.id == id }
    }

    /// 主畫面雲端狀態標用：總開關開且至少一項功能選雲端。
    public var anyFeatureCloud: Bool {
        enabled && AssistFeature.allCases.contains { engine(for: $0) == .cloud }
    }

    // MARK: Codable（含舊格式遷移）

    private enum CodingKeys: String, CodingKey {
        case enabled, providers, featureEngines, textProviderID, audioProviderID
        case engine, activeProviderID   // 舊格式
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        providers = try c.decodeIfPresent([CloudProviderConfig].self, forKey: .providers) ?? []
        if let fe = try c.decodeIfPresent([String: AssistEngineKind].self, forKey: .featureEngines) {
            featureEngines = fe
            textProviderID = try c.decodeIfPresent(String.self, forKey: .textProviderID)
            audioProviderID = try c.decodeIfPresent(String.self, forKey: .audioProviderID)
        } else {
            // 舊格式只代表既有摘要/事件雲端整理。升級時不得自動開啟字幕翻譯或音訊上傳路徑。
            let legacy = try c.decodeIfPresent(AssistEngineKind.self, forKey: .engine) ?? .local
            let legacyProvider = try c.decodeIfPresent(String.self, forKey: .activeProviderID)
            var fe: [String: AssistEngineKind] = [:]
            for f in [AssistFeature.summary, .events] {
                fe[f.rawValue] = legacy
            }
            fe[AssistFeature.translation.rawValue] = .local
            fe[AssistFeature.offlineTranscript.rawValue] = .local
            fe[AssistFeature.liveASR.rawValue] = .local
            featureEngines = fe
            textProviderID = legacyProvider
            audioProviderID = nil
        }
        providers = Self.migratingProviderDefaults(
            providers, audioProviderID: audioProviderID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(providers, forKey: .providers)
        try c.encode(featureEngines, forKey: .featureEngines)
        try c.encodeIfPresent(textProviderID, forKey: .textProviderID)
        try c.encodeIfPresent(audioProviderID, forKey: .audioProviderID)
    }

    // MARK: UserDefaults 持久化（key 不在此，存 Keychain）
    public static let defaultsKey = "cloudLLMSettings"

    public static func load(from defaults: UserDefaults = .standard) -> CloudLLMSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(CloudLLMSettings.self, from: data) else {
            return CloudLLMSettings()
        }
        return s
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func migratingProviderDefaults(
        _ providers: [CloudProviderConfig],
        audioProviderID: String?
    ) -> [CloudProviderConfig] {
        providers.map { provider in
            guard shouldMigrateOpenAISTTDefault(provider, audioProviderID: audioProviderID) else {
                return provider
            }
            var migrated = provider
            migrated.model = CloudProviderConfig.defaultOpenAISTTModel
            return migrated
        }
    }

    private static func shouldMigrateOpenAISTTDefault(
        _ provider: CloudProviderConfig,
        audioProviderID: String?
    ) -> Bool {
        guard provider.format == .openAICompatible,
              (provider.model == "whisper-1"
                || provider.model == "gpt-4o-transcribe-diarize"),
              provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                == "https://api.openai.com/v1" else {
            return false
        }
        return provider.id.hasPrefix("openai-stt")
            || provider.displayName == "OpenAI"
            || provider.id == audioProviderID
    }
}
