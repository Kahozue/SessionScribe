import Foundation
import Testing
@testable import SSCore

// MARK: - 共用 fixture

private let fixtureSession = Session(
    sessionID: "2026-06-15_1000_a3f2",
    title: "碩士論文口試 - 第一場",
    templateID: "thesis_defense",
    createdAt: Date(timeIntervalSince1970: 1_781_488_800),
    locale: "zh-TW",
    asrEngine: "SpeechAnalyzer",
    appVersion: "0.1.0"
)

private let fixtureSegments = [
    TranscriptSegment(
        segmentID: "seg_0001", sessionID: "2026-06-15_1000_a3f2",
        startSeconds: 12.3, endSeconds: 18.7,
        text: "請問你為什麼選擇這個資料集？", isFinal: true, language: "zh-TW",
        engine: "SpeechAnalyzer", model: "system",
        createdAt: Date(timeIntervalSince1970: 1_781_402_420)),
    TranscriptSegment(
        segmentID: "seg_0002", sessionID: "2026-06-15_1000_a3f2",
        startSeconds: 18.7, endSeconds: 25.0,
        text: "因為它是公開且有標註的。", isFinal: true, language: "zh-TW",
        engine: "SpeechAnalyzer", model: "system",
        createdAt: Date(timeIntervalSince1970: 1_781_402_426)),
]

private let fixtureMarkers = [
    Marker(
        markerID: "m_0001", sessionID: "2026-06-15_1000_a3f2", mediaSeconds: 15.0,
        type: "question", label: "問題", note: "追問資料集來源",
        nearestSegmentIDs: ["seg_0001"],
        createdAt: Date(timeIntervalSince1970: 1_781_402_415))
]

@Suite("MarkdownExporter")
struct MarkdownExporterTests {

    @Test("輸出含 metadata 區塊、時間排序 segments 與內嵌 markers")
    func fullTranscriptLayout() {
        let markdown = MarkdownExporter.transcript(
            session: fixtureSession, segments: fixtureSegments, markers: fixtureMarkers)
        let expected = """
        # 碩士論文口試 - 第一場

        - session_id：2026-06-15_1000_a3f2
        - 語言：zh-TW
        - 引擎：SpeechAnalyzer
        - 建立時間：2026-06-15T02:00:00Z
        - segments：2
        - markers：1

        ## 逐字稿

        **[00:00:12 - 00:00:18]** 請問你為什麼選擇這個資料集？

        > **標記｜問題** [00:00:15] 追問資料集來源

        **[00:00:18 - 00:00:25]** 因為它是公開且有標註的。

        """
        #expect(markdown == expected)
    }

    @Test("marker 無 note 時行尾不留空白")
    func markerWithoutNote() {
        let marker = Marker(
            markerID: "m_0001", sessionID: "s", mediaSeconds: 15.0,
            type: "question", label: "問題",
            createdAt: Date(timeIntervalSince1970: 0))
        let markdown = MarkdownExporter.transcript(
            session: fixtureSession, segments: fixtureSegments, markers: [marker])
        #expect(markdown.contains("> **標記｜問題** [00:00:15]\n"))
        #expect(!markdown.contains("[00:00:15] \n"))
    }

    @Test("空 transcript 輸出占位文字而非空白")
    func emptyTranscript() {
        let markdown = MarkdownExporter.transcript(
            session: fixtureSession, segments: [], markers: [])
        #expect(markdown.contains("（無逐字稿內容）"))
    }

    @Test("接受 segment 子集（選取匯出）")
    func selectionSubset() {
        let markdown = MarkdownExporter.transcript(
            session: fixtureSession, segments: [fixtureSegments[1]], markers: [])
        #expect(!markdown.contains("請問你為什麼選擇這個資料集？"))
        #expect(markdown.contains("因為它是公開且有標註的。"))
        #expect(markdown.contains("- segments：1"))
    }
}

@Suite("CSVExporter")
struct CSVExporterTests {

    @Test("markers.csv 含時間、類型、備註與動態重算的鄰近文字")
    func markersCSVLayout() {
        let csv = CSVExporter.markersCSV(
            markers: fixtureMarkers, segments: [fixtureSegments[0]])
        let expected = """
        media_seconds,time,type,label,note,nearest_segment_text
        15.0,00:00:15,question,問題,追問資料集來源,請問你為什麼選擇這個資料集？

        """
        #expect(csv == expected)
    }

    @Test("含逗號、引號與換行的欄位正確跳脫")
    func escapesSpecialCharacters() {
        let marker = Marker(
            markerID: "m_0001", sessionID: "s", mediaSeconds: 15.0,
            type: "question", label: "問題", note: "逗號,與\"引號\"與\n換行",
            createdAt: Date(timeIntervalSince1970: 0))
        let csv = CSVExporter.markersCSV(markers: [marker], segments: [])
        #expect(csv.contains(#""逗號,與""引號""與"#))
    }

    @Test("鄰近多個 segment 時文字以斜線串接")
    func joinsMultipleNearestSegments() {
        let csv = CSVExporter.markersCSV(markers: fixtureMarkers, segments: fixtureSegments)
        #expect(csv.contains("請問你為什麼選擇這個資料集？ / 因為它是公開且有標註的。"))
    }
}

@Suite("JSONExporter")
struct JSONExporterTests {

    @Test("session bundle 含 metadata、segments、markers 三鍵且可解碼還原")
    func bundleRoundTrip() throws {
        let data = try JSONExporter.sessionBundle(
            session: fixtureSession, segments: fixtureSegments, markers: fixtureMarkers)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["session"] is [String: Any])
        #expect((object["segments"] as? [Any])?.count == 2)
        #expect((object["markers"] as? [Any])?.count == 1)
    }
}

@Suite("ExportService")
struct ExportServiceTests {

    @Test("匯出目錄含 transcript.md、markers.csv、session.json 與 jsonl 副本")
    func exportsAllFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try await SessionStore.create(fixtureSession, in: root)
        for segment in fixtureSegments {
            try await store.appendSegment(segment)
        }
        for marker in fixtureMarkers {
            try await store.appendMarker(marker)
        }

        let destination = root.appending(path: "out")
        try await ExportService.export(
            store: store, session: fixtureSession, to: destination)

        let fm = FileManager.default
        for name in [
            "transcript.md", "markers.csv", "session.json",
            "live_segments.jsonl", "manual_markers.jsonl",
        ] {
            #expect(fm.fileExists(atPath: destination.appending(path: name).path), "缺 \(name)")
        }
        let markdown = try String(
            contentsOf: destination.appending(path: "transcript.md"), encoding: .utf8)
        #expect(
            markdown
                == MarkdownExporter.transcript(
                    session: fixtureSession, segments: fixtureSegments, markers: fixtureMarkers))
    }
}
