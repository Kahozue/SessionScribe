import Foundation
import Synchronization
import Testing
@testable import SSCore

// MARK: - 測試替身

/// 記錄呼叫順序的假錄音管線，可注入 start 與 stop 錯誤。
private final class FakeRecordingPipeline: RecordingPipeline, Sendable {
    struct Failure: Error {}
    private let state = Mutex<(calls: [String], failStart: Bool, failStop: Bool)>(([], false, false))

    var calls: [String] { state.withLock { $0.calls } }

    func setFailStart() { state.withLock { $0.failStart = true } }
    func setFailStop() { state.withLock { $0.failStop = true } }

    func start() async throws {
        let shouldFail = state.withLock { state in
            state.calls.append("start")
            return state.failStart
        }
        if shouldFail { throw Failure() }
    }

    func pause() async throws {
        state.withLock { $0.calls.append("pause") }
    }

    func resume() async throws {
        state.withLock { $0.calls.append("resume") }
    }

    func stop() async throws {
        let shouldFail = state.withLock { state in
            state.calls.append("stop")
            return state.failStop
        }
        if shouldFail { throw Failure() }
    }

    var mediaSeconds: Double { 12.5 }
}

private final class FakeSleepInhibitor: SleepInhibiting, Sendable {
    private let counts = Mutex<(begins: Int, ends: Int)>((0, 0))
    var begins: Int { counts.withLock { $0.begins } }
    var ends: Int { counts.withLock { $0.ends } }

    func begin(reason: String) { counts.withLock { $0.begins += 1 } }
    func end() { counts.withLock { $0.ends += 1 } }
}

private struct Fixture {
    let controller: SessionController
    let store: SessionStore
    let pipeline: FakeRecordingPipeline
    let sleep: FakeSleepInhibitor
    static let now = Date(timeIntervalSince1970: 1_781_402_472)

    init() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SSCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = Session(
            sessionID: "2026-06-15_1000_a3f2",
            title: "測試",
            templateID: "thesis_defense",
            createdAt: Date(timeIntervalSince1970: 1_781_402_400),
            locale: "zh-TW",
            appVersion: "0.1.0"
        )
        store = try await SessionStore.create(session, in: root)
        pipeline = FakeRecordingPipeline()
        sleep = FakeSleepInhibitor()
        controller = SessionController(
            session: session, store: store, pipeline: pipeline,
            sleepInhibitor: sleep, now: { Self.now })
    }
}

// MARK: - 測試

@Suite("SessionController 狀態機")
struct SessionControllerTests {

    @Test("初始狀態為 idle")
    func initialStateIsIdle() async throws {
        let fixture = try await Fixture()
        #expect(await fixture.controller.state == .idle)
    }

    @Test("start：進入 recording，啟動管線、持有防睡眠、startedAt 落盤")
    func startTransitionsToRecording() async throws {
        let fixture = try await Fixture()
        try await fixture.controller.start()
        #expect(await fixture.controller.state == .recording)
        #expect(fixture.pipeline.calls == ["start"])
        #expect(fixture.sleep.begins == 1)
        #expect(fixture.sleep.ends == 0)
        let metadata = try await fixture.store.loadMetadata()
        #expect(metadata.startedAt == Fixture.now)
        #expect(metadata.endedAt == nil)
    }

    @Test("pause 與 resume 在 recording 與 paused 間往返")
    func pauseResumeCycle() async throws {
        let fixture = try await Fixture()
        try await fixture.controller.start()
        try await fixture.controller.pause()
        #expect(await fixture.controller.state == .paused)
        try await fixture.controller.resume()
        #expect(await fixture.controller.state == .recording)
        try await fixture.controller.pause()
        try await fixture.controller.resume()
        #expect(fixture.pipeline.calls == ["start", "pause", "resume", "pause", "resume"])
    }

    @Test("stop：從 recording 進入 stopped，endedAt 落盤、釋放防睡眠")
    func stopFromRecording() async throws {
        let fixture = try await Fixture()
        try await fixture.controller.start()
        try await fixture.controller.stop()
        #expect(await fixture.controller.state == .stopped)
        #expect(fixture.pipeline.calls == ["start", "stop"])
        #expect(fixture.sleep.ends == 1)
        let metadata = try await fixture.store.loadMetadata()
        #expect(metadata.endedAt == Fixture.now)
    }

