import Foundation

/// 可匯出的格式。匯出選項視窗依此列出勾選項。
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case csv
    case json
    case structuredNotes
    case events
    case eventsCSV
    case rawJSONL
    case audio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .markdown: "逐字稿（Markdown）"
        case .csv: "標記（CSV）"
        case .json: "完整資料（JSON）"
        case .structuredNotes: "結構化筆記（Markdown）"
        case .events: "結構化事件（JSON）"
        case .eventsCSV: "結構化事件（CSV）"
        case .rawJSONL: "原始紀錄（JSONL）"
        case .audio: "錄音音檔"
        }
    }
}

/// 整批匯出：依選擇的格式寫出 transcript.md、markers.csv、session.json、
/// jsonl 原檔副本與錄音音檔。
public enum ExportService {

    public static func export(
        store: SessionStore,
        session: Session,
        to destination: URL,
        formats: Set<ExportFormat> = Set(ExportFormat.allCases)
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let segments = try await store.loadSegments()
        let markers = try await store.loadMarkers()

        // 結構化事件來源：有 events.json 取既有，否則由 markers 即時生成草稿。
        let needsEvents =
            formats.contains(.structuredNotes) || formats.contains(.events)
            || formats.contains(.eventsCSV)
        let events: [StructuredEvent]
        if needsEvents {
            if let document = try EventsFile.readIfPresent(from: store.directory) {
                events = document.events
            } else {
                events = EventDraftBuilder.drafts(
                    markers: markers, segments: segments, sessionID: session.sessionID)
            }
        } else {
            events = []
        }

        if formats.contains(.markdown) {
            let markdown = MarkdownExporter.transcript(
                session: session, segments: segments, markers: markers)
            try Data(markdown.utf8).write(
                to: destination.appending(path: "transcript.md"), options: .atomic)
        }

        if formats.contains(.csv) {
            let csv = CSVExporter.markersCSV(markers: markers, segments: segments)
            try Data(csv.utf8).write(
                to: destination.appending(path: "markers.csv"), options: .atomic)
        }

        if formats.contains(.json) {
            let bundle = try JSONExporter.sessionBundle(
                session: session, segments: segments, markers: markers)
            try bundle.write(to: destination.appending(path: "session.json"), options: .atomic)
        }

        if formats.contains(.structuredNotes) {
            let markdown = MarkdownExporter.structuredNotes(session: session, events: events)
            try Data(markdown.utf8).write(
                to: destination.appending(path: "structured_notes.md"), options: .atomic)
        }

        if formats.contains(.events) {
            try EventsFile.write(EventsDocument(events: events), to: destination)
        }

        if formats.contains(.eventsCSV) {
            let csv = CSVExporter.eventsCSV(events: events)
            try Data(csv.utf8).write(
                to: destination.appending(path: "events.csv"), options: .atomic)
        }

        if formats.contains(.rawJSONL) {
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

        if formats.contains(.audio) {
            let source = store.directory.appending(path: SessionFiles.audioDirectory)
            if fileManager.fileExists(atPath: source.path) {
                let target = destination.appending(path: SessionFiles.audioDirectory)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: source, to: target)
            }
        }
    }
}
