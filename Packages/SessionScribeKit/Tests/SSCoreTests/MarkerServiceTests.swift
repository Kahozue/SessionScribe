import Foundation
import Testing
@testable import SSCore

private func makeSegment(
    id: String, start: Double, end: Double, text: String = "內容", isFinal: Bool = true
) -> TranscriptSegment {
    TranscriptSegment(
        segmentID: id, sessionID: "s", startSeconds: start, endSeconds: end,
        text: text, isFinal: isFinal, language: "zh-TW", engine: "Mock", model: "mock",
        createdAt: Date(timeIntervalSince1970: 0))
}

@Suite("MarkerSegmentAssociation")
struct MarkerSegmentAssociationTests {

    @Test("取 marker 時間點前後視窗內重疊的 finalized segments")
    func overlappingSegmentsWithinWindow() {
        let segments = [
            makeSegment(id: "seg_0001", start: 20, end: 50),    // 視窗外（end < 70）
            makeSegment(id: "seg_0002", start: 60, end: 80),    // 重疊視窗起點
            makeSegment(id: "seg_0003", start: 95, end: 105),   // 跨 marker 時間點
            makeSegment(id: "seg_0004", start: 125, end: 140),  // 重疊視窗終點
            makeSegment(id: "seg_0005", start: 140, end: 150),  // 視窗外（start > 130）
        ]
        let ids = MarkerSegmentAssociation.nearestSegmentIDs(
            for: 100, in: segments, window: 30)
        #expect(ids == ["seg_0002", "seg_0003", "seg_0004"])
    }

    @Test("volatile segment 不納入關聯")
    func excludesNonFinalSegments() {
        let segments = [
            makeSegment(id: "seg_0001", start: 95, end: 105),
            makeSegment(id: "seg_0002", start: 98, end: 102, isFinal: false),
        ]
        let ids = MarkerSegmentAssociation.nearestSegmentIDs(for: 100, in: segments, window: 30)
        #expect(ids == ["seg_0001"])
    }

    @Test("無 segment 時回傳空陣列")
    func emptySegments() {
        #expect(MarkerSegmentAssociation.nearestSegmentIDs(for: 0, in: [], window: 30).isEmpty)
    }
}

@Suite("MarkerService")
struct MarkerServiceTests {

    private func makeFixture() async throws -> (MarkerService, SessionStore) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = Session(
            sessionID: "2026-06-15_1000_a3f2", title: "測試", templateID: "thesis_defense",
            createdAt: Date(timeIntervalSince1970: 1_781_402_400), locale: "zh-TW",
            appVersion: "0.1.0")
        let store = try await SessionStore.create(session, in: root)
        let service = MarkerService(
            store: store, sessionID: session.sessionID,
            now: { Date(timeIntervalSince1970: 1_781_402_500) })
        return (service, store)
    }

    @Test("marker id 依序編號且立即落盤")
    func sequentialIDsAndImmediatePersistence() async throws {
        let (service, store) = try await makeFixture()
        let first = try await service.addMarker(
            type: .question, mediaSeconds: 10, segments: [])
        let second = try await service.addMarker(
            type: .suggestion, mediaSeconds: 20, segments: [])
        #expect(first.markerID == "m_0001")
        #expect(second.markerID == "m_0002")
        let persisted = try await store.loadMarkers()
        #expect(persisted.map(\.markerID) == ["m_0001", "m_0002"])
        #expect(persisted[0].type == "question")
        #expect(persisted[0].label == "問題")
        #expect(persisted[1].type == "suggestion")
    }

    @Test("建立當下快照鄰近 segment ids")
    func snapshotsNearestSegments() async throws {
        let (service, _) = try await makeFixture()
        let segments = [
            makeSegment(id: "seg_0001", start: 5, end: 12),
            makeSegment(id: "seg_0002", start: 200, end: 210),
        ]
        let marker = try await service.addMarker(
            type: .question, mediaSeconds: 10, segments: segments)
        #expect(marker.nearestSegmentIDs == ["seg_0001"])
    }

    @Test("既有 marker 數量接續編號（重新開啟 session）")
    func continuesNumberingFromExistingCount() async throws {
        let (_, store) = try await makeFixture()
        let resumed = MarkerService(
            store: store, sessionID: "2026-06-15_1000_a3f2", existingCount: 7,
            now: { Date(timeIntervalSince1970: 0) })
        let marker = try await resumed.addMarker(type: .question, mediaSeconds: 1, segments: [])
        #expect(marker.markerID == "m_0008")
    }

    @Test("note 可選且預設為空")
    func noteDefaultsToEmpty() async throws {
        let (service, _) = try await makeFixture()
        let marker = try await service.addMarker(
            type: .importantAnswer, mediaSeconds: 30, segments: [], note: "重點")
        #expect(marker.note == "重點")
        let plain = try await service.addMarker(type: .question, mediaSeconds: 31, segments: [])
        #expect(plain.note.isEmpty)
    }
}

@Suite("TimeFormatting")
struct TimeFormattingTests {

    @Test("秒數格式化為 HH:mm:ss")
    func formatsHoursMinutesSeconds() {
        #expect(TimeFormatting.hms(0) == "00:00:00")
        #expect(TimeFormatting.hms(12.3) == "00:00:12")
        #expect(TimeFormatting.hms(2538.0) == "00:42:18")
        #expect(TimeFormatting.hms(3725) == "01:02:05")
    }
}
