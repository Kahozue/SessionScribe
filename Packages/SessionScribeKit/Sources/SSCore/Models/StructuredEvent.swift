import Foundation

/// 結構化事件（aim.md 第八節、規格書 v0.2）：由 marker 加前後文 segments
/// 生成草稿，必為 `needs_review: true` 且可追溯到原始 segment 與 marker
/// （核心可靠性原則 8、9）。使用者可手動編輯後仍保留來源欄位。
public struct StructuredEvent: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var eventID: String
    public var sessionID: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var speaker: String
    public var speakerRole: String
    public var type: String
    public var topic: String
    public var content: String
    public var responseSummary: String
    public var actionItem: String
    /// high、medium、low；開放字串。
    public var priority: String
    public var confidence: String
    public var needsReview: Bool
    public var sourceSegmentIDs: [String]
    public var sourceMarkerIDs: [String]
    public var tags: [String]
    public var createdAt: Date

    public var id: String { eventID }

    public init(
        schemaVersion: Int = SchemaVersion.current,
        eventID: String,
        sessionID: String,
        startSeconds: Double,
        endSeconds: Double,
        speaker: String = "",
        speakerRole: String = "",
        type: String,
        topic: String,
        content: String,
        responseSummary: String = "",
        actionItem: String = "",
        priority: String,
        confidence: String,
        needsReview: Bool = true,
        sourceSegmentIDs: [String],
        sourceMarkerIDs: [String],
        tags: [String] = [],
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.sessionID = sessionID
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
        self.speakerRole = speakerRole
        self.type = type
        self.topic = topic
        self.content = content
        self.responseSummary = responseSummary
        self.actionItem = actionItem
        self.priority = priority
        self.confidence = confidence
        self.needsReview = needsReview
        self.sourceSegmentIDs = sourceSegmentIDs
        self.sourceMarkerIDs = sourceMarkerIDs
        self.tags = tags
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case sessionID = "session_id"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case speaker
        case speakerRole = "speaker_role"
        case type
        case topic
        case content
        case responseSummary = "response_summary"
        case actionItem = "action_item"
        case priority
        case confidence
        case needsReview = "needs_review"
        case sourceSegmentIDs = "source_segment_ids"
        case sourceMarkerIDs = "source_marker_ids"
        case tags
        case createdAt = "created_at"
    }
}

/// events.json 的文件結構。
public struct EventsDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var events: [StructuredEvent]

    public init(schemaVersion: Int = SchemaVersion.current, events: [StructuredEvent] = []) {
        self.schemaVersion = schemaVersion
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case events
    }
}

/// events.json 讀寫，寫入採原子寫（規格書第八節：暫存檔加原子改名）。
public enum EventsFile {
    public static let fileName = "events.json"

    public static func url(in sessionDirectory: URL) -> URL {
        sessionDirectory.appending(path: fileName)
    }

    public static func write(_ document: EventsDocument, to sessionDirectory: URL) throws {
        let data = try SSJSON.fileEncoder.encode(document)
        try data.write(to: url(in: sessionDirectory), options: .atomic)
    }

    public static func readIfPresent(from sessionDirectory: URL) throws -> EventsDocument? {
        let url = url(in: sessionDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try SSJSON.decoder.decode(EventsDocument.self, from: Data(contentsOf: url))
    }
}
