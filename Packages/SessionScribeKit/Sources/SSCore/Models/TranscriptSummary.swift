import Foundation

/// 整份逐字稿摘要（v0.3）：由本機 AI 依 finalized segments 產生，
/// 不覆蓋原始逐字稿，並保留來源 segment ids 供追溯。
public struct TranscriptSummary: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var summaryID: String
    public var sessionID: String
    public var content: String
    public var keyPoints: [String]
    public var actionItems: [String]
    public var needsReview: Bool
    public var sourceSegmentIDs: [String]
    public var createdAt: Date

    public var id: String { summaryID }

    public init(
        schemaVersion: Int = SchemaVersion.current,
        summaryID: String,
        sessionID: String,
        content: String,
        keyPoints: [String] = [],
        actionItems: [String] = [],
        needsReview: Bool = true,
        sourceSegmentIDs: [String],
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.summaryID = summaryID
        self.sessionID = sessionID
        self.content = content
        self.keyPoints = keyPoints
        self.actionItems = actionItems
        self.needsReview = needsReview
        self.sourceSegmentIDs = sourceSegmentIDs
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case summaryID = "summary_id"
        case sessionID = "session_id"
        case content
        case keyPoints = "key_points"
        case actionItems = "action_items"
        case needsReview = "needs_review"
        case sourceSegmentIDs = "source_segment_ids"
        case createdAt = "created_at"
    }
}

/// transcript_summary.json 的文件結構。
public struct TranscriptSummaryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var summary: TranscriptSummary

    public init(
        schemaVersion: Int = SchemaVersion.current,
        summary: TranscriptSummary
    ) {
        self.schemaVersion = schemaVersion
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case summary
    }
}

/// transcript_summary.json 讀寫，寫入採原子寫。
public enum TranscriptSummaryFile {
    public static let fileName = "transcript_summary.json"

    public static func url(in sessionDirectory: URL) -> URL {
        sessionDirectory.appending(path: fileName)
    }

    public static func write(_ document: TranscriptSummaryDocument, to sessionDirectory: URL) throws {
        let data = try SSJSON.fileEncoder.encode(document)
        try data.write(to: url(in: sessionDirectory), options: .atomic)
    }

    public static func readIfPresent(from sessionDirectory: URL) throws -> TranscriptSummaryDocument? {
        let url = url(in: sessionDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try SSJSON.decoder.decode(TranscriptSummaryDocument.self, from: Data(contentsOf: url))
    }
}
