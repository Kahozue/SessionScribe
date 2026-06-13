import Foundation
import Testing
@testable import SSCore

private struct MockCloudLLMClient: CloudLLMClient {
    let reply: String
    func complete(system: String, user: String) async throws -> String { reply }
}

struct CloudEventOrganizerTests {
    private func seg(_ id: String, _ s: Double, _ e: Double, _ t: String) -> TranscriptSegment {
        TranscriptSegment(segmentID: id, sessionID: "s1", startSeconds: s, endSeconds: e,
                          text: t, isFinal: true, language: "zh-TW", engine: "SpeechAnalyzer",
                          model: "system")
    }

    @Test func organize_補語意欄位且強制needsReview() async throws {
        let reply = #"{"topic":"研究貢獻","type":"問題","priority":"high","speakerRole":"口委","responseSummary":"請補實驗","actionItem":"補對照組","tags":["實驗"]}"#
        let event = StructuredEvent(
            eventID: "evt_0001", sessionID: "s1", startSeconds: 0, endSeconds: 10,
            speakerRole: "", type: "event", topic: "", content: "原始逐字稿內容",
            responseSummary: "", actionItem: "", priority: "medium", confidence: "low",
            needsReview: true, sourceSegmentIDs: ["seg1"], sourceMarkerIDs: ["m1"], tags: [],
            createdAt: Date(timeIntervalSince1970: 0))
        let organizer = CloudEventOrganizer(client: MockCloudLLMClient(reply: reply))
        let out = try await organizer.organize([event], locale: Locale(identifier: "zh_TW")) { _ in }
        #expect(out.count == 1)
        #expect(out[0].topic == "研究貢獻")
        #expect(out[0].priority == "high")
        #expect(out[0].content == "原始逐字稿內容")   // 不覆蓋 raw
        #expect(out[0].sourceMarkerIDs == ["m1"])     // 來源保留
        #expect(out[0].needsReview == true)
    }

    @Test func generateEvents_從逐字稿生成且content取原始文字() async throws {
        let reply = #"{"events":[{"topic":"開場","type":"重要","priority":"low","speakerRole":"學生","responseSummary":"自我介紹","actionItem":"","tags":["開場"],"startSeconds":0,"endSeconds":5}]}"#
        let segs = [seg("seg1", 0, 5, "大家好我是報告人")]
        let organizer = CloudEventOrganizer(client: MockCloudLLMClient(reply: reply))
        let out = try await organizer.generateEvents(from: segs, sessionID: "s1",
            locale: Locale(identifier: "zh_TW"))
        #expect(out.count == 1)
        #expect(out[0].content == "大家好我是報告人")
        #expect(out[0].sourceSegmentIDs == ["seg1"])
        #expect(out[0].needsReview == true)
    }
}
