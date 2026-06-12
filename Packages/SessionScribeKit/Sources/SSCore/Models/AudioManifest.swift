import Foundation

/// 音訊 chunk 索引，對應 `audio/manifest.json`（規格書第二節決議 2）。
/// 只記錄已完成的 chunk；寫入中的 chunk 是孤兒，由恢復掃描重建補回。
/// 停止錄音時只完成索引，不做破壞性合併。
public struct AudioManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sampleRate: Double
    public var channels: Int
    public var chunks: [AudioChunk]

    public init(
        schemaVersion: Int = SchemaVersion.current,
        sampleRate: Double,
        channels: Int,
        chunks: [AudioChunk] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sampleRate = sampleRate
        self.channels = channels
        self.chunks = chunks
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sampleRate = "sample_rate"
        case channels
        case chunks
    }
}

extension AudioManifest {

    public struct ChunkLocation: Equatable, Sendable {
        public let chunkIndex: Int
        public let offsetSeconds: Double
    }

    public var totalDurationSeconds: Double {
        guard let last = chunks.last else { return 0 }
        return last.startSeconds + last.durationSeconds
    }

    /// 媒體時間定位到 chunk 與塊內偏移（播放跳轉用）。
    /// 邊界時間歸屬後一塊；超出總長回傳 nil。
    public func locate(seconds: Double) -> ChunkLocation? {
        for (index, chunk) in chunks.enumerated() {
            if seconds >= chunk.startSeconds,
                seconds < chunk.startSeconds + chunk.durationSeconds
            {
                return ChunkLocation(
                    chunkIndex: index, offsetSeconds: seconds - chunk.startSeconds)
            }
        }
        return nil
    }
}

/// manifest 內一個 chunk 的索引項。時間為媒體時間秒數，與 MediaClock 同軸。
public struct AudioChunk: Codable, Equatable, Sendable {
    public var file: String
    public var startSeconds: Double
    public var durationSeconds: Double
    public var createdAt: Date

    public init(file: String, startSeconds: Double, durationSeconds: Double, createdAt: Date) {
        self.file = file
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case file
        case startSeconds = "start_seconds"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
    }
}

/// audio/manifest.json 的讀寫，寫入採原子寫；ChunkedAudioWriter 與恢復掃描共用。
public enum AudioManifestFile {
    public static let fileName = "manifest.json"

    public static func url(in audioDirectory: URL) -> URL {
        audioDirectory.appending(path: fileName)
    }

    public static func write(_ manifest: AudioManifest, to audioDirectory: URL) throws {
        let data = try SSJSON.fileEncoder.encode(manifest)
        try data.write(to: url(in: audioDirectory), options: .atomic)
    }

    public static func read(from audioDirectory: URL) throws -> AudioManifest {
        let data = try Data(contentsOf: url(in: audioDirectory))
        return try SSJSON.decoder.decode(AudioManifest.self, from: data)
    }

    /// manifest 不存在（崩潰時尚未完成首次輪替）回傳 nil；存在但損毀則拋錯。
    public static func readIfPresent(from audioDirectory: URL) throws -> AudioManifest? {
        guard FileManager.default.fileExists(atPath: url(in: audioDirectory).path) else {
            return nil
        }
        return try read(from: audioDirectory)
    }
}
