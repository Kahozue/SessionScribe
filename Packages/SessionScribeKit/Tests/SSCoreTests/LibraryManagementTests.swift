import Foundation
import Testing
@testable import SSCore

private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SSCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeSession(id: String, title: String = "場次") -> Session {
    var session = Session(
        sessionID: id, title: title, templateID: "thesis_defense",
        createdAt: Date(timeIntervalSince1970: 1_781_488_800),
        locale: "zh-TW", appVersion: "0.1.0")
    session.endedAt = Date(timeIntervalSince1970: 1_781_492_400)
    return session
}

@Suite("LibraryConfig（分類定義，規格 1.1 第 7 項）")
struct LibraryConfigTests {

    @Test("不存在時讀回空設定")
    func missingFileYieldsEmptyConfig() throws {
        let root = try makeTempRoot()
        let config = try LibraryConfigFile.read(from: root)
        #expect(config.categories.isEmpty)
    }

    @Test("分類寫入後可讀回，依 order 排序")
    func roundTripSortedByOrder() throws {
        let root = try makeTempRoot()
        var config = LibraryConfig()
        config.categories = [
            SessionCategory(id: "c2", name: "會議", hidden: false, order: 1),
            SessionCategory(id: "c1", name: "口試", hidden: true, order: 0),
        ]
        try LibraryConfigFile.write(config, to: root)
        let loaded = try LibraryConfigFile.read(from: root)
        #expect(loaded.categories.map(\.id) == ["c1", "c2"])
        #expect(loaded.categories[0].hidden)
    }
}

@Suite("Session category_id 欄位")
struct SessionCategoryIDTests {

    @Test("舊 metadata 缺 category_id 視為未分類")
    func missingCategoryIDIsNil() throws {
        let json = """
        {
          "schema_version": 1, "session_id": "s", "title": "t",
          "template_id": "x", "created_at": "2026-06-15T10:00:00+08:00",
          "started_at": null, "ended_at": null, "locale": "zh-TW",
          "asr_engine": "", "privacy_mode": "local_only", "audio_input": "",
          "recovered": false, "notes": "", "app_version": "0.1.0"
        }
        """
        let session = try SSJSON.decoder.decode(Session.self, from: Data(json.utf8))
        #expect(session.categoryID == nil)
    }

    @Test("category_id 編解碼 round-trip")
    func categoryIDRoundTrips() throws {
        var session = makeSession(id: "2026-06-15_1000_cat1")
        session.categoryID = "c1"
        let data = try SSJSON.lineEncoder.encode(session)
        let decoded = try SSJSON.decoder.decode(Session.self, from: data)
        #expect(decoded.categoryID == "c1")
    }
}

@Suite("SessionLibrary 批次操作")
struct SessionLibraryBatchTests {

    @Test("批次指派分類後 metadata 落盤")
    func assignsCategoryInBatch() async throws {
        let root = try makeTempRoot()
        _ = try await SessionStore.create(makeSession(id: "2026-06-15_1000_aaa1"), in: root)
        _ = try await SessionStore.create(makeSession(id: "2026-06-15_1001_bbb2"), in: root)
        let library = SessionLibrary(rootDirectory: root)

        try library.assign(
            categoryID: "c9", to: ["2026-06-15_1000_aaa1", "2026-06-15_1001_bbb2"])
        let sessions = try library.sessions()
        #expect(sessions.allSatisfy { $0.categoryID == "c9" })

        // 指派 nil 即移回未分類。
        try library.assign(categoryID: nil, to: ["2026-06-15_1000_aaa1"])
        let updated = try library.sessions()
        #expect(updated.first { $0.sessionID == "2026-06-15_1000_aaa1" }?.categoryID == nil)
        #expect(updated.first { $0.sessionID == "2026-06-15_1001_bbb2" }?.categoryID == "c9")
    }

