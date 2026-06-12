import Foundation

/// 一筆手動事件標記，對應 `manual_markers.jsonl` 的一行。
/// 與 segment 的關聯以 `mediaSeconds` 為唯一真相；`nearestSegmentIDs` 只是寫入當下的快照，
/// 讀取與匯出時一律由時間戳動態重算。
public struct Marker: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var markerID: String
    public var sessionID: String
    public var mediaSeconds: Double
    /// 開放字串而非封閉 enum：自定義 marker type 自始即受資料模型支援（v0.2 提供 UI）。
    public var type: String
    public var label: String
    public var note: String
    public var nearestSegmentIDs: [String]
    public var createdAt: Date

    public var id: String { markerID }

    public init(
        schemaVersion: Int = SchemaVersion.current,
        markerID: String,
        sessionID: String,
        mediaSeconds: Double,
        type: String,
        label: String,
        note: String = "",
        nearestSegmentIDs: [String] = [],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.markerID = markerID
        self.sessionID = sessionID
        self.mediaSeconds = mediaSeconds
        self.type = type
        self.label = label
        self.note = note
        self.nearestSegmentIDs = nearestSegmentIDs
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case markerID = "marker_id"
        case sessionID = "session_id"
        case mediaSeconds = "media_seconds"
        case type
        case label
        case note
        case nearestSegmentIDs = "nearest_segment_ids"
        case createdAt = "created_at"
    }
}

/// 預設 marker type 與顯示標籤。Marker.type 本身是開放字串，這裡只提供內建四種。
public struct MarkerType: Equatable, Hashable, Sendable {
    public let rawValue: String
    public let label: String

    public init(rawValue: String, label: String) {
        self.rawValue = rawValue
        self.label = label
    }

    public static let question = MarkerType(rawValue: "question", label: "問題")
    public static let requiredRevision = MarkerType(rawValue: "required_revision", label: "必改")
    public static let suggestion = MarkerType(rawValue: "suggestion", label: "建議")
    public static let importantAnswer = MarkerType(rawValue: "important_answer", label: "重要回答")

    /// 依 UI 按鈕順序排列：Q 問題、R 必改、S 建議、A 重要回答。
    public static let defaults: [MarkerType] = [
        .question, .requiredRevision, .suggestion, .importantAnswer,
    ]
}
