import Foundation
import Testing
@testable import SSCore

@Suite("AudioManifest 模型")
struct AudioManifestTests {

    @Test("可解碼規格書第八節的 manifest 範例")
    func decodesSpecSample() throws {
        let json = """
        {
          "schema_version": 2,
          "sample_rate": 48000,
          "channels": 1,
          "chunks": [
            {
              "file": "chunk_0001.caf",
              "start_seconds": 0.0,
              "duration_seconds": 300.0,
              "created_at": "2026-06-15T10:06:12+08:00"
            }
          ]
        }
        """
        let manifest = try SSJSON.decoder.decode(AudioManifest.self, from: Data(json.utf8))
        #expect(manifest.sampleRate == 48000)
        #expect(manifest.channels == 1)
        #expect(manifest.chunks.count == 1)
        #expect(manifest.chunks[0].file == "chunk_0001.caf")
        #expect(manifest.chunks[0].startSeconds == 0.0)
        #expect(manifest.chunks[0].durationSeconds == 300.0)
    }

    @Test("編碼輸出 snake_case 鍵")
    func encodingUsesSnakeCase() throws {
        let manifest = AudioManifest(
            sampleRate: 48000,
            channels: 1,
            chunks: [
                AudioChunk(
                    file: "chunk_0001.caf", startSeconds: 0, durationSeconds: 300,
                    createdAt: Date(timeIntervalSince1970: 1_781_402_772))
            ])
        let data = try SSJSON.lineEncoder.encode(manifest)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schema_version"] as? Int == SchemaVersion.current)
        #expect(object["sample_rate"] as? Double == 48000)
        #expect(object["channels"] as? Int == 1)
        let chunks = try #require(object["chunks"] as? [[String: Any]])
        #expect(chunks[0]["file"] as? String == "chunk_0001.caf")
        #expect(chunks[0]["start_seconds"] as? Double == 0)
        #expect(chunks[0]["duration_seconds"] as? Double == 300)
        #expect(chunks[0]["created_at"] is String)
    }

    @Test("編解碼 round-trip 不失真")
    func roundTrip() throws {
        let manifest = AudioManifest(
            sampleRate: 44100,
            channels: 2,
            chunks: [
                AudioChunk(
                    file: "chunk_0001.caf", startSeconds: 0, durationSeconds: 300,
                    createdAt: Date(timeIntervalSince1970: 1_781_402_772)),
                AudioChunk(
                    file: "chunk_0002.caf", startSeconds: 300, durationSeconds: 12.5,
                    createdAt: Date(timeIntervalSince1970: 1_781_403_072)),
            ])
        let data = try SSJSON.lineEncoder.encode(manifest)
        let decoded = try SSJSON.decoder.decode(AudioManifest.self, from: data)
        #expect(decoded == manifest)
    }

    @Test("AudioManifestFile 原子寫入 audio/manifest.json 並可讀回")
    func manifestFileRoundTrip() throws {
        let audioDirectory = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: audioDirectory, withIntermediateDirectories: true)
        let manifest = AudioManifest(
            sampleRate: 48000,
            channels: 1,
            chunks: [
                AudioChunk(
                    file: "chunk_0001.caf", startSeconds: 0, durationSeconds: 1.5,
                    createdAt: Date(timeIntervalSince1970: 1_781_402_772))
            ])
        try AudioManifestFile.write(manifest, to: audioDirectory)
        #expect(
            FileManager.default.fileExists(
                atPath: audioDirectory.appending(path: "manifest.json").path))
        let loaded = try AudioManifestFile.read(from: audioDirectory)
        #expect(loaded == manifest)
    }

    @Test("manifest 不存在時讀取回傳 nil")
    func missingManifestReturnsNil() throws {
        let audioDirectory = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: audioDirectory, withIntermediateDirectories: true)
        #expect(try AudioManifestFile.readIfPresent(from: audioDirectory) == nil)
    }
}
