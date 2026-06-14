import Foundation

/// 雲端翻譯：實作 LiveTranslator，用 chat client 逐句翻成目標語言。
/// prepare 不需下載模型，僅記錄目標語言；翻譯只送文字（不涉音訊）。
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
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
