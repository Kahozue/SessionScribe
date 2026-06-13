import Foundation
import SSCore
import Testing

@testable import SSTranscription

@Suite("TranslationCoordinator")
struct TranslationCoordinatorTests {

    private let source = CaptionLanguage.english.language
    private let target = CaptionLanguage.zhTW.language

    private func collect(
        _ coordinator: TranslationCoordinator
    ) async -> Task<[TranslatedSegment], Never> {
        let stream = await coordinator.updates()
        return Task {
            var out: [TranslatedSegment] = []
            for await segment in stream {
                out.append(segment)
            }
            return out
        }
    }

    @Test("prepare 成功後逐段翻譯，segmentID 對應、依序轉發")
    func translatesEachSegmentInOrder() async {
        let coordinator = TranslationCoordinator(translator: MockTranslator())
        let collector = await collect(coordinator)

        await coordinator.prepare(source: source, target: target)
        await coordinator.translate(segmentID: "seg_1", text: "hello")
        await coordinator.translate(segmentID: "seg_2", text: "world")
        await coordinator.finish()

        let result = await collector.value
        #expect(
            result == [
                TranslatedSegment(segmentID: "seg_1", text: "譯：hello"),
                TranslatedSegment(segmentID: "seg_2", text: "譯：world"),
            ])
        let failed = await coordinator.preparationFailed
        #expect(failed == false)
    }

    @Test("prepare 失敗：translate 全短路、不轉發，preparationFailed 為真")
    func prepareFailureShortCircuits() async {
        let coordinator = TranslationCoordinator(
            translator: MockTranslator(failPrepare: true))
        let collector = await collect(coordinator)

        await coordinator.prepare(source: source, target: target)
        await coordinator.translate(segmentID: "seg_1", text: "hello")
        await coordinator.finish()

        let result = await collector.value
        #expect(result.isEmpty)
        let failed = await coordinator.preparationFailed
        #expect(failed)
    }

    @Test("單段 translate 失敗：該段不轉發，後續段落續譯")
    func perSegmentFailureDoesNotStopOthers() async {
        let coordinator = TranslationCoordinator(
            translator: MockTranslator(failTranslateContaining: ["bad"]))
        let collector = await collect(coordinator)

        await coordinator.prepare(source: source, target: target)
        await coordinator.translate(segmentID: "seg_1", text: "good one")
        await coordinator.translate(segmentID: "seg_2", text: "a bad one")
        await coordinator.translate(segmentID: "seg_3", text: "good two")
        await coordinator.finish()

        let result = await collector.value
        #expect(result.map(\.segmentID) == ["seg_1", "seg_3"])
    }

    @Test("空白文字不翻譯")
    func blankTextSkipped() async {
        let coordinator = TranslationCoordinator(translator: MockTranslator())
        let collector = await collect(coordinator)

        await coordinator.prepare(source: source, target: target)
        await coordinator.translate(segmentID: "seg_1", text: "   ")
        await coordinator.finish()

        let result = await collector.value
        #expect(result.isEmpty)
    }
}
