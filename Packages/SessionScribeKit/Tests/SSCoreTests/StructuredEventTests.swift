import Foundation
import Testing
@testable import SSCore

private let fixtureSegments = [
    TranscriptSegment(
        segmentID: "seg_0132", sessionID: "s1", startSeconds: 2530, endSeconds: 2545,
        text: "口委詢問為什麼選擇此資料集。", isFinal: true, language: "zh-TW",
        engine: "SpeechAnalyzer", model: "system", createdAt: Date(timeIntervalSince1970: 0)),
    TranscriptSegment(
        segmentID: "seg_0133", sessionID: "s1", startSeconds: 2546, endSeconds: 2580,
        text: "學生回覆目前資料來源限制。", isFinal: true, language: "zh-TW",
        engine: "SpeechAnalyzer", model: "system", createdAt: Date(timeIntervalSince1970: 0)),
    TranscriptSegment(
        segmentID: "seg_0200", sessionID: "s1", startSeconds: 3000, endSeconds: 3010,
        text: "下一題。", isFinal: true, language: "zh-TW",
        engine: "SpeechAnalyzer", model: "system", createdAt: Date(timeIntervalSince1970: 0)),
]

@Suite("StructuredEvent 模型（events.json，v0.2）")
struct StructuredEventTests {

    @Test("編碼輸出 snake_case 鍵且必含 needs_review 與來源追溯欄位")
    func encodingMatchesSpec() throws {
        let event = StructuredEvent(
            eventID: "evt_0001", sessionID: "s1",
            startSeconds: 2538, endSeconds: 2582,
            type: "question", topic: "研究方法",
            content: "口委詢問為什麼選擇此資料集。",
            priority: "high", confidence: "low",
            sourceSegmentIDs: ["seg_0132", "seg_0133"],
            sourceMarkerIDs: ["m_0001"],
            createdAt: Date(timeIntervalSince1970: 1_781_488_800))
        let data = try SSJSON.lineEncoder.encode(event)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["event_id"] as? String == "evt_0001")
        #expect(object["start_seconds"] as? Double == 2538)
        #expect(object["end_seconds"] as? Double == 2582)
        #expect(object["needs_review"] as? Bool == true)
        #expect(object["source_segment_ids"] as? [String] == ["seg_0132", "seg_0133"])
        #expect(object["source_marker_ids"] as? [String] == ["m_0001"])
        #expect(object["speaker"] is String)
        #expect(object["response_summary"] is String)
        #expect(object["action_item"] is String)
        #expect(object["tags"] is [Any])
    }

    @Test("events.json 原子寫入與讀回；不存在回傳 nil")
    func eventsFileRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(try EventsFile.readIfPresent(from: root) == nil)

        let document = EventsDocument(events: [
            StructuredEvent(
                eventID: "evt_0001", sessionID: "s1", startSeconds: 1, endSeconds: 2,
                type: "question", topic: "", content: "內容",
                priority: "medium", confidence: "low",
                sourceSegmentIDs: [], sourceMarkerIDs: [],
                createdAt: Date(timeIntervalSince1970: 100))
        ])
        try EventsFile.write(document, to: root)
        let loaded = try #require(try EventsFile.readIfPresent(from: root))
        #expect(loaded == document)
    }
}

@Suite("EventDraftBuilder（v0.2）")
struct EventDraftBuilderTests {

    private let marker = Marker(
        markerID: "m_0001", sessionID: "s1", mediaSeconds: 2538,
        type: "question", label: "問題", note: "資料集代表性",
        createdAt: Date(timeIntervalSince1970: 0))

    @Test("依 marker 前 30 後 90 秒視窗收集 segments 生成草稿")
    func buildsDraftFromWindow() {
        let drafts = EventDraftBuilder.drafts(
            markers: [marker], segments: fixtureSegments, sessionID: "s1",
            now: { Date(timeIntervalSince1970: 1_781_488_800) })
        #expect(drafts.count == 1)
        let draft = drafts[0]
        #expect(draft.eventID == "evt_0001")
        #expect(draft.type == "question")
        #expect(draft.needsReview)
        // seg_0132 與 seg_0133 在視窗內；seg_0200（3000 秒）在 2538+90 之外。
        #expect(draft.sourceSegmentIDs == ["seg_0132", "seg_0133"])
        #expect(draft.sourceMarkerIDs == ["m_0001"])
        #expect(draft.startSeconds == 2530)
        #expect(draft.endSeconds == 2580)
        #expect(draft.content.contains("口委詢問"))
        #expect(draft.content.contains("學生回覆"))
        #expect(draft.topic == "資料集代表性")
    }

