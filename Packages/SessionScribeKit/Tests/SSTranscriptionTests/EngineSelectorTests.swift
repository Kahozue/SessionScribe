import Foundation
import Testing
@testable import SSTranscription
import SSCore

/// 固定可用性的假引擎，只用於 selector 測試。
private struct StubEngine: TranscriptionEngine {
    struct PrepareFailure: Error {}

    let info: EngineInfo
    let result: EngineAvailability
    var prepareFails = false

    init(name: String, result: EngineAvailability, prepareFails: Bool = false) {
        self.info = EngineInfo(name: name, isOnDevice: true)
        self.result = result
        self.prepareFails = prepareFails
    }

    func availability(for locale: Locale) async -> EngineAvailability { result }
    func prepare(locale: Locale) async throws {
        if prepareFails { throw PrepareFailure() }
    }
    func start(sessionID: String, locale: Locale) async throws {}
    func feed(_ slice: AudioSlice) async throws {}
    func finish() async throws {}
    func finalizedSegments() async -> AsyncStream<TranscriptSegment> {
        AsyncStream { $0.finish() }
    }
    func volatileUpdates() async -> AsyncStream<VolatileUpdate> {
        AsyncStream { $0.finish() }
    }
}

@Suite("EngineSelector")
struct EngineSelectorTests {
    private let locale = Locale(identifier: "zh-TW")

    @Test("依序挑第一個非 unsupported 的引擎")
    func picksFirstUsableEngine() async {
        let selected = await EngineSelector.select(
            from: [
                StubEngine(name: "A", result: .unsupported),
                StubEngine(name: "B", result: .requiresDownload),
                StubEngine(name: "C", result: .available),
            ], locale: locale)
        #expect(selected?.info.name == "B")
    }

    @Test("第一個就可用時不再往下找")
    func prefersFirstEngine() async {
        let selected = await EngineSelector.select(
            from: [
                StubEngine(name: "A", result: .available),
                StubEngine(name: "B", result: .available),
            ], locale: locale)
        #expect(selected?.info.name == "A")
    }

    @Test("prepare 失敗時降級到下一個引擎")
    func fallsThroughWhenPrepareFails() async {
        let selected = await EngineSelector.selectAndPrepare(
            from: [
                StubEngine(name: "A", result: .requiresDownload, prepareFails: true),
                StubEngine(name: "B", result: .available),
            ], locale: locale)
        #expect(selected?.info.name == "B")
    }

    @Test("全部 unsupported 時回傳 nil（純錄音模式）")
    func returnsNilWhenNoneUsable() async {
        let selected = await EngineSelector.select(
            from: [
                StubEngine(name: "A", result: .unsupported),
                StubEngine(name: "B", result: .unsupported),
            ], locale: locale)
        #expect(selected == nil)
    }
}

@Suite("實機引擎可用性（依 spike 結果）")
struct RealEngineAvailabilityTests {

    @Test("AppleSpeechEngine 對 zh-TW 非 unsupported（spike 已證實支援）")
    func appleEngineSupportsZhTW() async {
        let engine = AppleSpeechEngine()
        let availability = await engine.availability(for: Locale(identifier: "zh-TW"))
        #expect(availability != .unsupported)
    }

    @Test("LegacySFSpeechEngine 可用性查詢不崩潰")
    func legacyEngineAvailabilityIsSafe() async {
        let engine = LegacySFSpeechEngine()
        _ = await engine.availability(for: Locale(identifier: "zh-TW"))
    }
}
