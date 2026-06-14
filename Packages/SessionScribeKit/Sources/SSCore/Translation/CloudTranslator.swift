import Foundation

/// 雲端翻譯：實作 LiveTranslator，用 chat client 逐句翻成目標語言。
/// prepare 不需下載模型，僅記錄目標語言；翻譯只送文字（不涉音訊）。
/// `@unchecked Sendable`：`target` 的寫（prepare）讀（translate）依賴唯一呼叫者
/// `TranslationCoordinator`（actor）序列化保證，不得在 actor 外直接呼叫本型別。
public final class CloudTranslator: LiveTranslator, @unchecked Sendable {
    private let client: CloudLLMClient
    private var target: Locale.Language

    public init(client: CloudLLMClient, target: Locale.Language) {
        self.client = client
        self.target = target
    }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        self.target = target
    }

    public func translate(_ text: String) async throws -> String {
        let targetName = target.languageCode?.identifier ?? "en"
        let system = """
            你是翻譯引擎。把使用者文字翻成目標語言（BCP-47：\(targetName)）。
            只輸出 JSON 物件 {"translation":"譯文"}，不要加說明或原文。
            """
        let reply = try await client.complete(system: system, user: text)
        return try Self.parseTranslation(reply)
    }

    static func parseTranslation(_ reply: String) throws -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if let json = try? JSONExtraction.firstJSONValue(in: trimmed),
           let data = json.data(using: .utf8),
           let object = try? JSONDecoder().decode(TranslationJSON.self, from: data) {
            return stripWrapping(object.translation.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stripWrapping(trimmed)
    }

    /// 模型偶爾無視指示用引號包住整句譯文，去掉前後成對的引號（直引號與「」）。
    static func stripWrapping(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("「", "」")]
        for (open, close) in pairs
        where text.count >= 2 && text.first == open && text.last == close {
            return String(text.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private struct TranslationJSON: Decodable { let translation: String }
}
