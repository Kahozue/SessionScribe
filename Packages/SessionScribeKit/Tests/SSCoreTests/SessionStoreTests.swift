import Foundation
import Testing
@testable import SSCore

private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SSCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeSession(id: String = "2026-06-15_1000_a3f2") -> Session {
    Session(
        sessionID: id,
        title: "碩士論文口試 - 第一場",
        templateID: "thesis_defense",
        createdAt: Date(timeIntervalSince1970: 1_781_402_400),
        locale: "zh-TW",
        appVersion: "0.1.0"
    )
}

@Suite("SessionStore")
struct SessionStoreTests {

    @Test("create 建立規格書第八節的資料夾結構")
    func createBuildsFolderStructure() async throws {
        let root = try makeTempRoot()
        let store = try await SessionStore.create(makeSession(), in: root)

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        #expect(store.directory == root.appending(path: "2026-06-15_1000_a3f2"))
        #expect(fm.fileExists(atPath: store.directory.appending(path: "metadata.json").path))
        #expect(
            fm.fileExists(
                atPath: store.directory.appending(path: "audio").path, isDirectory: &isDirectory)
                && isDirectory.boolValue)
        #expect(
            fm.fileExists(
                atPath: store.directory.appending(path: "exports").path, isDirectory: &isDirectory)
                && isDirectory.boolValue)
    }

    @Test("metadata 寫入後可讀回且不失真")
    func metadataRoundTrip() async throws {
        let root = try makeTempRoot()
        let session = makeSession()
        let store = try await SessionStore.create(session, in: root)
        let loaded = try await store.loadMetadata()
        #expect(loaded == session)
    }

    @Test("saveMetadata 覆寫既有 metadata")
    func saveMetadataOverwrites() async throws {
        let root = try makeTempRoot()
        var session = makeSession()
        let store = try await SessionStore.create(session, in: root)

        session.endedAt = Date(timeIntervalSince1970: 1_781_409_600)
        session.title = "改過的標題"
        try await store.saveMetadata(session)

        let loaded = try await store.loadMetadata()
        #expect(loaded == session)
    }

    @Test("同名 session 資料夾已存在時 create 拋錯")
    func createThrowsIfDirectoryExists() async throws {
        let root = try makeTempRoot()
        _ = try await SessionStore.create(makeSession(), in: root)
        await #expect(throws: (any Error).self) {
            _ = try await SessionStore.create(makeSession(), in: root)
        }
    }

    @Test("segment 逐筆 append 後可依序讀回")
    func segmentsAppendAndLoad() async throws {
        let root = try makeTempRoot()
        let store = try await SessionStore.create(makeSession(), in: root)
        let segments = (1...3).map { index in
            TranscriptSegment(
                segmentID: String(format: "seg_%04d", index),
                sessionID: "2026-06-15_1000_a3f2",
                startSeconds: Double(index) * 10,
                endSeconds: Double(index) * 10 + 5,
                text: "第 \(index) 段",
                isFinal: true,
                language: "zh-TW",
                engine: "Mock",
                model: "mock",
                createdAt: Date(timeIntervalSince1970: 1_781_402_400)
            )
        }
        for segment in segments {
            try await store.appendSegment(segment)
        }
        let loaded = try await store.loadSegments()
        #expect(loaded == segments)
    }

    @Test("marker 逐筆 append 後可依序讀回")
    func markersAppendAndLoad() async throws {
        let root = try makeTempRoot()
        let store = try await SessionStore.create(makeSession(), in: root)
        let markers = (1...3).map { index in
            Marker(
                markerID: String(format: "m_%04d", index),
                sessionID: "2026-06-15_1000_a3f2",
                mediaSeconds: Double(index) * 60,
                type: MarkerType.question.rawValue,
                label: MarkerType.question.label,
                createdAt: Date(timeIntervalSince1970: 1_781_402_400)
            )
        }
        for marker in markers {
            try await store.appendMarker(marker)
        }
        let loaded = try await store.loadMarkers()
        #expect(loaded == markers)
    }

    @Test("marker 可重寫以取消標記，後續 append 仍寫入目前檔案")
    func markersCanBeRewrittenForCancellation() async throws {
        let root = try makeTempRoot()
        let session = makeSession()
        let store = try await SessionStore.create(session, in: root)
        let markers = (1...3).map { index in
            Marker(
                markerID: String(format: "m_%04d", index),
                sessionID: session.sessionID,
                mediaSeconds: Double(index) * 10,
                type: MarkerType.defaults[index - 1].rawValue,
                label: MarkerType.defaults[index - 1].label,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        try await store.appendMarker(markers[0])
        try await store.appendMarker(markers[1])
        try await store.saveMarkers([markers[1]])
        try await store.appendMarker(markers[2])

        let loaded = try await store.loadMarkers()
        #expect(loaded == [markers[1], markers[2]])

        let markerLines = try String(
            contentsOf: store.directory.appending(path: SessionFiles.manualMarkers),
            encoding: .utf8
        )
        .split(separator: "\n")
        #expect(markerLines.count == 2)
    }

    @Test("segment 與 marker 寫入規格書指定的檔名，一筆一行")
    func writesToSpecFileNames() async throws {
        let root = try makeTempRoot()
        let store = try await SessionStore.create(makeSession(), in: root)
        try await store.appendSegment(
            TranscriptSegment(
                segmentID: "seg_0001", sessionID: "s", startSeconds: 0, endSeconds: 1,
                text: "a", isFinal: true, language: "zh-TW", engine: "Mock", model: "mock",
                createdAt: Date(timeIntervalSince1970: 0)))
        try await store.appendMarker(
            Marker(
                markerID: "m_0001", sessionID: "s", mediaSeconds: 0,
                type: "question", label: "問題", createdAt: Date(timeIntervalSince1970: 0)))

        let segmentsFile = store.directory.appending(path: "live_segments.jsonl")
        let markersFile = store.directory.appending(path: "manual_markers.jsonl")
        let segmentLines = try String(contentsOf: segmentsFile, encoding: .utf8)
            .split(separator: "\n")
        let markerLines = try String(contentsOf: markersFile, encoding: .utf8)
            .split(separator: "\n")
        #expect(segmentLines.count == 1)
        #expect(markerLines.count == 1)
    }

    @Test("既有 session 目錄可重新開啟並續寫")
    func reopenExistingSession() async throws {
        let root = try makeTempRoot()
        let session = makeSession()
        let first = try await SessionStore.create(session, in: root)
        try await first.appendMarker(
            Marker(
                markerID: "m_0001", sessionID: session.sessionID, mediaSeconds: 1,
                type: "question", label: "問題", createdAt: Date(timeIntervalSince1970: 0)))

        let second = SessionStore(directory: root.appending(path: session.sessionID))
        try await second.appendMarker(
            Marker(
                markerID: "m_0002", sessionID: session.sessionID, mediaSeconds: 2,
                type: "suggestion", label: "建議", createdAt: Date(timeIntervalSince1970: 0)))
        let loaded = try await second.loadMarkers()
        #expect(loaded.map(\.markerID) == ["m_0001", "m_0002"])
    }

    @Test func resetSegments後重寫不重複() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "ss-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let session = Session(
            sessionID: "s1", title: "t", templateID: "thesis_defense", locale: "zh-TW",
            appVersion: "0.1.0")
        let store = try await SessionStore.create(session, in: tmp)
        func seg(_ id: String, _ start: Double) -> TranscriptSegment {
            TranscriptSegment(segmentID: id, sessionID: "s1", startSeconds: start,
                endSeconds: start + 1, text: "x", isFinal: true,
                language: "zh-TW", engine: "mock", model: "m")
        }
        try await store.appendSegment(seg("a", 0))
        try await store.appendSegment(seg("b", 1))
        #expect(try await store.loadSegments().count == 2)

        try await store.resetSegments()
        #expect(try await store.loadSegments().isEmpty)

        try await store.appendSegment(seg("c", 0))
        let after = try await store.loadSegments()
        #expect(after.map(\.segmentID) == ["c"])
    }
}