    @Test("批次刪除後列表不再包含，資料夾自原位移除")
    func deletesInBatch() async throws {
        let root = try makeTempRoot()
        _ = try await SessionStore.create(makeSession(id: "2026-06-15_1000_del1"), in: root)
        _ = try await SessionStore.create(makeSession(id: "2026-06-15_1001_keep"), in: root)
        let library = SessionLibrary(rootDirectory: root)

        try library.delete(sessionIDs: ["2026-06-15_1000_del1"])
        #expect(try library.sessions().map(\.sessionID) == ["2026-06-15_1001_keep"])
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appending(path: "2026-06-15_1000_del1").path))
    }
}

@Suite("TranscriptSearchService（規格 1.1 第 9 項）")
struct TranscriptSearchTests {

    private func makeFixture() async throws -> SessionLibrary {
        let root = try makeTempRoot()
        let first = try await SessionStore.create(
            makeSession(id: "2026-06-15_1000_se01", title: "口試第一場"), in: root)
        try await first.appendSegment(
            TranscriptSegment(
                segmentID: "seg_0001", sessionID: "2026-06-15_1000_se01",
                startSeconds: 10, endSeconds: 15, text: "請說明資料集的標註流程。",
                isFinal: true, language: "zh-TW", engine: "Mock", model: "mock",
                createdAt: Date(timeIntervalSince1970: 0)))
        try await first.appendMarker(
            Marker(
                markerID: "m_0001", sessionID: "2026-06-15_1000_se01", mediaSeconds: 12,
                type: "question", label: "問題", note: "標註一致性要補",
                createdAt: Date(timeIntervalSince1970: 0)))
        let second = try await SessionStore.create(
            makeSession(id: "2026-06-15_1100_se02", title: "會議"), in: root)
        try await second.appendSegment(
            TranscriptSegment(
                segmentID: "seg_0001", sessionID: "2026-06-15_1100_se02",
                startSeconds: 5, endSeconds: 9, text: "下一版要改用新的資料集。",
                isFinal: true, language: "zh-TW", engine: "Mock", model: "mock",
                createdAt: Date(timeIntervalSince1970: 0)))
        return SessionLibrary(rootDirectory: root)
    }

    @Test("跨 session 命中 segments，附媒體時間與片段")
    func findsAcrossSessions() async throws {
        let library = try await makeFixture()
        let service = TranscriptSearchService(library: library)
        let hits = try service.search("資料集")
        #expect(hits.count == 2)
        #expect(Set(hits.map(\.sessionID)) == ["2026-06-15_1000_se01", "2026-06-15_1100_se02"])
        let firstHit = try #require(hits.first { $0.sessionID == "2026-06-15_1000_se01" })
        #expect(firstHit.segmentID == "seg_0001")
        #expect(firstHit.mediaSeconds == 10)
        #expect(firstHit.snippet.contains("資料集"))
    }

    @Test("marker note 也納入搜尋")
    func findsMarkerNotes() async throws {
        let library = try await makeFixture()
        let service = TranscriptSearchService(library: library)
        let hits = try service.search("一致性")
        #expect(hits.count == 1)
        #expect(hits[0].markerID == "m_0001")
    }

    @Test("空白查詢回傳空結果")
    func emptyQueryYieldsNothing() async throws {
        let library = try await makeFixture()
        let service = TranscriptSearchService(library: library)
        #expect(try service.search("  ").isEmpty)
    }

    @Test("英文查詢不分大小寫")
    func caseInsensitive() async throws {
        let root = try makeTempRoot()
        let store = try await SessionStore.create(
            makeSession(id: "2026-06-15_1200_se03"), in: root)
        try await store.appendSegment(
            TranscriptSegment(
                segmentID: "seg_0001", sessionID: "2026-06-15_1200_se03",
                startSeconds: 0, endSeconds: 3, text: "我們用 BERT 做基線。",
                isFinal: true, language: "zh-TW", engine: "Mock", model: "mock",
                createdAt: Date(timeIntervalSince1970: 0)))
        let service = TranscriptSearchService(
            library: SessionLibrary(rootDirectory: root))
        #expect(try service.search("bert").count == 1)
    }
}
