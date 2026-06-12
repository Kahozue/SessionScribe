import Foundation

/// 整批匯出：寫出 transcript.md、markers.csv、session.json，
/// 並複製 live_segments.jsonl 與 manual_markers.jsonl 原檔。
public enum ExportService {

    public static func export(
        store: SessionStore,
        session: Session,
        to destination: URL
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let segments = try await store.loadSegments()
        let markers = try await store.loadMarkers()

        let markdown = MarkdownExporter.transcript(
            session: session, segments: segments, markers: markers)
        try Data(markdown.utf8).write(
            to: destination.appending(path: "transcript.md"), options: .atomic)

        let csv = CSVExporter.markersCSV(markers: markers, segments: segments)
        try Data(csv.utf8).write(
            to: destination.appending(path: "markers.csv"), options: .atomic)

        let bundle = try JSONExporter.sessionBundle(
            session: session, segments: segments, markers: markers)
        try bundle.write(to: destination.appending(path: "session.json"), options: .atomic)

        for name in [SessionFiles.liveSegments, SessionFiles.manualMarkers] {
            let source = store.directory.appending(path: name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let target = destination.appending(path: name)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: source, to: target)
        }
    }
}
