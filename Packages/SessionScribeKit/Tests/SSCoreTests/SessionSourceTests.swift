import Foundation
import Testing
@testable import SSCore

@Suite("Session source 欄位（規格 1.1 第 6 項）")
struct SessionSourceTests {

    @Test("舊 metadata 缺 source 欄位時視為 recorded")
    func missingSourceDefaultsToRecorded() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "2026-06-15_1000_a3f2",
          "title": "舊資料",
          "template_id": "thesis_defense",
          "created_at": "2026-06-15T10:00:00+08:00",
          "started_at": null,
          "ended_at": null,
          "locale": "zh-TW",
          "asr_engine": "",
          "privacy_mode": "local_only",
          "audio_input": "",
          "recovered": false,
          "notes": "",
          "app_version": "0.1.0"
        }
        """
        let session = try SSJSON.decoder.decode(Session.self, from: Data(json.utf8))
        #expect(session.source == .recorded)
    }

    @Test("imported session 編解碼 round-trip")
    func importedRoundTrips() throws {
        var session = Session(
            sessionID: "2026-06-15_1000_b4c1", title: "匯入的音檔",
            templateID: "thesis_defense",
            createdAt: Date(timeIntervalSince1970: 1_781_488_800),
            locale: "zh-TW", appVersion: "0.1.0")
        session.source = .imported
        let data = try SSJSON.lineEncoder.encode(session)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["source"] as? String == "imported")
        let decoded = try SSJSON.decoder.decode(Session.self, from: data)
        #expect(decoded == session)
    }
}

@Suite("AudioManifest 時間定位（播放跳轉用）")
struct AudioManifestLocateTests {

    private let manifest = AudioManifest(
        sampleRate: 48000, channels: 1,
        chunks: [
            AudioChunk(
                file: "chunk_0001.caf", startSeconds: 0, durationSeconds: 300,
                createdAt: Date(timeIntervalSince1970: 0)),
            AudioChunk(
                file: "chunk_0002.caf", startSeconds: 300, durationSeconds: 120.5,
                createdAt: Date(timeIntervalSince1970: 0)),
        ])

    @Test("時間落在 chunk 內回傳索引與偏移")
    func locatesWithinChunk() {
        let hit = manifest.locate(seconds: 310)
        #expect(hit?.chunkIndex == 1)
        #expect(hit?.offsetSeconds == 10)
    }

    @Test("chunk 邊界歸屬後一塊")
    func boundaryBelongsToNextChunk() {
        let hit = manifest.locate(seconds: 300)
        #expect(hit?.chunkIndex == 1)
        #expect(hit?.offsetSeconds == 0)
    }

    @Test("零秒落在第一塊起點")
    func zeroIsFirstChunk() {
        let hit = manifest.locate(seconds: 0)
        #expect(hit?.chunkIndex == 0)
        #expect(hit?.offsetSeconds == 0)
    }

    @Test("超出總長回傳 nil；總長正確")
    func beyondEndReturnsNil() {
        #expect(manifest.locate(seconds: 99999) == nil)
        #expect(manifest.totalDurationSeconds == 420.5)
    }

    @Test("空 manifest 回傳 nil 與零長度")
    func emptyManifest() {
        let empty = AudioManifest(sampleRate: 48000, channels: 1)
        #expect(empty.locate(seconds: 0) == nil)
        #expect(empty.totalDurationSeconds == 0)
    }
}
