import Foundation
import SSCore
import Testing

@testable import SSUI

@Suite("MarkerVisualStyle")
struct MarkerVisualStyleTests {

    @Test("Cmd+1 至 Cmd+4 的位置色票彼此不同")
    func shortcutSlotsUseDistinctKeys() {
        let keys = (0..<4).map { MarkerVisualStyle.style(forSlot: $0).key }

        #expect(keys == [.blue, .red, .green, .purple])
        #expect(Set(keys).count == 4)
    }

    @Test("同一 type 在不同模板中依四鍵位置取色")
    func markerUsesTemplateSlotBeforeSemanticFallback() {
        let meeting = SessionTemplate.template(for: "meeting")
        let marker = Marker(
            markerID: "m_1", sessionID: "s1", mediaSeconds: 12,
            type: "question", label: "問題",
            createdAt: Date(timeIntervalSince1970: 0))

        let style = MarkerVisualStyle.style(for: marker, template: meeting)

        #expect(style.key == .purple)
    }

    @Test("AI 整理改 event.type 後仍用來源 marker 找回原本色票")
    func eventUsesSourceMarkerColorBeforeOrganizedType() {
        let marker = Marker(
            markerID: "m_1", sessionID: "s1", mediaSeconds: 12,
            type: "question", label: "問題",
            createdAt: Date(timeIntervalSince1970: 0))
        let event = StructuredEvent(
            eventID: "evt_1", sessionID: "s1", startSeconds: 10, endSeconds: 20,
            type: "問題", topic: "資料集代表性", content: "內容",
            priority: "medium", confidence: "low",
            sourceSegmentIDs: ["seg_1"], sourceMarkerIDs: ["m_1"],
            createdAt: Date(timeIntervalSince1970: 0))

        let style = MarkerVisualStyle.style(
            for: event,
            markersByID: ["m_1": marker],
            template: SessionTemplate.template(for: "thesis_defense"))

        #expect(style.key == .blue)
    }

    @Test("逐字稿段落可依時間範圍取回內嵌標記")
    func transcriptSegmentFindsInlineMarkersByTime() {
        let segment = TranscriptSegment(
            segmentID: "seg_1", sessionID: "s1", startSeconds: 10, endSeconds: 20,
            text: "內容", isFinal: true, language: "zh-TW", engine: "mock", model: "mock",
            createdAt: Date(timeIntervalSince1970: 0))
        let markers = [
            Marker(
                markerID: "before", sessionID: "s1", mediaSeconds: 9.9,
                type: "question", label: "問題",
                createdAt: Date(timeIntervalSince1970: 0)),
            Marker(
                markerID: "inside", sessionID: "s1", mediaSeconds: 12,
                type: "question", label: "問題",
                createdAt: Date(timeIntervalSince1970: 0)),
            Marker(
                markerID: "after", sessionID: "s1", mediaSeconds: 20,
                type: "question", label: "問題",
                createdAt: Date(timeIntervalSince1970: 0)),
        ]

        let inline = MarkerTimeline.inlineMarkers(for: segment, markers: markers)

        #expect(inline.map(\.markerID) == ["inside"])
    }
}
