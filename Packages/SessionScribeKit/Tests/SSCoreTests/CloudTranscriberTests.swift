import Foundation
import Testing
@testable import SSCore

struct CloudTranscriberTests {
    @Test func STT段落對應為TranscriptSegment() {
        let stt = [
            CloudSTTSegment(startSeconds: 0, endSeconds: 1.5, text: "甲"),
            CloudSTTSegment(startSeconds: 1.5, endSeconds: 3, text: "乙"),
        ]
        let segs = CloudTranscriber.makeSegments(
            from: stt, sessionID: "s1", language: "zh-TW", model: "whisper-1")
        #expect(segs.count == 2)
        #expect(segs[0].sessionID == "s1")
        #expect(segs[0].text == "甲")
        #expect(segs[1].startSeconds == 1.5)
        #expect(segs.allSatisfy { $0.isFinal })
        #expect(segs.allSatisfy { $0.engine == "cloud" })
        #expect(Set(segs.map(\.segmentID)).count == 2)
    }

    @Test func 空輸入回空陣列() {
        #expect(CloudTranscriber.makeSegments(
            from: [], sessionID: "s1", language: "zh-TW", model: "m").isEmpty)
    }
}
