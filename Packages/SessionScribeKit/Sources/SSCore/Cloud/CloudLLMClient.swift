import Foundation

/// 雲端 LLM 的最小能力：給 system 指示與 user 內容，回傳 assistant 純文字。
/// 三個格式轉接器各自實作；上層的整理/摘要只依賴此協定。
public protocol CloudLLMClient: Sendable {
    func complete(system: String, user: String) async throws -> String
}

/// 可注入的 HTTP 傳輸，預設包 URLSession；測試以 stub 回傳預錄資料，不打真網路。
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public enum CloudProviderFormat: String, Codable, Sendable, CaseIterable {
    case openAICompatible = "openai_compatible"
    case anthropic
    case gemini

    public var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 相容"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        }
    }

    /// 是否提供語音轉文字端點。Anthropic 無 STT API。
    public var supportsSTT: Bool {
        switch self {
        case .anthropic: false
        case .openAICompatible, .gemini: true
        }
    }
}

public enum CloudLLMError: Error, Sendable, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    case malformedResponse(String)
    case transport(String)

    public var userMessage: String {
        switch self {
        case .missingAPIKey: "尚未設定 API key。"
        case .http(let status, _) where status == 401: "API key 無效或未授權（401）。"
        case .http(let status, _) where status == 429: "雲端服務忙線或額度受限（429），請稍後再試。"
        case .http(let status, let body):
            if let detail = Self.serverMessage(from: body) {
                "雲端服務回應錯誤（\(status)）：\(detail)"
            } else {
                "雲端服務回應錯誤（\(status)）。"
            }
        case .malformedResponse: "雲端回應格式無法解析。"
        case .transport(let detail): "連線失敗：\(detail)"
        }
    }

    private static func serverMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        return nil
    }
}

/// 預設傳輸：URLSession，並把非 HTTPURLResponse 視為傳輸錯誤。
public enum DefaultHTTPTransport {
    public static let live: HTTPTransport = { request in
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CloudLLMError.transport("非 HTTP 回應")
            }
            return (data, http)
        } catch let error as CloudLLMError {
            throw error
        } catch {
            throw CloudLLMError.transport(error.localizedDescription)
        }
    }
}
