import Foundation
import Testing
@testable import SSCore

@Suite("Session 模型")
struct SessionTests {

    @Test("編碼輸出 snake_case 鍵，optional 欄位輸出明確 null")
    func encodingUsesSnakeCaseAndExplicitNull() throws {
        let session = Session(
            sessionID: "2026-06-15_1000_a3f2",
            title: "碩士論文口試 - 第一場",
            templateID: "thesis_defense",
            createdAt: Date(timeIntervalSince1970: 1_781_402_400),
            locale: "zh-TW",
            asrEngine: "SpeechAnalyzer",
            audioInput: "MacBook Air Microphone",
            appVersion: "0.1.0"
        )
        let data = try SSJSON.lineEncoder.encode(session)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schema_version"] as? Int == 1)
        #expect(object["session_id"] as? String == "2026-06-15_1000_a3f2")
        #expect(object["template_id"] as? String == "thesis_defense")
        #expect(object["started_at"] is NSNull)
        #expect(object["ended_at"] is NSNull)
        #expect(object["privacy_mode"] as? String == "local_only")
        #expect(object["asr_engine"] as? String == "SpeechAnalyzer")
        #expect(object["audio_input"] as? String == "MacBook Air Microphone")
        #expect(object["recovered"] as? Bool == false)
        #expect(object["app_version"] as? String == "0.1.0")
    }

