import AVFoundation
import Testing
@testable import SSAudio
import SSCore

private let testFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

private func makeAudioDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SSAudioTests-\(UUID().uuidString)")
        .appending(path: "audio")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeBuffer(frames: Int) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: testFormat, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    return buffer
}

private func makeWriter(at directory: URL) -> ChunkedAudioWriter {
    ChunkedAudioWriter(audioDirectory: directory, format: testFormat, chunkDuration: 0.5)
}

@Suite("AudioManifestRecovery")
struct AudioManifestRecoveryTests {

    @Test("manifest 遺失時依 chunk 檔重建，索引內容一致")
    func rebuildsDeletedManifest() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        for _ in 0..<4 {
            try await writer.write(makeBuffer(frames: 12000))
        }
        let original = try await writer.finish()
        try FileManager.default.removeItem(at: AudioManifestFile.url(in: directory))

        let rebuilt = try AudioManifestRecovery.rebuild(audioDirectory: directory)
        #expect(rebuilt.sampleRate == 48000)
        #expect(rebuilt.channels == 1)
        #expect(rebuilt.chunks.map(\.file) == original.chunks.map(\.file))
        #expect(rebuilt.chunks.map(\.startSeconds) == original.chunks.map(\.startSeconds))
        #expect(rebuilt.chunks.map(\.durationSeconds) == original.chunks.map(\.durationSeconds))
        // 重建結果已原子落盤。
        let onDisk = try AudioManifestFile.read(from: directory)
        #expect(onDisk == rebuilt)
    }

    @Test("孤兒 chunk 補回索引（崩潰時寫入中、未進 manifest 的那塊）")
    func indexesOrphanChunk() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        // 一塊完成輪替（24000 frames），一塊寫到一半（12000 frames）即「崩潰」。
        try await writer.write(makeBuffer(frames: 24000))
        try await writer.write(makeBuffer(frames: 12000))
        // 不呼叫 finish；磁碟上 manifest 只有 chunk_0001。

        let rebuilt = try AudioManifestRecovery.rebuild(audioDirectory: directory)
        #expect(rebuilt.chunks.map(\.file) == ["chunk_0001.caf", "chunk_0002.caf"])
        #expect(rebuilt.chunks.map(\.startSeconds) == [0, 0.5])
        #expect(rebuilt.chunks.map(\.durationSeconds) == [0.5, 0.25])
    }

    @Test("空目錄重建出空索引")
    func emptyDirectoryYieldsEmptyManifest() throws {
        let directory = try makeAudioDirectory()
        let rebuilt = try AudioManifestRecovery.rebuild(audioDirectory: directory)
        #expect(rebuilt.chunks.isEmpty)
    }

    @Test("非 chunk 檔案不計入索引")
    func ignoresNonChunkFiles() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        try await writer.write(makeBuffer(frames: 12000))
        _ = try await writer.finish()
        try Data("雜物".utf8).write(to: directory.appending(path: "notes.txt"))

        let rebuilt = try AudioManifestRecovery.rebuild(audioDirectory: directory)
        #expect(rebuilt.chunks.map(\.file) == ["chunk_0001.caf"])
    }

    @Test("無法讀取的損毀 chunk 跳過，其餘照常索引")
    func skipsUnreadableChunk() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        try await writer.write(makeBuffer(frames: 12000))
        _ = try await writer.finish()
        // 偽造一個完全損毀的 chunk 檔。
        try Data("這不是CAF".utf8).write(to: directory.appending(path: "chunk_0002.caf"))

        let rebuilt = try AudioManifestRecovery.rebuild(audioDirectory: directory)
        #expect(rebuilt.chunks.map(\.file) == ["chunk_0001.caf"])
    }
}
