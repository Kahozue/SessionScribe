import Foundation

/// 一筆 finalized 轉寫結果，對應 `live_segments.jsonl` 的一行。
/// 時間戳為媒體時間秒數（從錄音起點累計，不含暫停），與音訊時間軸共用 MediaClock。
public struct TranscriptSegment: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var segmentID: String
    public var sessionID: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var isFinal: Bool
    public var language: String
    public var engine: String
    public var model: String
    public var confidence: Double?
    public var createdAt: Date

    public var id: String { segmentID }

    public init(
        schemaVersion: Int = SchemaVersion.current,
        segmentID: String,
        sessionID: String,
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        isFinal: Bool,
        language: String,
        engine: String,
        model: String,
        confidence: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.segmentID = segmentID
        self.sessionID = sessionID
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.isFinal = isFinal
        self.language = language
        self.engine = engine
        self.model = model
        self.confidence = confidence
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case segmentID = "segment_id"
        case sessionID = "session_id"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case text
        case isFinal = "is_final"
        case language
        case engine
        case model
        case confidence
        case createdAt = "created_at"
    }

    // confidence 輸出明確 null（規格書第八節範例格式）。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(segmentID, forKey: .segmentID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(startSeconds, forKey: .startSeconds)
        try container.encode(endSeconds, forKey: .endSeconds)
        try container.encode(text, forKey: .text)
        try container.encode(isFinal, forKey: .isFinal)
        try container.encode(language, forKey: .language)
        try container.encode(engine, forKey: .engine)
        try container.encode(model, forKey: .model)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
