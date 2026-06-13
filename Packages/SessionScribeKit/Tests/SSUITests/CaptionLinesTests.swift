import Foundation
import SSCore
import Testing

@testable import SSUI

@Suite("CaptionLines")
struct CaptionLinesTests {

    private func segment(_ id: String, _ text: String, start: Double) -> TranscriptSegment {
        TranscriptSegment(
            segmentID: id, sessionID: "s1", startSeconds: start, endSeconds: start + 1,
            text: text, isFinal: true, language: "zh-TW", engine: "mock", model: "mock",
            createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test("空逐字稿且無 volatile：兩行皆空")
    func emptyState() {
        let lines = CaptionLines.derive(transcript: [], volatileText: nil)
        #expect(lines.isEmpty)
        #expect(lines.previous == nil)
        #expect(lines.current == nil)
        #expect(lines.isVolatile == false)
    }

    @Test("有 volatile：當前句取 volatile、前一句取最後一句 finalized")
    func volatileTakesCurrentLastFinalIsPrevious() {
        let transcript = [segment("seg_1", "第一句", start: 0), segment("seg_2", "第二句", start: 1)]
        let lines = CaptionLines.derive(transcript: transcript, volatileText: "正在說的")

        #expect(lines.current == "正在說的")
        #expect(lines.isVolatile)
        #expect(lines.previous == "第二句")
    }

    @Test("無 volatile：當前句取最後一句、前一句取倒數第二句")
    func noVolatileRollsTwoFinalized() {
        let transcript = [
            segment("seg_1", "第一句", start: 0),
            segment("seg_2", "第二句", start: 1),
            segment("seg_3", "第三句", start: 2),
        ]
        let lines = CaptionLines.derive(transcript: transcript, volatileText: nil)

        #expect(lines.current == "第三句")
        #expect(lines.previous == "第二句")
        #expect(lines.isVolatile == false)
    }

    @Test("只有一句 finalized：前一句為空")
    func singleFinalizedHasNoPrevious() {
        let lines = CaptionLines.derive(
            transcript: [segment("seg_1", "唯一一句", start: 0)], volatileText: nil)

        #expect(lines.current == "唯一一句")
        #expect(lines.previous == nil)
    }

    @Test("volatile 為空白字串視同無 volatile")
    func blankVolatileTreatedAsNone() {
        let transcript = [segment("seg_1", "第一句", start: 0)]
        let lines = CaptionLines.derive(transcript: transcript, volatileText: "   ")

        #expect(lines.current == "第一句")
        #expect(lines.isVolatile == false)
    }

    @Test("無 volatile：當前句與前一句各帶對應 segmentID 的譯文")
    func translationsAttachedBySegmentID() {
        let transcript = [
            segment("seg_1", "第一句", start: 0),
            segment("seg_2", "第二句", start: 1),
        ]
        let lines = CaptionLines.derive(
            transcript: transcript, volatileText: nil,
            translations: ["seg_1": "first", "seg_2": "second"])

        #expect(lines.current == "第二句")
        #expect(lines.currentTranslation == "second")
        #expect(lines.previous == "第一句")
        #expect(lines.previousTranslation == "first")
    }

    @Test("有 volatile：前一句帶譯文、當前句（volatile）無譯文")
    func volatileHasNoTranslationButPreviousDoes() {
        let transcript = [segment("seg_1", "第一句", start: 0)]
        let lines = CaptionLines.derive(
            transcript: transcript, volatileText: "正在說的",
            translations: ["seg_1": "first"])

        #expect(lines.current == "正在說的")
        #expect(lines.currentTranslation == nil)
        #expect(lines.previousTranslation == "first")
    }
}