    @Test("可解碼規格書第八節的 metadata 範例")
    func decodesSpecSample() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "2026-06-15_1000_a3f2",
          "title": "碩士論文口試 - 第一場",
          "template_id": "thesis_defense",
          "created_at": "2026-06-15T10:00:00+08:00",
          "started_at": "2026-06-15T10:01:12+08:00",
          "ended_at": null,
          "locale": "zh-TW",
          "asr_engine": "SpeechAnalyzer",
          "privacy_mode": "local_only",
          "audio_input": "MacBook Air Microphone",
          "recovered": false,
          "notes": "",
          "app_version": "0.1.0"
        }
        """
        let session = try SSJSON.decoder.decode(Session.self, from: Data(json.utf8))
        #expect(session.sessionID == "2026-06-15_1000_a3f2")
        #expect(session.endedAt == nil)
        #expect(session.privacyMode == .localOnly)
        let expectedCreated = try #require(
            ISO8601DateFormatter().date(from: "2026-06-15T10:00:00+08:00"))
        #expect(session.createdAt == expectedCreated)
        let expectedStarted = try #require(
            ISO8601DateFormatter().date(from: "2026-06-15T10:01:12+08:00"))
        #expect(session.startedAt == expectedStarted)
    }

    @Test("編解碼 round-trip 不失真（ISO-8601 為秒級精度，時間取整秒）")
    func roundTrip() throws {
        var session = Session(
            sessionID: Session.makeID(),
            title: "測試場次",
            templateID: "thesis_defense",
            createdAt: Date(timeIntervalSince1970: 1_781_402_400),
            locale: "zh-TW",
            appVersion: "0.1.0"
        )
        session.startedAt = Date(timeIntervalSince1970: 1_781_402_472)
        session.endedAt = Date(timeIntervalSince1970: 1_781_409_600)
        session.recovered = true
        session.notes = "備註"
        let data = try SSJSON.lineEncoder.encode(session)
        let decoded = try SSJSON.decoder.decode(Session.self, from: data)
        #expect(decoded == session)
    }

    @Test("session id 格式為 YYYY-MM-DD_HHmm_xxxx")
    func idMatchesSpecFormat() throws {
        let id = Session.makeID()
        #expect(id.wholeMatch(of: /\d{4}-\d{2}-\d{2}_\d{4}_[0-9a-f]{4}/) != nil)
    }

    @Test("session id 以注入的日期、時區與後綴決定")
    func idIsDeterministicWithInjectedParts() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-06-15T10:00:00+08:00"))
        let timeZone = try #require(TimeZone(identifier: "Asia/Taipei"))
        let id = Session.makeID(date: date, timeZone: timeZone, suffix: "a3f2")
        #expect(id == "2026-06-15_1000_a3f2")
    }
}

@Suite("TranscriptSegment 模型")
struct TranscriptSegmentTests {

    @Test("可解碼規格書第八節的 segment 範例")
    func decodesSpecSample() throws {
        let json = """
        {
          "schema_version": 1,
          "segment_id": "seg_0001",
          "session_id": "2026-06-15_1000_a3f2",
          "start_seconds": 12.3,
          "end_seconds": 18.7,
          "text": "請問你為什麼選擇這個資料集？",
          "is_final": true,
          "language": "zh-TW",
          "engine": "SpeechAnalyzer",
          "model": "system",
          "confidence": null,
          "created_at": "2026-06-15T10:01:30+08:00"
        }
        """
        let segment = try SSJSON.decoder.decode(TranscriptSegment.self, from: Data(json.utf8))
        #expect(segment.segmentID == "seg_0001")
        #expect(segment.startSeconds == 12.3)
        #expect(segment.endSeconds == 18.7)
        #expect(segment.isFinal)
        #expect(segment.confidence == nil)
    }

    @Test("編碼輸出 snake_case 鍵且 confidence 為明確 null")
    func encodingUsesSnakeCaseAndExplicitNull() throws {
        let segment = TranscriptSegment(
            segmentID: "seg_0001",
            sessionID: "2026-06-15_1000_a3f2",
            startSeconds: 12.3,
            endSeconds: 18.7,
            text: "請問你為什麼選擇這個資料集？",
            isFinal: true,
            language: "zh-TW",
            engine: "SpeechAnalyzer",
            model: "system",
            createdAt: Date(timeIntervalSince1970: 1_781_402_490)
        )
        let data = try SSJSON.lineEncoder.encode(segment)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["segment_id"] as? String == "seg_0001")
        #expect(object["start_seconds"] as? Double == 12.3)
        #expect(object["end_seconds"] as? Double == 18.7)
        #expect(object["is_final"] as? Bool == true)
        #expect(object["confidence"] is NSNull)
    }

    @Test("文字含換行時編碼仍為單行")
    func encodingStaysSingleLine() throws {
        let segment = TranscriptSegment(
            segmentID: "seg_0002",
            sessionID: "2026-06-15_1000_a3f2",
            startSeconds: 0,
            endSeconds: 1,
            text: "第一行\n第二行",
            isFinal: true,
            language: "zh-TW",
            engine: "Mock",
            model: "mock",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let data = try SSJSON.lineEncoder.encode(segment)
        #expect(!data.contains(UInt8(ascii: "\n")))
    }

    @Test("編解碼 round-trip 不失真")
    func roundTrip() throws {
        var segment = TranscriptSegment(
            segmentID: "seg_0003",
            sessionID: "s",
            startSeconds: 1.5,
            endSeconds: 2.5,
            text: "abc",
            isFinal: false,
            language: "zh-TW",
            engine: "Mock",
            model: "mock",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        segment.confidence = 0.5
        let data = try SSJSON.lineEncoder.encode(segment)
        let decoded = try SSJSON.decoder.decode(TranscriptSegment.self, from: data)
        #expect(decoded == segment)
    }
}

@Suite("Marker 模型")
struct MarkerTests {

    @Test("可解碼規格書第八節的 marker 範例")
    func decodesSpecSample() throws {
        let json = """
        {
          "schema_version": 1,
          "marker_id": "m_0001",
          "session_id": "2026-06-15_1000_a3f2",
          "media_seconds": 2538.0,
          "type": "question",
          "label": "問題",
          "note": "",
          "nearest_segment_ids": ["seg_0132"],
          "created_at": "2026-06-15T10:43:30+08:00"
        }
        """
        let marker = try SSJSON.decoder.decode(Marker.self, from: Data(json.utf8))
        #expect(marker.markerID == "m_0001")
        #expect(marker.mediaSeconds == 2538.0)
        #expect(marker.type == "question")
        #expect(marker.nearestSegmentIDs == ["seg_0132"])
    }

    @Test("type 是開放字串，自定義值可編解碼")
    func customTypeRoundTrips() throws {
        let marker = Marker(
            markerID: "m_0002",
            sessionID: "s",
            mediaSeconds: 10,
            type: "my_custom_type",
            label: "自訂",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let data = try SSJSON.lineEncoder.encode(marker)
        let decoded = try SSJSON.decoder.decode(Marker.self, from: data)
        #expect(decoded == marker)
        #expect(decoded.type == "my_custom_type")
    }

    @Test("預設四種 marker type 與標籤符合規格")
    func defaultTypesMatchSpec() {
        #expect(MarkerType.defaults.map(\.rawValue) == [
            "question", "required_revision", "suggestion", "important_answer",
        ])
        #expect(MarkerType.question.label == "問題")
        #expect(MarkerType.requiredRevision.label == "必改")
        #expect(MarkerType.suggestion.label == "建議")
        #expect(MarkerType.importantAnswer.label == "重要回答")
    }

    @Test("編碼輸出 snake_case 鍵")
    func encodingUsesSnakeCase() throws {
        let marker = Marker(
            markerID: "m_0003",
            sessionID: "s",
            mediaSeconds: 5.5,
            type: MarkerType.question.rawValue,
            label: MarkerType.question.label,
            nearestSegmentIDs: ["seg_0001", "seg_0002"],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let data = try SSJSON.lineEncoder.encode(marker)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["marker_id"] as? String == "m_0003")
        #expect(object["media_seconds"] as? Double == 5.5)
        #expect(object["nearest_segment_ids"] as? [String] == ["seg_0001", "seg_0002"])
    }
}
