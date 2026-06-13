import Foundation
import Testing
@testable import SSCore

private struct MockSummaryClient: CloudLLMClient {
    let reply: String
    func complete(system: String, user: String) async throws -> String { reply }
}

struct CloudTranscriptSummarizerTests {
    private func seg(_ id: String, _ s: Double, _ e: Double, _ t: String) -> TranscriptSegment {
        TranscriptSegment(segmentID: id, sessionID: "s1", startSeconds: s, endSeconds: e,
                          text: t, isFinal: true, language: "zh-TW", engine: "SpeechAnalyzer",
                          model: "system")
    }

    @Test func summarize_組出摘要且來源涵蓋finalized() async throws {
        let reply = #"{"content":"本場討論研究方法與貢獻","keyPoints":["方法","貢獻"],"actionItems":["補實驗"]}"#
        let segs = [seg("seg1", 0, 5, "方法說明"), seg("seg2", 5, 9, "貢獻說明")]
        let s = try await CloudTranscriptSummarizer(client: MockSummaryClient(reply: reply))
            .summarize(from: segs, sessionID: "s1", locale: Locale(identifier: "zh_TW"))
        #expect(s.content == "本場討論研究方法與貢獻")
        #expect(s.keyPoints == ["方法", "貢獻"])
        #expect(s.actionItems == ["補實驗"])
        #expect(s.sourceSegmentIDs == ["seg1", "seg2"])
    }

    @Test func 空逐字稿回傳空摘要() async throws {
        let s = try await CloudTranscriptSummarizer(client: MockSummaryClient(reply: "{}"))
            .summarize(from: [], sessionID: "s1", locale: Locale(identifier: "zh_TW"))
        #expect(s.content.isEmpty)
        #expect(s.sourceSegmentIDs.isEmpty)
    }
}
