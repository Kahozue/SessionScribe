import AVFoundation
import Foundation
import Testing
@testable import SSTranscription
import SSCore

/// 以指定媒體時間產生空 buffer 的 slice：mock 引擎只看時間不看內容。
private func slice(at seconds: Double) -> AudioSlice {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
    return AudioSlice(buffer: buffer, startSeconds: seconds)
}

private let script = [
    MockUtterance(text: "請問你為什麼選擇這個資料集？", startSeconds: 1, endSeconds: 4),
    MockUtterance(text: "因為它是公開且有標註的。", startSeconds: 5, endSeconds: 8),
]

@Suite("MockTranscriptionEngine")
struct MockEngineTests {

    @Test("媒體時間越過 utterance 終點時 finalize，編號與時間正確")
    func finalizesUtterancesAsTimePasses() async throws {
        let engine = MockTranscriptionEngine(script: script)
        let finalized = await engine.finalizedSegments()
        try await engine.start(sessionID: "s1", locale: Locale(identifier: "zh-TW"))

        try await engine.feed(slice(at: 4.5))
        try await engine.feed(slice(at: 9.0))
        try await engine.finish()

        var segments: [TranscriptSegment] = []
        for await segment in finalized {
            segments.append(segment)
        }
        #expect(segments.count == 2)
        #expect(segments[0].segmentID == "seg_0001")
        #expect(segments[0].text == "請問你為什麼選擇這個資料集？")
        #expect(segments[0].startSeconds == 1)
        #expect(segments[0].endSeconds == 4)
        #expect(segments[0].isFinal)
        #expect(segments[0].sessionID == "s1")
        #expect(segments[0].engine == "Mock")
        #expect(segments[1].segmentID == "seg_0002")
    }

    @Test("進行中的 utterance 發出漸進 volatile，不提前 finalize")
    func emitsVolatileWhileInProgress() async throws {
        let engine = MockTranscriptionEngine(script: script)
        let volatileStream = await engine.volatileUpdates()
        try await engine.start(sessionID: "s1", locale: Locale(identifier: "zh-TW"))

        // 1 至 4 秒的 utterance，餵到 2.5 秒：進度約一半。
        try await engine.feed(slice(at: 2.5))
        try await engine.finish()

        var updates: [VolatileUpdate] = []
        for await update in volatileStream {
            updates.append(update)
        }
        let lastBeforeFinish = try #require(updates.first)
        #expect(!lastBeforeFinish.text.isEmpty)
        #expect(lastBeforeFinish.text.count < script[0].text.count)
        #expect(script[0].text.hasPrefix(lastBeforeFinish.text))
    }

    @Test("finish 把已開始未完成的 utterance 收尾為 finalized")
    func finishFinalizesInProgressUtterance() async throws {
        let engine = MockTranscriptionEngine(script: script)
        let finalized = await engine.finalizedSegments()
        try await engine.start(sessionID: "s1", locale: Locale(identifier: "zh-TW"))
        try await engine.feed(slice(at: 2.5))
        try await engine.finish()

        var segments: [TranscriptSegment] = []
        for await segment in finalized {
            segments.append(segment)
        }
        #expect(segments.count == 1)
        #expect(segments[0].text == script[0].text)
    }

    @Test("注入錯誤：越過 failAtSeconds 的 feed 拋錯")
    func injectedFailureThrows() async throws {
        let engine = MockTranscriptionEngine(script: script, failAtSeconds: 3)
        try await engine.start(sessionID: "s1", locale: Locale(identifier: "zh-TW"))
        try await engine.feed(slice(at: 2))
        await #expect(throws: (any Error).self) {
            try await engine.feed(slice(at: 3.5))
        }
    }

    @Test("任何 locale 都回報可用，prepare 不拋錯")
    func alwaysAvailable() async throws {
        let engine = MockTranscriptionEngine(script: [])
        #expect(await engine.availability(for: Locale(identifier: "xx-XX")) == .available)
        try await engine.prepare(locale: Locale(identifier: "zh-TW"))
        #expect(engine.info.name == "Mock")
        #expect(engine.info.isOnDevice)
    }
}

@Suite("TranscriptionCoordinator")
struct TranscriptionCoordinatorTests {

    private func makeStore() async throws -> SessionStore {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSTranscriptionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = Session(
            sessionID: "s1", title: "測試", templateID: "thesis_defense",
            createdAt: Date(timeIntervalSince1970: 0), locale: "zh-TW", appVersion: "0.1.0")
        return try await SessionStore.create(session, in: root)
    }

    @Test("finalized segment 先落盤再轉發 UI")
    func persistsThenForwards() async throws {
        let store = try await makeStore()
        let engine = MockTranscriptionEngine(script: script)
        let coordinator = TranscriptionCoordinator(engine: engine, store: store)
        let updates = await coordinator.finalizedUpdates()
        try await coordinator.start(sessionID: "s1", locale: Locale(identifier: "zh-TW"))

        await coordinator.feed(slice(at: 9.0))
        await coordinator.finish()

        var forwarded: [TranscriptSegment] = []
        for await segment in updates {
            forwarded.append(segment)
        }
        #expect(forwarded.count == 2)
        let persisted = try await store.loadSegments()
        #expect(persisted == forwarded)
    }

    @Test("名詞表規則套用於 finalized：落盤與轉發的文字都已校正")
    func appliesLexiconToFinalized() async throws {
        let store = try await makeStore()
        let engine = MockTranscriptionEngine(script: [
            MockUtterance(text: "我們用博特跑這個資料急。", startSeconds: 1, endSeconds: 4)
        ])
        let coordinator = TranscriptionCoordinator(
            engine: engine, store: store,
            lexicon: [
                LexiconRule(from: "博特", to: "BERT"),
                LexiconRule(from: "資料急", to: "資料集"),
            ])
        let updates = await coordinator.finalizedUpdates()
        try await coordinator.start(sessionID: "s1", locale: Locale(identifier: "zh-TW"))

        await coordinator.feed(slice(at: 4.5))
        await coordinator.finish()

        var forwarded: [TranscriptSegment] = []
        for await segment in updates {
            forwarded.append(segment)
        }
        #expect(forwarded.count == 1)
        #expect(forwarded[0].text == "我們用BERT跑這個資料集。")
        let persisted = try await store.loadSegments()
        #expect(persisted[0].text == "我們用BERT跑這個資料集。")
    }

    @Test("引擎失敗後 feed 不拋錯、狀態標記失敗、已定稿資料保留（ASR 失敗錄音不中斷）")
    func engineFailureIsContained() async throws {
        let store = try await makeStore()
        let engine = MockTranscriptionEngine(script: script, failAtSeconds: 5)
        let coordinator = TranscriptionCoordinator(engine: engine, store: store)
        try await coordinator.start(sessionID: "s1", locale: Locale(identifier: "zh-TW"))

        await coordinator.feed(slice(at: 4.5))   // 第一句 finalize
        await coordinator.feed(slice(at: 6.0))   // 觸發注入錯誤，不得往外拋
        await coordinator.feed(slice(at: 7.0))   // 失敗後繼續 feed 也安全
        #expect(await coordinator.failed)
        await coordinator.finish()

        let persisted = try await store.loadSegments()
        #expect(persisted.count == 1)
        #expect(persisted[0].text == script[0].text)
    }
}