    @Test("marker type 對應優先程度：必改 high、問題 medium、建議 low")
    func mapsPriorityFromMarkerType() {
        let markers = [
            Marker(
                markerID: "m_0001", sessionID: "s1", mediaSeconds: 10,
                type: "required_revision", label: "必改",
                createdAt: Date(timeIntervalSince1970: 0)),
            Marker(
                markerID: "m_0002", sessionID: "s1", mediaSeconds: 20,
                type: "question", label: "問題",
                createdAt: Date(timeIntervalSince1970: 0)),
            Marker(
                markerID: "m_0003", sessionID: "s1", mediaSeconds: 30,
                type: "suggestion", label: "建議",
                createdAt: Date(timeIntervalSince1970: 0)),
        ]
        let drafts = EventDraftBuilder.drafts(
            markers: markers, segments: [], sessionID: "s1",
            now: { Date(timeIntervalSince1970: 0) })
        #expect(drafts.map(\.priority) == ["high", "medium", "low"])
        #expect(drafts.map(\.eventID) == ["evt_0001", "evt_0002", "evt_0003"])
    }

    @Test("視窗內沒有 segments 時草稿時間取 marker 時點、內容空白")
    func emptyWindowFallsBackToMarkerTime() {
        let drafts = EventDraftBuilder.drafts(
            markers: [marker], segments: [], sessionID: "s1",
            now: { Date(timeIntervalSince1970: 0) })
        #expect(drafts[0].startSeconds == 2538)
        #expect(drafts[0].endSeconds == 2538)
        #expect(drafts[0].content.isEmpty)
        #expect(drafts[0].needsReview)
    }
}

@Suite("Lexicon 名詞表校正（v0.2）")
struct LexiconTests {

    @Test("依規則順序做全文替換")
    func appliesRulesInOrder() {
        let rules = [
            LexiconRule(from: "博特", to: "BERT"),
            LexiconRule(from: "資料急", to: "資料集"),
        ]
        let corrected = Lexicon.apply("我們用博特跑這個資料急，博特表現不錯。", rules: rules)
        #expect(corrected == "我們用BERT跑這個資料集，BERT表現不錯。")
    }

    @Test("空規則表回傳原文")
    func emptyRulesReturnOriginal() {
        #expect(Lexicon.apply("原文", rules: []) == "原文")
    }
}

@Suite("LibraryConfig v0.2 擴充：自訂標記與名詞表")
struct LibraryConfigV02Tests {

    @Test("自訂 marker type 與名詞表規則 round-trip；舊檔缺欄位為空")
    func roundTripAndBackwardCompatible() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // 舊格式：只有 categories。
        let legacy = #"{"schema_version": 1, "categories": []}"#
        try Data(legacy.utf8).write(to: root.appending(path: "library.json"))
        let loaded = try LibraryConfigFile.read(from: root)
        #expect(loaded.markerTypes.isEmpty)
        #expect(loaded.lexicon.isEmpty)

        var config = LibraryConfig()
        config.markerTypes = [MarkerType(rawValue: "decision", label: "決議")]
        config.lexicon = [LexiconRule(from: "博特", to: "BERT")]
        try LibraryConfigFile.write(config, to: root)
        let reloaded = try LibraryConfigFile.read(from: root)
        #expect(reloaded.markerTypes == config.markerTypes)
        #expect(reloaded.lexicon == config.lexicon)
    }
}

@Suite("SessionTemplate（v0.2 模板系統）")
struct SessionTemplateTests {

    @Test("內建四種模板，論文口試為預設且含規格四鍵")
    func builtInTemplates() {
        #expect(SessionTemplate.builtIns.map(\.id) == [
            "thesis_defense", "meeting", "interview", "lecture",
        ])
        let defense = SessionTemplate.builtIns[0]
        #expect(defense.markerTypes == MarkerType.defaults)
        for template in SessionTemplate.builtIns {
            #expect(template.markerTypes.count == 4, "四鍵對應 Q/R/S/A")
            #expect(!template.name.isEmpty)
        }
    }

    @Test("依 id 查模板，未知 id 退回論文口試")
    func lookupByID() {
        #expect(SessionTemplate.template(for: "meeting").id == "meeting")
        #expect(SessionTemplate.template(for: "不存在").id == "thesis_defense")
    }
}
