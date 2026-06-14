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
            只輸出譯文本身，不要加引號、說明或原文。
            """
        let reply = try await client.complete(system: system, user: text)
        return Self.stripWrapping(reply.trimmingCharacters(in: .whitespacesAndNewlines))
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
}
