import Foundation
import Testing
@testable import SSCore

private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SSCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeSession(
    id: String,
    createdAt: Date,
    endedAt: Date? = nil
) -> Session {
    var session = Session(
        sessionID: id,
        title: "場次 \(id)",
        templateID: "thesis_defense",
        createdAt: createdAt,
        locale: "zh-TW",
        appVersion: "0.1.0"
    )
    session.endedAt = endedAt
    return session
}

@Suite("SessionLibrary")
struct SessionLibraryTests {

    @Test("依 createdAt 由新到舊列出所有 session")
    func listsSessionsSortedByCreatedAtDescending() async throws {
        let root = try makeTempRoot()
        let older = makeSession(
            id: "2026-06-14_0900_aaaa", createdAt: Date(timeIntervalSince1970: 1_781_000_000),
            endedAt: Date(timeIntervalSince1970: 1_781_003_600))
        let newer = makeSession(
            id: "2026-06-15_1000_bbbb", createdAt: Date(timeIntervalSince1970: 1_781_402_400),
            endedAt: Date(timeIntervalSince1970: 1_781_406_000))
        _ = try await SessionStore.create(older, in: root)
        _ = try await SessionStore.create(newer, in: root)

        let library = SessionLibrary(rootDirectory: root)
        let sessions = try library.sessions()
        #expect(sessions.map(\.sessionID) == ["2026-06-15_1000_bbbb", "2026-06-14_0900_aaaa"])
    }

    @Test("略過散落檔案、缺 metadata 與 metadata 損毀的項目")
    func skipsNonSessionEntries() async throws {
        let root = try makeTempRoot()
        let fm = FileManager.default
        // 散落檔案。
        try Data("不是 session".utf8).write(to: root.appending(path: "stray.txt"))
        // 缺 metadata 的目錄。
        try fm.createDirectory(
            at: root.appending(path: "no-metadata"), withIntermediateDirectories: false)
        // metadata 損毀的目錄。
        let corrupted = root.appending(path: "corrupted")
        try fm.createDirectory(at: corrupted, withIntermediateDirectories: false)
        try Data("{broken".utf8).write(to: corrupted.appending(path: "metadata.json"))
        // 一個正常 session。
        let valid = makeSession(
            id: "2026-06-15_1000_cccc", createdAt: Date(timeIntervalSince1970: 1_781_402_400))
        _ = try await SessionStore.create(valid, in: root)

        let library = SessionLibrary(rootDirectory: root)
        let sessions = try library.sessions()
        #expect(sessions.map(\.sessionID) == ["2026-06-15_1000_cccc"])
    }

    @Test("root 不存在時回傳空列表")
    func missingRootReturnsEmpty() throws {
        let library = SessionLibrary(
            rootDirectory: FileManager.default.temporaryDirectory
                .appending(path: "SSCoreTests-nonexistent-\(UUID().uuidString)"))
        let sessions = try library.sessions()
        #expect(sessions.isEmpty)
    }

    @Test("恢復掃描：ended_at == null 的 session 標記 recovered 並落盤")
    func recoveryMarksCrashedSessions() async throws {
        let root = try makeTempRoot()
        let crashed = makeSession(
            id: "2026-06-15_1000_dddd", createdAt: Date(timeIntervalSince1970: 1_781_402_400))
        _ = try await SessionStore.create(crashed, in: root)

        let library = SessionLibrary(rootDirectory: root)
        let recovered = try library.recoverCrashedSessions()
        #expect(recovered.map(\.sessionID) == ["2026-06-15_1000_dddd"])
        #expect(recovered.allSatisfy { $0.recovered })

        // recovered: true 已持久化。
        let store = SessionStore(directory: root.appending(path: "2026-06-15_1000_dddd"))
        let reloaded = try await store.loadMetadata()
        #expect(reloaded.recovered)
        #expect(reloaded.endedAt == nil)
    }

    @Test("恢復掃描：已正常結束的 session 不受影響")
    func recoverySkipsEndedSessions() async throws {
        let root = try makeTempRoot()
        let ended = makeSession(
            id: "2026-06-15_1000_eeee", createdAt: Date(timeIntervalSince1970: 1_781_402_400),
            endedAt: Date(timeIntervalSince1970: 1_781_409_600))
        _ = try await SessionStore.create(ended, in: root)

        let library = SessionLibrary(rootDirectory: root)
        let recovered = try library.recoverCrashedSessions()
        #expect(recovered.isEmpty)

        let store = SessionStore(directory: root.appending(path: "2026-06-15_1000_eeee"))
        let reloaded = try await store.loadMetadata()
        #expect(!reloaded.recovered)
    }

    @Test("恢復掃描：進行中的 session 不視為崩潰殘留")
    func recoverySkipsActiveSessions() async throws {
        let root = try makeTempRoot()
        let active = makeSession(
            id: "2026-06-15_1000_ffff", createdAt: Date(timeIntervalSince1970: 1_781_402_400))
        _ = try await SessionStore.create(active, in: root)

        let library = SessionLibrary(rootDirectory: root)
        let recovered = try library.recoverCrashedSessions(
            activeSessionIDs: ["2026-06-15_1000_ffff"])
        #expect(recovered.isEmpty)
    }

    @Test("恢復掃描具冪等性：已標記 recovered 的不重複回報")
    func recoveryIsIdempotent() async throws {
        let root = try makeTempRoot()
        let crashed = makeSession(
            id: "2026-06-15_1000_abcd", createdAt: Date(timeIntervalSince1970: 1_781_402_400))
        _ = try await SessionStore.create(crashed, in: root)

        let library = SessionLibrary(rootDirectory: root)
        #expect(try library.recoverCrashedSessions().count == 1)
        #expect(try library.recoverCrashedSessions().isEmpty)
    }

    @Test("恢復後既有 segments 與 markers 仍可載入")
    func recoveredSessionDataRemainsLoadable() async throws {
        let root = try makeTempRoot()
        let crashed = makeSession(
            id: "2026-06-15_1000_beef", createdAt: Date(timeIntervalSince1970: 1_781_402_400))
        let store = try await SessionStore.create(crashed, in: root)
        try await store.appendSegment(
            TranscriptSegment(
                segmentID: "seg_0001", sessionID: crashed.sessionID, startSeconds: 0,
                endSeconds: 5, text: "崩潰前已定稿", isFinal: true, language: "zh-TW",
                engine: "Mock", model: "mock", createdAt: Date(timeIntervalSince1970: 0)))
        try await store.appendMarker(
            Marker(
                markerID: "m_0001", sessionID: crashed.sessionID, mediaSeconds: 3,
                type: "question", label: "問題", createdAt: Date(timeIntervalSince1970: 0)))

        let library = SessionLibrary(rootDirectory: root)
        _ = try library.recoverCrashedSessions()

        let reopened = SessionStore(directory: library.directory(for: crashed.sessionID))
        #expect(try await reopened.loadSegments().map(\.segmentID) == ["seg_0001"])
        #expect(try await reopened.loadMarkers().map(\.markerID) == ["m_0001"])
    }
}
