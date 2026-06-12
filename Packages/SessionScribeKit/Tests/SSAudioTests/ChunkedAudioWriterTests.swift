import AVFoundation
import Testing
@testable import SSAudio
import SSCore

private let testFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
private let fixedNow = Date(timeIntervalSince1970: 1_781_402_772)

private func makeAudioDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SSAudioTests-\(UUID().uuidString)")
        .appending(path: "audio")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 產生指定 frame 數的固定值 buffer。
private func makeBuffer(frames: Int, value: Float = 0.25) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: testFormat, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let channel = buffer.floatChannelData![0]
    for index in 0..<frames {
        channel[index] = value
    }
    return buffer
}

/// 建立 chunkDuration 0.5 秒（24000 frames）的 writer。
private func makeWriter(at directory: URL) -> ChunkedAudioWriter {
    ChunkedAudioWriter(
        audioDirectory: directory, format: testFormat, chunkDuration: 0.5, now: { fixedNow })
}

@Suite("ChunkedAudioWriter")
struct ChunkedAudioWriterTests {

    @Test("單一 buffer 加 finish：一個 chunk 檔與一筆 manifest 索引")
    func singleChunk() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        try await writer.write(makeBuffer(frames: 12000))
        let manifest = try await writer.finish()

        #expect(manifest.sampleRate == 48000)
        #expect(manifest.channels == 1)
        #expect(manifest.chunks.count == 1)
        #expect(manifest.chunks[0].file == "chunk_0001.caf")
        #expect(manifest.chunks[0].startSeconds == 0)
        #expect(manifest.chunks[0].durationSeconds == 0.25)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "chunk_0001.caf").path))
    }

    @Test("寫滿即輪替：連續寫入產生多個 chunk，媒體時間起點連續")
    func rotationProducesSequentialChunks() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        // 6 個 12000 frames buffer = 72000 frames = 1.5 秒 = 3 個 0.5 秒 chunk。
        for _ in 0..<6 {
            try await writer.write(makeBuffer(frames: 12000))
        }
        let manifest = try await writer.finish()

        #expect(manifest.chunks.map(\.file) == ["chunk_0001.caf", "chunk_0002.caf", "chunk_0003.caf"])
        #expect(manifest.chunks.map(\.startSeconds) == [0, 0.5, 1.0])
        #expect(manifest.chunks.map(\.durationSeconds) == [0.5, 0.5, 0.5])
    }

    @Test("buffer 不跨檔切割：超過目標長度的 chunk 略長，下一塊起點順移")
    func bufferIsNeverSplit() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        // 30000 frames 超過 24000 的目標，整顆寫入 chunk_0001。
        try await writer.write(makeBuffer(frames: 30000))
        try await writer.write(makeBuffer(frames: 12000))
        let manifest = try await writer.finish()

        #expect(manifest.chunks.map(\.file) == ["chunk_0001.caf", "chunk_0002.caf"])
        #expect(manifest.chunks.map(\.durationSeconds) == [0.625, 0.25])
        #expect(manifest.chunks.map(\.startSeconds) == [0, 0.625])
    }

    @Test("輪替當下即原子落盤 manifest，不等 finish（崩潰容錯）")
    func manifestPersistedOnRotation() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        // 1.5 個 chunk 的量：第一塊完成輪替，第二塊還在寫。
        try await writer.write(makeBuffer(frames: 24000))
        try await writer.write(makeBuffer(frames: 12000))

        // 模擬崩潰：不呼叫 finish，直接讀磁碟上的 manifest。
        let onDisk = try #require(try AudioManifestFile.readIfPresent(from: directory))
        #expect(onDisk.chunks.map(\.file) == ["chunk_0001.caf"])
        // 寫入中的 chunk_0002 是孤兒檔，留給恢復掃描補回。
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "chunk_0002.caf").path))
    }

    @Test("chunk 檔可用 AVAudioFile 讀回且 frame 數正確")
    func chunkFileIsReadable() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        try await writer.write(makeBuffer(frames: 12000))
        _ = try await writer.finish()

        let file = try AVAudioFile(forReading: directory.appending(path: "chunk_0001.caf"))
        #expect(file.length == 12000)
        #expect(file.fileFormat.sampleRate == 48000)
        #expect(file.fileFormat.channelCount == 1)
    }

    @Test("樣本值在 16-bit 量化誤差內保留")
    func samplesSurviveRoundTrip() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        try await writer.write(makeBuffer(frames: 480, value: 0.25))
        _ = try await writer.finish()

        let file = try AVAudioFile(forReading: directory.appending(path: "chunk_0001.caf"))
        let readBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: readBuffer)
        let samples = UnsafeBufferPointer(
            start: readBuffer.floatChannelData![0], count: Int(readBuffer.frameLength))
        // 16-bit 量化誤差上限 1/32768。
        #expect(samples.allSatisfy { abs($0 - 0.25) < 1.0 / 32768.0 })
    }

    @Test("未寫入任何 buffer 時 finish 產生空索引，無 chunk 檔")
    func finishWithoutWrites() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        let manifest = try await writer.finish()

        #expect(manifest.chunks.isEmpty)
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!entries.contains { $0.hasSuffix(".caf") })
    }

    @Test("空 buffer 忽略不計")
    func emptyBufferIsIgnored() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        try await writer.write(makeBuffer(frames: 0))
        let manifest = try await writer.finish()
        #expect(manifest.chunks.isEmpty)
    }

    @Test("格式不符的 buffer 拋錯，不寫入")
    func mismatchedFormatThrows() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        await #expect(throws: (any Error).self) {
            let otherFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: otherFormat, frameCapacity: 480)!
            buffer.frameLength = 480
            try await writer.write(buffer)
        }
    }

    @Test("finish 後的 manifest 與磁碟上的一致")
    func finishedManifestMatchesDisk() async throws {
        let directory = try makeAudioDirectory()
        let writer = makeWriter(at: directory)
        try await writer.write(makeBuffer(frames: 30000))
        let returned = try await writer.finish()
        let onDisk = try AudioManifestFile.read(from: directory)
        #expect(returned == onDisk)
    }
}
