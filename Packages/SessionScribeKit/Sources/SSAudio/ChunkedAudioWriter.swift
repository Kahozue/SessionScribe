import AVFoundation
import SSCore

/// PCM CAF 分塊寫入器（規格書第六節、決議 2 與 10）。
///
/// - buffer 不跨檔切割：寫滿目標長度後輪替，chunk 實際長度可能略超過設定值。
/// - manifest 只記錄已完成的 chunk，每次輪替即原子落盤；
///   寫入中的 chunk 是孤兒檔，崩潰後由恢復掃描補回索引。
/// - 檔案格式 16-bit 整數 CAF，對中斷寫入容錯最佳；磁碟代價約 350MB 一小時。
public actor ChunkedAudioWriter {

    public enum WriterError: Error, Equatable {
        case formatMismatch
    }

    private let audioDirectory: URL
    private let format: AVAudioFormat
    private let chunkFrames: AVAudioFramePosition
    private let now: @Sendable () -> Date

    private var currentFile: AVAudioFile?
    private var currentChunkIndex = 0
    private var currentChunkFrames: AVAudioFramePosition = 0
    private var completedFrames: AVAudioFramePosition = 0
    private var manifest: AudioManifest

    public init(
        audioDirectory: URL,
        format: AVAudioFormat,
        chunkDuration: TimeInterval = AudioDefaults.chunkDuration,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.audioDirectory = audioDirectory
        self.format = format
        self.chunkFrames = AVAudioFramePosition(chunkDuration * format.sampleRate)
        self.now = now
        self.manifest = AudioManifest(
            sampleRate: format.sampleRate, channels: Int(format.channelCount))
    }

    /// 寫入一個 buffer。整顆進當前 chunk，寫滿即輪替。
    public func write(_ buffer: AVAudioPCMBuffer) throws {
        guard buffer.frameLength > 0 else { return }
        guard buffer.format == format else { throw WriterError.formatMismatch }
        if currentFile == nil {
            try openNextChunk()
        }
        try currentFile!.write(from: buffer)
        currentChunkFrames += AVAudioFramePosition(buffer.frameLength)
        if currentChunkFrames >= chunkFrames {
            try completeCurrentChunk()
        }
    }

    /// 寫入一顆擷取 buffer（消費者持有獨佔拷貝，可安全跨入 actor）。
    public func write(_ captured: CapturedBuffer) throws {
        try write(captured.buffer)
    }

    /// 停止錄音：收尾當前 chunk 並完成索引（不合併檔案）。
    public func finish() throws -> AudioManifest {
        if currentFile != nil {
            try completeCurrentChunk()
        } else {
            try ensureDirectory()
            try AudioManifestFile.write(manifest, to: audioDirectory)
        }
        return manifest
    }

    // MARK: - 私有

    private func openNextChunk() throws {
        try ensureDirectory()
        currentChunkIndex += 1
        let url = audioDirectory.appending(path: Self.fileName(for: currentChunkIndex))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        currentFile = try AVAudioFile(
            forWriting: url, settings: settings,
            commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    private func completeCurrentChunk() throws {
        guard currentFile != nil else { return }
        // 釋放 AVAudioFile 即關閉並寫出檔案。
        currentFile = nil
        manifest.chunks.append(
            AudioChunk(
                file: Self.fileName(for: currentChunkIndex),
                startSeconds: Double(completedFrames) / format.sampleRate,
                durationSeconds: Double(currentChunkFrames) / format.sampleRate,
                createdAt: now()))
        completedFrames += currentChunkFrames
        currentChunkFrames = 0
        try AudioManifestFile.write(manifest, to: audioDirectory)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: audioDirectory, withIntermediateDirectories: true)
    }

    static func fileName(for index: Int) -> String {
        String(format: "chunk_%04d.caf", index)
    }
}
