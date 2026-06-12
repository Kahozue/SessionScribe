import Foundation

/// 錄音狀態。UI 的狀態徽章與按鈕可用性直接對應這個值。
public enum RecordingState: String, Equatable, Sendable {
    case idle
    case recording
    case paused
    case stopped
}

/// 錄音管線抽象：SSCore 透過此 protocol 操作音訊層，
/// SSAudio 提供實機實作，測試使用假管線。
public protocol RecordingPipeline: Sendable {
    func start() async throws
    func pause() async throws
    func resume() async throws
    /// 收尾當前 chunk 並完成 manifest 索引。
    func stop() async throws
    /// 目前媒體時間（秒，不含暫停）。
    var mediaSeconds: Double { get async }
}

/// 防睡眠 assertion 抽象（規格書決議 7）。
public protocol SleepInhibiting: Sendable {
    func begin(reason: String)
    func end()
}

/// 單場 session 的錄音流程協調者：強制狀態機轉換合法性、
/// 維護 metadata 的 startedAt 與 endedAt、控制防睡眠 assertion。
public actor SessionController {

    public enum ControllerError: Error, Equatable {
        case invalidTransition(from: RecordingState, action: String)
    }

    public private(set) var state: RecordingState = .idle
    private var session: Session
    private let store: SessionStore
    private let pipeline: any RecordingPipeline
    private let sleepInhibitor: any SleepInhibiting
    private let now: @Sendable () -> Date

    public init(
        session: Session,
        store: SessionStore,
        pipeline: any RecordingPipeline,
        sleepInhibitor: any SleepInhibiting,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.store = store
        self.pipeline = pipeline
        self.sleepInhibitor = sleepInhibitor
        self.now = now
    }

    public var currentSession: Session { session }

    public var mediaSeconds: Double {
        get async { await pipeline.mediaSeconds }
    }

    /// idle 轉 recording。管線啟動失敗時維持 idle 並釋放防睡眠，可重試。
    public func start() async throws {
        guard state == .idle else {
            throw ControllerError.invalidTransition(from: state, action: "start")
        }
        sleepInhibitor.begin(reason: "SessionScribe 錄音中")
        do {
            try await pipeline.start()
        } catch {
            sleepInhibitor.end()
            throw error
        }
        session.startedAt = now()
        try await store.saveMetadata(session)
        state = .recording
    }

    public func pause() async throws {
        guard state == .recording else {
            throw ControllerError.invalidTransition(from: state, action: "pause")
        }
        try await pipeline.pause()
        state = .paused
    }

    public func resume() async throws {
        guard state == .paused else {
            throw ControllerError.invalidTransition(from: state, action: "resume")
        }
        try await pipeline.resume()
        state = .recording
    }

    /// recording 或 paused 轉 stopped（終態）。
    /// 管線收尾失敗時仍進入 stopped 並釋放防睡眠，但 endedAt 不落盤：
    /// metadata 保持 ended_at == null，下次啟動的恢復掃描會接手重建索引。
    public func stop() async throws {
        guard state == .recording || state == .paused else {
            throw ControllerError.invalidTransition(from: state, action: "stop")
        }
        state = .stopped
        defer { sleepInhibitor.end() }
        try await pipeline.stop()
        session.endedAt = now()
        try await store.saveMetadata(session)
    }
}
