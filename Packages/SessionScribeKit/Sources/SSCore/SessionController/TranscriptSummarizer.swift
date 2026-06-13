import Foundation
import FoundationModels

/// 本機 LLM 逐字稿摘要（v0.3）：對整份 finalized transcript 產生摘要。
/// 摘要是衍生資料，原始逐字稿不被覆蓋；摘要預設不標需複查。
public enum TranscriptSummarizer {

    public enum SummaryError: Error, Sendable {
        case modelUnavailable(String)
        case generationFailed(String)
    }

    @Generable
    struct SummaryFields {
        @Guide(description: "整份逐字稿的摘要，三到六句，繁體中文")
        var content: String
        @Guide(description: "三到八個重點，每個重點一句")
        var keyPoints: [String]
        @Guide(description: "需要後續處理的事項；沒有就回傳空陣列")
        var actionItems: [String]
    }

    /// 模型不可用時回傳原因文字；可用回傳 nil。UI 用這個決定摘要按鈕是否可按。
    public static func availabilityMessage() -> String? {
        EventOrganizer.availabilityMessage()
    }

    public static func generateSummary(
        from segments: [TranscriptSegment],
        sessionID: String,
        locale: Locale,
        now: @Sendable () -> Date = { Date() }
    ) async throws -> TranscriptSummary {
        let finals = segments.filter(\.isFinal).sorted { $0.startSeconds < $1.startSeconds }
        guard !finals.isEmpty else {
            return buildSummary(
                content: "", keyPoints: [], actionItems: [], segments: finals,
                sessionID: sessionID, createdAt: now())
        }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw SummaryError.modelUnavailable(availabilityMessage() ?? "本機模型不可用。")
        }
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions))
        let transcript = finals
            .map { "[\(Int($0.startSeconds))-\(Int($0.endSeconds))] \($0.text)" }
            .joined(separator: "\n")
        let prompt = """
            以下是 locale \(locale.identifier) 的完整逐字稿，行首為錄音秒數區間。
            請整理整份逐字稿的摘要、重點與待辦：

            \(transcript)
            """
        let createdAt = Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        do {
            // 經閘門序列化，避免與「整理」同時打本機模型造成 generationFailed。
            let response = try await OnDeviceModelGate.shared.run {
                try await session.respond(to: prompt, generating: SummaryFields.self)
            }
            return buildSummary(
                content: response.content.content,
                keyPoints: response.content.keyPoints,
                actionItems: response.content.actionItems,
                segments: finals,
                sessionID: sessionID,
                createdAt: createdAt)
        } catch {
            throw SummaryError.generationFailed(error.localizedDescription)
        }
    }

    /// 拆成純值函式以便單元測試：summary 來源涵蓋所有 finalized segments，
    /// 空白重點／待辦會被移除，摘要預設不標需複查。
    static func buildSummary(
        content: String,
        keyPoints: [String],
        actionItems: [String],
        segments: [TranscriptSegment],
        sessionID: String,
        createdAt: Date
    ) -> TranscriptSummary {
        let finals = segments.filter(\.isFinal).sorted { $0.startSeconds < $1.startSeconds }
        return TranscriptSummary(
            summaryID: "sum_0001",
            sessionID: sessionID,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            keyPoints: compactLines(keyPoints),
            actionItems: compactLines(actionItems),
            needsReview: false,
            sourceSegmentIDs: finals.map(\.segmentID),
            createdAt: createdAt)
    }

    static let instructions = """
        你是論文口試、會議與訪談記錄的整理助手。根據完整逐字稿產生整份內容摘要。
        只整理逐字稿中出現的資訊，不得杜撰；不確定的待辦不要加入。
        全部欄位以繁體中文輸出，語氣中性、可供使用者後續編修。
        """

    private static func compactLines(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
