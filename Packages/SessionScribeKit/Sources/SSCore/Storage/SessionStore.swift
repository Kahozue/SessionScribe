import Foundation

/// 單一 session 資料夾的儲存服務：建立資料夾結構、metadata 原子寫入、
/// segment 與 marker 的落盤。actor 隔離保證寫入順序。
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

    /// 清空逐字稿檔，用於重新轉錄前丟棄舊段落。關閉 append handle，
    /// 後續 appendSegment 會重新開啟目前檔案，避免寫到已被替換的舊 inode。
    public func resetSegments() throws {
        try segmentWriter?.close()
        segmentWriter = nil
        let url = directory.appending(path: SessionFiles.liveSegments)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url, options: .atomic)
    }

    /// 原子替換整份逐字稿。用於重新轉錄成功後一次換檔，避免轉錄失敗時先刪掉舊稿。
    public func replaceSegments(_ segments: [TranscriptSegment]) throws {
        try segmentWriter?.close()
        segmentWriter = nil

        let url = directory.appending(path: SessionFiles.liveSegments)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for segment in segments {
            var line = try SSJSON.lineEncoder.encode(segment)
            line.append(UInt8(ascii: "\n"))
            data.append(line)
        }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Markers

    public func appendMarker(_ marker: Marker) throws {
        if markerWriter == nil {
            markerWriter = try JSONLWriter(
                url: directory.appending(path: SessionFiles.manualMarkers))
        }
        try markerWriter!.append(marker)
    }

    /// 重寫 marker 檔案，用於使用者取消既有標記。重寫前關閉 append handle，
    /// 後續 append 會重新開啟目前檔案，避免寫到已被原子替換的舊 inode。
    public func saveMarkers(_ markers: [Marker]) throws {
        try markerWriter?.close()
        markerWriter = nil

        let url = directory.appending(path: SessionFiles.manualMarkers)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for marker in markers {
            var line = try SSJSON.lineEncoder.encode(marker)
            line.append(UInt8(ascii: "\n"))
            data.append(line)
        }
        try data.write(to: url, options: .atomic)
    }

    public func loadMarkers() throws -> [Marker] {
        try JSONLReader.read(
            Marker.self, from: directory.appending(path: SessionFiles.manualMarkers))
    }
}
