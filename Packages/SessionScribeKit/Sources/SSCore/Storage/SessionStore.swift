import Foundation

/// 單一 session 資料夾的儲存服務：建立資料夾結構、metadata 原子寫入、
/// segment 與 marker 的 append-only 落盤。actor 隔離保證寫入順序。
public actor SessionStore {
    public nonisolated let directory: URL
    private var segmentWriter: JSONLWriter?
    private var markerWriter: JSONLWriter?

    /// 開啟既有 session 目錄。
    public init(directory: URL) {
        self.directory = directory
    }

    /// 建立新 session：資料夾結構（audio/、exports/）加 metadata 原子寫入。
    /// 同名目錄已存在視為錯誤（session id 的亂數後綴已避免正常碰撞）。
    public static func create(_ session: Session, in root: URL) async throws -> SessionStore {
        let directory = root.appending(path: session.sessionID)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        try fileManager.createDirectory(
            at: directory.appending(path: SessionFiles.audioDirectory),
            withIntermediateDirectories: false)
        try fileManager.createDirectory(
            at: directory.appending(path: SessionFiles.exportsDirectory),
            withIntermediateDirectories: false)
        let store = SessionStore(directory: directory)
        try await store.saveMetadata(session)
        return store
    }

    // MARK: - Metadata

    public func saveMetadata(_ session: Session) throws {
        try SessionMetadataFile.write(session, to: directory)
    }

    public func loadMetadata() throws -> Session {
        try SessionMetadataFile.read(from: directory)
    }

    // MARK: - Segments

    public func appendSegment(_ segment: TranscriptSegment) throws {
        if segmentWriter == nil {
            segmentWriter = try JSONLWriter(
                url: directory.appending(path: SessionFiles.liveSegments))
        }
        try segmentWriter!.append(segment)
    }

    public func loadSegments() throws -> [TranscriptSegment] {
        try JSONLReader.read(
            TranscriptSegment.self, from: directory.appending(path: SessionFiles.liveSegments))
    }

    // MARK: - Markers

    public func appendMarker(_ marker: Marker) throws {
        if markerWriter == nil {
            markerWriter = try JSONLWriter(
                url: directory.appending(path: SessionFiles.manualMarkers))
        }
        try markerWriter!.append(marker)
    }

    public func loadMarkers() throws -> [Marker] {
        try JSONLReader.read(
            Marker.self, from: directory.appending(path: SessionFiles.manualMarkers))
    }
}
