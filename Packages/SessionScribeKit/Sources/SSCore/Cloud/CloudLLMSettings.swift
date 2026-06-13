import Foundation

public enum AssistEngineKind: String, Codable, Sendable, CaseIterable {
    case local, cloud
}

/// 單一供應商設定（不含 API key；key 存 Keychain，以 id 為 account）。
public struct CloudProviderConfig: Codable, Equatable, Sendable, Identifiable {
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
}

public struct CloudLLMSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var engine: AssistEngineKind
    public var providers: [CloudProviderConfig]
    public var activeProviderID: String?

    public init(enabled: Bool = false, engine: AssistEngineKind = .local,
                providers: [CloudProviderConfig] = [], activeProviderID: String? = nil) {
        self.enabled = enabled; self.engine = engine
        self.providers = providers; self.activeProviderID = activeProviderID
    }

    public var activeProvider: CloudProviderConfig? {
        providers.first { $0.id == activeProviderID }
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
}
