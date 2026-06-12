import Foundation

/// Session 資料夾內的檔案與子目錄名稱（規格書第八節）。
public enum SessionFiles {
    public static let metadata = "metadata.json"
    public static let liveSegments = "live_segments.jsonl"
    public static let manualMarkers = "manual_markers.jsonl"
    public static let audioDirectory = "audio"
    public static let exportsDirectory = "exports"
}

/// metadata.json 的讀寫。寫入使用原子寫（暫存檔加改名），
/// 崩潰瞬間不會留下半截 metadata；SessionStore 與 SessionLibrary 共用。
enum SessionMetadataFile {

    static func url(in directory: URL) -> URL {
        directory.appending(path: SessionFiles.metadata)
    }

    static func write(_ session: Session, to directory: URL) throws {
        let data = try SSJSON.fileEncoder.encode(session)
        try data.write(to: url(in: directory), options: .atomic)
    }

    static func read(from directory: URL) throws -> Session {
        let data = try Data(contentsOf: url(in: directory))
        return try SSJSON.decoder.decode(Session.self, from: data)
    }
}
