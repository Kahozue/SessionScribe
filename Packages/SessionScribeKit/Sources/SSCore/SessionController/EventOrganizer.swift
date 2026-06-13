import Foundation
import FoundationModels

/// 本機 LLM 事件整理（v0.2，aim.md 十四節第二段）：用 macOS 26 的
/// Foundation Models（on-device，零網路，符合沙盒）把機械草稿的語意欄位補齊。
/// 核心可靠性原則：AI 產物一律 needs_review、不覆蓋 raw transcript（content）、
/// 保留 source_segment_ids／source_marker_ids 追溯。
///
/// 來源：
/// - developer.apple.com/documentation/foundationmodels/systemlanguagemodel
/// - /documentation/foundationmodels/languagemodelsession/respond(to:generating:options:)
/// - /documentation/foundationmodels/generable
public enum EventOrganizer {

    public enum OrganizeError: Error, Sendable {
        case modelUnavailable(String)
        case generationFailed(String)
    }

    /// LLM 要填的語意欄位；以 @Generable 做結構化輸出，欄位描述用繁體中文。
    @Generable
    struct OrganizedFields {
        @Guide(description: "事件主題，六到十二字的精簡標題")
        var topic: String
        @Guide(description: "事件類型，例如 問題、回答、決議、建議、待辦、重要")
        var type: String
        @Guide(description: "優先程度，只能是 high、medium 或 low 三者之一")
        var priority: String
        @Guide(description: "發言者角色，例如 口委、學生、指導教授；不確定就留空字串")
        var speakerRole: String
        @Guide(description: "這段討論的回應或結論摘要，一到兩句；無法判斷留空")
        var responseSummary: String
        @Guide(description: "需要後續處理的待辦事項，沒有就留空字串")
        var actionItem: String
        @Guide(description: "一到四個關鍵字標籤")
        var tags: [String]
    }

    /// 模型不可用時回傳原因文字（裝置不符、未開 Apple Intelligence、模型未就緒等）；
    /// 可用回傳 nil。UI 用這個決定「AI 整理」按鈕是否可按。
    public static func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return Self.text(for: reason)
        @unknown default:
            return "本機模型目前不可用。"
        }
    }

    /// 對單一事件做整理，回傳填好語意欄位的新事件；來源欄位與 content 不動。
    public static func organize(
        _ event: StructuredEvent,
        locale: Locale
    ) async throws -> StructuredEvent {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw OrganizeError.modelUnavailable(availabilityMessage() ?? "本機模型不可用。")
        }
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions))
        let prompt = "以下是某個標記前後的逐字稿片段，請依指示整理成結構化欄位：\n\n\(event.content)"
        do {
            let response = try await session.respond(to: prompt, generating: OrganizedFields.self)
            return apply(response.content, to: event)
        } catch {
            throw OrganizeError.generationFailed(error.localizedDescription)
        }
    }

    /// 批次整理；逐筆呼叫（結構化輸出較穩、避免長 context），每完成一筆回報進度。
    public static func organize(
        _ events: [StructuredEvent],
        locale: Locale,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> [StructuredEvent] {
        var result: [StructuredEvent] = []
        result.reserveCapacity(events.count)
        for (index, event) in events.enumerated() {
            result.append(try await organize(event, locale: locale))
            progress(Double(index + 1) / Double(max(events.count, 1)))
        }
        return result
    }

    // MARK: - 私有

    private static let instructions = """
        你是論文口試與會議記錄的整理助手。根據使用者提供的逐字稿片段，整理出結構化欄位。
        只做整理與歸納，不得杜撰逐字稿沒有的內容；無法判斷的欄位一律留空字串。
        priority 僅能是 high、medium、low。全部欄位以繁體中文輸出。
        """

    private static func apply(_ fields: OrganizedFields, to event: StructuredEvent) -> StructuredEvent {
        applyOrganized(
            topic: fields.topic, type: fields.type, priority: fields.priority,
            speakerRole: fields.speakerRole, responseSummary: fields.responseSummary,
            actionItem: fields.actionItem, tags: fields.tags, to: event)
    }

    /// 把整理結果套回事件：只改語意欄位，content／來源／時間／建立時間不動，
    /// needs_review 強制為 true（aim.md 核心原則 8）。空欄位與不合法 priority 不覆蓋原值。
    /// 拆成純值參數以便單元測試（不依賴 @Generable 合成成員）。
    static func applyOrganized(
        topic: String,
        type: String,
        priority: String,
        speakerRole: String,
        responseSummary: String,
        actionItem: String,
        tags: [String],
        to event: StructuredEvent
    ) -> StructuredEvent {
        var updated = event
        if !topic.isEmpty { updated.topic = topic }
        if !type.isEmpty { updated.type = type }
        if ["high", "medium", "low"].contains(priority) {
            updated.priority = priority
        }
        updated.speakerRole = speakerRole
        updated.responseSummary = responseSummary
        updated.actionItem = actionItem
        updated.tags = tags
        updated.needsReview = true
        return updated
    }

    private static func text(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "這台裝置不支援 Apple Intelligence，無法使用 AI 整理。"
        case .appleIntelligenceNotEnabled:
            return "請先到系統設定開啟 Apple Intelligence，才能使用 AI 整理。"
        case .modelNotReady:
            return "本機模型尚未就緒（可能仍在下載），請稍後再試。"
        @unknown default:
            return "本機模型目前不可用。"
        }
    }
}
