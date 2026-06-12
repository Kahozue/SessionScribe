import AVFoundation
import Foundation
import Testing
@testable import SSTranscription
import SSAudio
import SSCore

@Suite("OfflineTranscriber")
struct OfflineTranscriberTests {

    @Test("依 manifest 順序餵入引擎，segments 落盤且媒體時間跨 chunk 連續")
    func transcribesImportedChunks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSTranscriptionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // 準備一個有兩塊 chunk（各 0.5 秒）的 session。
        var session = Session(
            sessionID: "2026-06-15_1000_imp1", title: "匯入測試",
            templateID: "imported", createdAt: Date(timeIntervalSince1970: 0),
            locale: "zh-TW", appVersion: "0.1.0", source: .imported)
        session.endedAt = Date(timeIntervalSince1970: 10)
        let store = try await SessionStore.create(session, in: root)
        let audioDirectory = store.directory.appending(path: SessionFiles.audioDirectory)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let writer = ChunkedAudioWriter(
            audioDirectory: audioDirectory, format: format, chunkDuration: 0.5)
        for _ in 0..<2 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000)!
            buffer.frameLength = 24000
            try await writer.write(buffer)
        }
        _ = try await writer.finish()

        // mock 腳本：第一句落在 0.3 秒結束（第一塊內），第二句 0.9 秒（第二塊內）。
        let script = [
            MockUtterance(text: "第一句", startSeconds: 0.1, endSeconds: 0.3),
            MockUtterance(text: "第二句", startSeconds: 0.6, endSeconds: 0.9),
        ]
        let engine = MockTranscriptionEngine(script: script)
        let coordinator = TranscriptionCoordinator(engine: engine, store: store)

        try await OfflineTranscriber.transcribe(
            sessionDirectory: store.directory, session: session, coordinator: coordinator)

        let persisted = try await store.loadSegments()
        #expect(persisted.map(\.text) == ["第一句", "第二句"])
        #expect(persisted.map(\.startSeconds) == [0.1, 0.6])
    }
}
