import AVFoundation
import Testing
@testable import SSAudio
import SSCore

private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SSAudioTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 產生 1.2 秒、48kHz 單聲道的測試 wav。
private func makeSourceWAV(in directory: URL) throws -> URL {
    let url = directory.appending(path: "口試錄音備份.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(
        forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 57600)!
    buffer.frameLength = 57600
    let channel = buffer.floatChannelData![0]
    for index in 0..<57600 {
        channel[index] = 0.25
    }
    try file.write(from: buffer)
    return url
}

@Suite("AudioImporter")
struct AudioImporterTests {

    @Test("匯入 wav：建立 imported session、轉成 CAF chunks、manifest 長度正確")
    func importsWAVIntoChunks() async throws {
        let root = try makeTempRoot()
        let source = try makeSourceWAV(in: root)

        let session = try await AudioImporter.importFile(
            at: source, into: root, chunkDuration: 0.5)

        #expect(session.source == .imported)
        #expect(session.title == "口試錄音備份")
        // 匯入即完成：endedAt 必須非 null，否則會被當崩潰殘留。
        #expect(session.endedAt != nil)

        let store = SessionStore(directory: root.appending(path: session.sessionID))
        let metadata = try await store.loadMetadata()
        #expect(metadata == session)

        let audioDirectory = store.directory.appending(path: SessionFiles.audioDirectory)
        let manifest = try AudioManifestFile.read(from: audioDirectory)
        // 1.2 秒、0.5 秒一塊：三塊（0.5 + 0.5 + 0.2）。
        #expect(manifest.chunks.count == 3)
        #expect(abs(manifest.totalDurationSeconds - 1.2) < 0.001)
        for chunk in manifest.chunks {
            #expect(
                FileManager.default.fileExists(
                    atPath: audioDirectory.appending(path: chunk.file).path))
        }
    }

    @Test("匯入的 session 不被恢復掃描誤判為崩潰殘留")
    func importedSessionIsNotFlaggedByRecovery() async throws {
        let root = try makeTempRoot()
        let source = try makeSourceWAV(in: root.appending(path: "..").standardized)
        _ = try await AudioImporter.importFile(at: source, into: root)

        let library = SessionLibrary(rootDirectory: root)
        #expect(try library.recoverCrashedSessions().isEmpty)
    }

    @Test("空音檔拋錯，不留半個 session 資料夾")
    func emptyFileThrows() async throws {
        let root = try makeTempRoot()
        let url = root.appending(path: "empty.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        _ = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
            ],
            commonFormat: format.commonFormat, interleaved: false)

        await #expect(throws: (any Error).self) {
            _ = try await AudioImporter.importFile(at: url, into: root)
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0 != "empty.wav" }
        #expect(entries.isEmpty)
    }
}
