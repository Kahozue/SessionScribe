import Foundation

/// 播放頁波形的離線抽樣結果（衍生資料，地位比照 transcript_summary.json：
/// 不覆蓋 canonical 音訊，損毀或缺檔即重新生成）。
public struct Waveform: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var durationSeconds: Double
    /// 每 bin 的 RMS（0...1）。
    public var rms: [Float]
    /// 每 bin 的絕對值峰值（0...1）。
    public var peak: [Float]

    public init(
        schemaVersion: Int = SchemaVersion.current,
        durationSeconds: Double,
        rms: [Float],
        peak: [Float]
    ) {
        self.schemaVersion = schemaVersion
        self.durationSeconds = durationSeconds
        self.rms = rms
        self.peak = peak
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case durationSeconds = "duration_seconds"
        case rms
        case peak
    }

    /// bin 數規則（spec 第四節）：每秒 10 bins，上限 2000，至少 1。
    public static func binCount(forDuration seconds: Double) -> Int {
        min(2000, max(1, Int((seconds * 10).rounded(.up))))
    }
}

public enum WaveformFile {
    public static let filename = "waveform.json"

    public static func url(in sessionDirectory: URL) -> URL {
        sessionDirectory.appending(path: filename)
    }

    public static func write(_ waveform: Waveform, to sessionDirectory: URL) throws {
        let data = try SSJSON.fileEncoder.encode(waveform)
        try data.write(to: url(in: sessionDirectory), options: .atomic)
    }

    public static func readIfPresent(from sessionDirectory: URL) throws -> Waveform? {
        let fileURL = url(in: sessionDirectory)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try SSJSON.decoder.decode(Waveform.self, from: Data(contentsOf: fileURL))
    }
}
