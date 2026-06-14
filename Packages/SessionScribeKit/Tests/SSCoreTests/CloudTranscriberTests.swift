import Foundation
import Testing
@testable import SSCore

struct CloudTranscriberTests {
    @Test func STT段落對應為TranscriptSegment() {
        let stt = [
            CloudSTTSegment(startSeconds: 0, endSeconds: 1.5, text: "甲", speaker: "speaker_0"),
            CloudSTTSegment(startSeconds: 1.5, endSeconds: 3, text: "乙", speaker: "speaker_1"),
        ]
        let segs = CloudTranscriber.makeSegments(
            from: stt, sessionID: "s1", language: "zh-TW",
            model: "gpt-4o-transcribe-diarize")
        #expect(segs.count == 2)
        #expect(segs[0].sessionID == "s1")
        #expect(segs[0].text == "甲")
        #expect(segs[0].speaker == "speaker_0")
        #expect(segs[1].startSeconds == 1.5)
        #expect(segs.allSatisfy { $0.isFinal })
        #expect(segs.allSatisfy { $0.engine == "cloud" })
        #expect(Set(segs.map(\.segmentID)).count == 2)
    }

    @Test func 空輸入回空陣列() {
        #expect(CloudTranscriber.makeSegments(
            from: [], sessionID: "s1", language: "zh-TW", model: "m").isEmpty)
    }

    @Test func 單段全文無時間戳時用音訊總長補結束時間() {
        let stt = [
            CloudSTTSegment(startSeconds: 0, endSeconds: 0, text: "整段逐字稿"),
        ]
        let segs = CloudTranscriber.makeSegments(
            from: stt, sessionID: "s1", language: "zh-TW",
            model: "gpt-4o-mini-transcribe", fallbackEndSeconds: 226.47)
        #expect(segs.count == 1)
        #expect(segs[0].startSeconds == 0)
        #expect(segs[0].endSeconds == 226.47)
        #expect(segs[0].speaker == nil)
    }
}