    @Test("stop：從 paused 也可停止")
    func stopFromPaused() async throws {
        let fixture = try await Fixture()
        try await fixture.controller.start()
        try await fixture.controller.pause()
        try await fixture.controller.stop()
        #expect(await fixture.controller.state == .stopped)
    }

    @Test("非法轉換一律拋 invalidTransition")
    func invalidTransitionsThrow() async throws {
        let fixture = try await Fixture()
        // idle 不可 pause、resume、stop。
        await #expect(throws: SessionController.ControllerError.self) {
            try await fixture.controller.pause()
        }
        await #expect(throws: SessionController.ControllerError.self) {
            try await fixture.controller.resume()
        }
        await #expect(throws: SessionController.ControllerError.self) {
            try await fixture.controller.stop()
        }
        // recording 不可重複 start、不可 resume。
        try await fixture.controller.start()
        await #expect(throws: SessionController.ControllerError.self) {
            try await fixture.controller.start()
        }
        await #expect(throws: SessionController.ControllerError.self) {
            try await fixture.controller.resume()
        }
        // stopped 是終態。
        try await fixture.controller.stop()
        await #expect(throws: SessionController.ControllerError.self) {
            try await fixture.controller.start()
        }
        await #expect(throws: SessionController.ControllerError.self) {
            try await fixture.controller.pause()
        }
    }

    @Test("管線 start 失敗：維持 idle、釋放防睡眠、startedAt 不落盤")
    func pipelineStartFailureKeepsIdle() async throws {
        let fixture = try await Fixture()
        fixture.pipeline.setFailStart()
        await #expect(throws: (any Error).self) {
            try await fixture.controller.start()
        }
        #expect(await fixture.controller.state == .idle)
        #expect(fixture.sleep.begins == 1)
        #expect(fixture.sleep.ends == 1)
        let metadata = try await fixture.store.loadMetadata()
        #expect(metadata.startedAt == nil)
    }

    @Test("管線 stop 失敗：進入 stopped 並釋放防睡眠，endedAt 不落盤留給恢復掃描")
    func pipelineStopFailureLeavesEndedAtNil() async throws {
        let fixture = try await Fixture()
        fixture.pipeline.setFailStop()
        try await fixture.controller.start()
        await #expect(throws: (any Error).self) {
            try await fixture.controller.stop()
        }
        #expect(await fixture.controller.state == .stopped)
        #expect(fixture.sleep.ends == 1)
        let metadata = try await fixture.store.loadMetadata()
        #expect(metadata.endedAt == nil)
    }

    @Test("mediaSeconds 轉發管線目前媒體時間")
    func mediaSecondsForwardsPipeline() async throws {
        let fixture = try await Fixture()
        #expect(await fixture.controller.mediaSeconds == 12.5)
    }
}

@Suite("SleepInhibitor")
struct SleepInhibitorTests {

    @Test("begin 後持有 assertion，end 後釋放")
    func beginEndLifecycle() {
        let inhibitor = SleepInhibitor()
        #expect(!inhibitor.isActive)
        inhibitor.begin(reason: "測試錄音")
        #expect(inhibitor.isActive)
        inhibitor.end()
        #expect(!inhibitor.isActive)
    }

    @Test("重複 begin 具冪等性，單一 end 即可釋放")
    func beginIsIdempotent() {
        let inhibitor = SleepInhibitor()
        inhibitor.begin(reason: "a")
        inhibitor.begin(reason: "b")
        #expect(inhibitor.isActive)
        inhibitor.end()
        #expect(!inhibitor.isActive)
    }

    @Test("未 begin 即 end 不出錯")
    func endWithoutBeginIsNoOp() {
        let inhibitor = SleepInhibitor()
        inhibitor.end()
        #expect(!inhibitor.isActive)
    }
}

@Suite("DiskSpace")
struct DiskSpaceTests {

    @Test("回報暫存目錄所在卷的可用空間為正數")
    func reportsPositiveAvailableBytes() throws {
        let bytes = try DiskSpace.availableBytes(at: FileManager.default.temporaryDirectory)
        #expect(bytes > 0)
    }

    @Test("建議最低空間門檻為正數且至少容納一小時 PCM")
    func recommendedMinimumCoversOneHour() {
        // 規格書決議 10：48kHz 16-bit 單聲道約 350MB 一小時。
        #expect(DiskSpace.recommendedMinimumBytes >= 350_000_000)
    }
}
