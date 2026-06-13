import Foundation

/// 雲端整份摘要：對齊本機 TranscriptSummarizer，重用 buildSummary 收斂行為。
public struct CloudTranscriptSummarizer: TranscriptSummarizing {
    let client: CloudLLMClient
    public init(client: CloudLLMClient) { self.client = client }

    private struct SummaryJSON: Decodable {
        var content: String?; var keyPoints: [String]?; var actionItems: [String]?
    }

    private static let schema = """

        請只輸出 JSON 物件，鍵為：content(整份摘要字串)、keyPoints(重點字串陣列)、
        actionItems(待辦字串陣列；沒有就空陣列)。全部繁體中文。
        """

    public func summarize(from segments: [TranscriptSegment], sessionID: String,
                          locale: Locale) async throws -> TranscriptSummary {
        let finals = segments.filter(\.isFinal).sorted { $0.startSeconds < $1.startSeconds }
        let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        guard !finals.isEmpty else {
            return TranscriptSummarizer.buildSummary(
                content: "", keyPoints: [], actionItems: [], segments: finals,
                sessionID: sessionID, createdAt: createdAt)
        }
        let transcript = finals
            .map { "[\(Int($0.startSeconds))-\(Int($0.endSeconds))] \($0.text)" }
            .joined(separator: "\n")
        let prompt = """
            以下是 locale \(locale.identifier) 的完整逐字稿，行首為錄音秒數區間。
            請整理整份逐字稿的摘要、重點與待辦：

            \(transcript)
            """
        let reply = try await client.complete(
            system: TranscriptSummarizer.instructions + Self.schema, user: prompt)
        let json = try JSONExtraction.firstJSONValue(in: reply)
        guard let data = json.data(using: .utf8),
              let fields = try? JSONDecoder().decode(SummaryJSON.self, from: data) else {
            throw CloudLLMError.malformedResponse("摘要 JSON 無法對應")
        }
        return TranscriptSummarizer.buildSummary(
            content: fields.content ?? "", keyPoints: fields.keyPoints ?? [],
            actionItems: fields.actionItems ?? [], segments: finals,
            sessionID: sessionID, createdAt: createdAt)
    }
}
