import AVFoundation
import SSCore

/// 崩潰恢復的 audio 部分（架構文件第三節）：掃描 audio 目錄的 chunk 檔，
/// 依檔名順序重建 manifest 並原子落盤。寫入中未進索引的孤兒 chunk 由此補回。
public enum AudioManifestRecovery {

    /// 重建並落盤 manifest。完全無法讀取的損毀 chunk 跳過，不阻斷恢復。
    @discardableResult
    public static func rebuild(audioDirectory: URL) throws -> AudioManifest {
        let fileManager = FileManager.default
        let chunkNames = try fileManager.contentsOfDirectory(atPath: audioDirectory.path)
            .filter { $0.hasPrefix("chunk_") && $0.hasSuffix(".caf") }
            .sorted()

        var sampleRate: Double?
        var channels: Int?
        var chunks: [AudioChunk] = []
        var cumulativeSeconds = 0.0
        for name in chunkNames {
            let url = audioDirectory.appending(path: name)
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let duration = Double(file.length) / file.fileFormat.sampleRate
            let creationDate =
                (try? fileManager.attributesOfItem(atPath: url.path)[.creationDate] as? Date)
                .flatMap { $0 } ?? Date()
            // 取整秒：ISO-8601 為秒級精度，使回傳值與落盤值相等。
            let createdAt = Date(
                timeIntervalSince1970: creationDate.timeIntervalSince1970.rounded(.down))
            chunks.append(
                AudioChunk(
                    file: name, startSeconds: cumulativeSeconds,
                    durationSeconds: duration, createdAt: createdAt))
            cumulativeSeconds += duration
            if sampleRate == nil {
                sampleRate = file.fileFormat.sampleRate
                channels = Int(file.fileFormat.channelCount)
            }
        }

        // 無可讀 chunk 時保留既有 manifest 的格式參數，再不行用預設值。
        let existing = try? AudioManifestFile.readIfPresent(from: audioDirectory)
        let manifest = AudioManifest(
            sampleRate: sampleRate ?? existing?.sampleRate ?? 48000,
            channels: channels ?? existing?.channels ?? 1,
            chunks: chunks)
        try AudioManifestFile.write(manifest, to: audioDirectory)
        return manifest
    }
}
