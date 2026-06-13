import AVFoundation
import Foundation
import Testing

@testable import SSCore

@Suite("AudioExporter m4a 匯出（v0.2）")
struct AudioExporterTests {

    private func writeSilentCAF(to url: URL, seconds: Double, sampleRate: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    @Test("依 manifest 順序串接 chunks 輸出單一 m4a，長度約為總和")
    func exportsConcatenatedM4A() async throws {
        let audioDir = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let sampleRate = 48000.0
        try writeSilentCAF(
            to: audioDir.appending(path: "chunk_0001.caf"), seconds: 0.5, sampleRate: sampleRate)
        try writeSilentCAF(
            to: audioDir.appending(path: "chunk_0002.caf"), seconds: 0.5, sampleRate: sampleRate)
        let manifest = AudioManifest(
            sampleRate: sampleRate, channels: 1,
            chunks: [
                AudioChunk(
                    file: "chunk_0001.caf", startSeconds: 0, durationSeconds: 0.5,
                    createdAt: Date(timeIntervalSince1970: 0)),
                AudioChunk(
                    file: "chunk_0002.caf", startSeconds: 0.5, durationSeconds: 0.5,
                    createdAt: Date(timeIntervalSince1970: 0)),
            ])
        try AudioManifestFile.write(manifest, to: audioDir)

        let output = audioDir.appending(path: "out.m4a")
        try await AudioExporter.exportM4A(audioDirectory: audioDir, to: output)

        #expect(FileManager.default.fileExists(atPath: output.path))
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(duration > 0.8 && duration < 1.2, "長度約 1 秒，實際 \(duration)")
    }

    @Test("沒有 manifest 時拋出 missingManifest")
    func throwsWhenNoManifest() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await #expect(throws: AudioExporter.ExportError.self) {
            try await AudioExporter.exportM4A(
                audioDirectory: dir, to: dir.appending(path: "x.m4a"))
        }
    }
}
