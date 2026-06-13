import Foundation
import Testing

@testable import SSCore

@Suite("TranscriptSummary 模型（transcript_summary.json，v0.3）")
struct TranscriptSummaryTests {

    @Test("編碼輸出 snake_case 鍵且摘要預設不標需複查")
    func encodingMatchesSpec() throws {
        let summary = TranscriptSummary(
            summaryID: "sum_0001",
            sessionID: "s1",
            content: "本場主要討論研究方法與資料集限制。",
            keyPoints: ["研究方法需補強", "資料集代表性需說明"],
            actionItems: ["補充資料集代表性段落"],
            sourceSegmentIDs: ["seg_1", "seg_2"],
            createdAt: Date(timeIntervalSince1970: 1_781_488_800))

        let data = try SSJSON.lineEncoder.encode(summary)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["summary_id"] as? String == "sum_0001")
        #expect(object["session_id"] as? String == "s1")
        #expect(object["key_points"] as? [String] == ["研究方法需補強", "資料集代表性需說明"])
        #expect(object["action_items"] as? [String] == ["補充資料集代表性段落"])
        #expect(object["needs_review"] as? Bool == false)
        #expect(object["source_segment_ids"] as? [String] == ["seg_1", "seg_2"])
    }

    @Test("transcript_summary.json 原子寫入與讀回；不存在回傳 nil")
    func summaryFileRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(try TranscriptSummaryFile.readIfPresent(from: root) == nil)

        let document = TranscriptSummaryDocument(summary: TranscriptSummary(
            summaryID: "sum_0001",
            sessionID: "s1",
            content: "摘要內容",
            keyPoints: ["重點"],
            actionItems: [],
            sourceSegmentIDs: ["seg_1"],
            createdAt: Date(timeIntervalSince1970: 100)))

        try TranscriptSummaryFile.write(document, to: root)
        let loaded = try #require(try TranscriptSummaryFile.readIfPresent(from: root))
        #expect(loaded == document)
    }
}

@Suite("TranscriptSummarizer 套回邏輯（v0.3 本機 LLM 摘要）")
struct TranscriptSummarizerTests {

    @Test("從整份 finalized 逐字稿建立摘要，來源涵蓋所有 finalized segments 且不標需複查")
    func buildSummaryUsesAllFinalSegmentsAsSources() {
        let segments = [
            TranscriptSegment(
                segmentID: "seg_1", sessionID: "s1", startSeconds: 0, endSeconds: 5,
                text: "第一段", isFinal: true, language: "zh-TW", engine: "e", model: "m",
                createdAt: Date(timeIntervalSince1970: 0)),
            TranscriptSegment(
                segmentID: "seg_volatile", sessionID: "s1", startSeconds: 5, endSeconds: 8,
                text: "未定稿", isFinal: false, language: "zh-TW", engine: "e", model: "m",
                createdAt: Date(timeIntervalSince1970: 0)),
            TranscriptSegment(
                segmentID: "seg_2", sessionID: "s1", startSeconds: 8, endSeconds: 13,
                text: "第二段", isFinal: true, language: "zh-TW", engine: "e", model: "m",
                createdAt: Date(timeIntervalSince1970: 0)),
        ]

        let summary = TranscriptSummarizer.buildSummary(
            content: "本場討論兩個重點。",
            keyPoints: ["第一重點", "", "第二重點"],
            actionItems: ["待辦"],
            segments: segments,
            sessionID: "s1",
            createdAt: Date(timeIntervalSince1970: 100))

        #expect(summary.summaryID == "sum_0001")
        #expect(summary.sessionID == "s1")
        #expect(summary.content == "本場討論兩個重點。")
        #expect(summary.keyPoints == ["第一重點", "第二重點"])
        #expect(summary.actionItems == ["待辦"])
        #expect(summary.sourceSegmentIDs == ["seg_1", "seg_2"])
        #expect(!summary.needsReview)
        #expect(summary.createdAt == Date(timeIntervalSince1970: 100))
    }
}
