import Foundation

/// 一場錄音轉寫 session 的 metadata，對應 `metadata.json`。
/// `endedAt == nil` 且非進行中即視為崩潰殘留，啟動時由 SessionLibrary 進入恢復流程。
public struct Session: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var sessionID: String
    public var title: String
    public var templateID: String
    public var createdAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var locale: String
    public var asrEngine: String
    public var privacyMode: PrivacyMode
    public var audioInput: String
    public var recovered: Bool
    public var notes: String
    public var appVersion: String

    public var id: String { sessionID }

    public init(
        schemaVersion: Int = SchemaVersion.current,
        sessionID: String,
        title: String,
        templateID: String,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        locale: String,
        asrEngine: String = "",
        privacyMode: PrivacyMode = .localOnly,
        audioInput: String = "",
        recovered: Bool = false,
        notes: String = "",
        appVersion: String
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.title = title
        self.templateID = templateID
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.locale = locale
        self.asrEngine = asrEngine
        self.privacyMode = privacyMode
        self.audioInput = audioInput
        self.recovered = recovered
        self.notes = notes
        self.appVersion = appVersion
    }

    /// 產生 `YYYY-MM-DD_HHmm_xxxx` 格式的 session id。
    /// 短亂數後綴避免同分鐘碰撞，前綴保留時間排序性。
    public static func makeID(
        date: Date = Date(),
        timeZone: TimeZone = .current,
        suffix: String? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let randomSuffix = suffix ?? String((0..<4).map { _ in "0123456789abcdef".randomElement()! })
        return "\(formatter.string(from: date))_\(randomSuffix)"
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case title
        case templateID = "template_id"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case locale
        case asrEngine = "asr_engine"
        case privacyMode = "privacy_mode"
        case audioInput = "audio_input"
        case recovered
        case notes
        case appVersion = "app_version"
    }

    // optional 欄位輸出明確 null（規格書第八節範例格式），故不用合成的 encodeIfPresent。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(title, forKey: .title)
        try container.encode(templateID, forKey: .templateID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(locale, forKey: .locale)
        try container.encode(asrEngine, forKey: .asrEngine)
        try container.encode(privacyMode, forKey: .privacyMode)
        try container.encode(audioInput, forKey: .audioInput)
        try container.encode(recovered, forKey: .recovered)
        try container.encode(notes, forKey: .notes)
        try container.encode(appVersion, forKey: .appVersion)
    }
}

/// 隱私模式。v0.1 只有 local_only；其餘兩種在 v0.3 提供 UI，資料模型自始預留。
public enum PrivacyMode: String, Codable, Equatable, Sendable {
    case localOnly = "local_only"
    case textCloudAssist = "text_cloud_assist"
    case audioCloudASR = "audio_cloud_asr"
}
