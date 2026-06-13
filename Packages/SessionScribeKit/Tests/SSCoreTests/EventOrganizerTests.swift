import Foundation
import Testing

@testable import SSCore

@Suite("EventOrganizer 套回邏輯（v0.2 本機 LLM 整理）")
struct EventOrganizerTests {

    private func makeEvent() -> StructuredEvent {
        StructuredEvent(
            eventID: "evt_0001", sessionID: "s1", startSeconds: 10, endSeconds: 20,
            type: "question", topic: "原主題", content: "原始逐字稿內容",
            priority: "low", confidence: "low", needsReview: false,
            sourceSegmentIDs: ["seg_1", "seg_2"], sourceMarkerIDs: ["m_1"],
            createdAt: Date(timeIntervalSince1970: 100))
    }

    @Test("只改語意欄位；content、來源、時間、建立時間不動，needs_review 強制 true")
    func preservesSourceFields() {
        let result = EventOrganizer.applyOrganized(
            topic: "資料集代表性", type: "問題", priority: "high",
            speakerRole: "口委", responseSummary: "說明資料來源限制", actionItem: "補充代表性說明",
            tags: ["資料集", "方法"], to: makeEvent())

        #expect(result.topic == "資料集代表性")
        #expect(result.type == "問題")
        #expect(result.priority == "high")
        #expect(result.speakerRole == "口委")
        #expect(result.responseSummary == "說明資料來源限制")
        #expect(result.actionItem == "補充代表性說明")
        #expect(result.tags == ["資料集", "方法"])
        // AI 產物一律 needs_review。
        #expect(result.needsReview)
        // 來源與原始逐字稿不得被覆蓋。
        #expect(result.content == "原始逐字稿內容")
        #expect(result.sourceSegmentIDs == ["seg_1", "seg_2"])
        #expect(result.sourceMarkerIDs == ["m_1"])
        #expect(result.startSeconds == 10)
        #expect(result.endSeconds == 20)
        #expect(result.createdAt == Date(timeIntervalSince1970: 100))
        #expect(result.eventID == "evt_0001")
    }

    @Test("空欄位與不合法 priority 不覆蓋原值")
    func keepsOriginalOnEmptyOrInvalid() {
        let event = StructuredEvent(
            eventID: "evt_0002", sessionID: "s1", startSeconds: 0, endSeconds: 1,
            type: "question", topic: "原主題", content: "內容",
            priority: "medium", confidence: "low",
            sourceSegmentIDs: [], sourceMarkerIDs: [],
            createdAt: Date(timeIntervalSince1970: 0))
        let result = EventOrganizer.applyOrganized(
            topic: "", type: "", priority: "urgent",
            speakerRole: "", responseSummary: "", actionItem: "", tags: [], to: event)

        #expect(result.topic == "原主題")
        #expect(result.type == "question")
        #expect(result.priority == "medium")  // urgent 不合法，保留原值
        #expect(result.needsReview)
    }
}
