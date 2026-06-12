import Foundation
import Observation
import SSAudio
import SSCore

/// 錄音流程的 view model：持有 SessionController 與 LiveRecordingPipeline，
/// 將狀態、媒體時間與音量發佈給 UI。所有錯誤以文字呈現，不讓 UI 崩潰。
@MainActor
@Observable
public final class RecordingViewModel {

    // MARK: - 發佈狀態

    public private(set) var sessions: [Session] = []
    public private(set) var activeSession: Session?
    public private(set) var state: RecordingState = .idle
    public private(set) var mediaSeconds: Double = 0
    public private(set) var level: AudioLevel = .silent
    public var errorMessage: String?
    public var diskSpaceWarning: String?
    public var micPermissionDenied = false

    public private(set) var inputDevices: [AudioInputDevice] = []
    public var selectedDeviceUID: String?

    // MARK: - 內部

    private var controller: SessionController?
    private var pipeline: LiveRecordingPipeline?
    private var levelTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private let library: SessionLibrary
    public let sessionsRoot: URL

    public init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultSessionsRoot()
        sessionsRoot = root
        library = SessionLibrary(rootDirectory: root)
    }

    /// app container 內的 Application Support/SessionScribe/Sessions。
    private static func defaultSessionsRoot() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "SessionScribe").appending(path: "Sessions")
    }

    // MARK: - 啟動

    /// App 啟動：建立根目錄、跑崩潰恢復掃描（含 audio 索引重建）、載入列表。
    public func onLaunch() async {
        do {
            try FileManager.default.createDirectory(
                at: sessionsRoot, withIntermediateDirectories: true)
            let recovered = try library.recoverCrashedSessions()
            for session in recovered {
                let audioDirectory = library.directory(for: session.sessionID)
                    .appending(path: SessionFiles.audioDirectory)
                _ = try? AudioManifestRecovery.rebuild(audioDirectory: audioDirectory)
            }
            sessions = try library.sessions()
        } catch {
            errorMessage = "載入 session 列表失敗：\(error.localizedDescription)"
        }
        inputDevices = AudioInputDevices.available()
    }

    // MARK: - Session 控制

    /// 建立新 session 並備妥錄音管線。錄音中不可建立。
    public func newSession() async {
        guard state != .recording && state != .paused else { return }
        await tearDownActiveSession()
        do {
            try checkDiskSpace()
            let deviceName = inputDevices.first { $0.id == selectedDeviceUID }?.name
            let session = Session(
                sessionID: Session.makeID(),
                title: "新場次 \(Self.titleDateFormatter.string(from: Date()))",
                templateID: "thesis_defense",
                locale: "zh-TW",
                audioInput: deviceName ?? "系統預設輸入",
                appVersion: Self.appVersion
            )
            let store = try await SessionStore.create(session, in: sessionsRoot)
            let pipeline = LiveRecordingPipeline(
                audioDirectory: store.directory.appending(path: SessionFiles.audioDirectory),
                deviceUID: selectedDeviceUID)
            self.pipeline = pipeline
            controller = SessionController(
                session: session, store: store, pipeline: pipeline,
                sleepInhibitor: SleepInhibitor())
            activeSession = session
            state = .idle
            mediaSeconds = 0
            subscribeLevels(of: pipeline)
            sessions = try library.sessions()
        } catch {
            errorMessage = "建立 session 失敗：\(error.localizedDescription)"
        }
    }

    public func start() async {
        guard let controller else { return }
        do {
            try await controller.start()
            state = await controller.state
            startClockPolling()
        } catch is MicrophonePermission.PermissionError {
            micPermissionDenied = true
        } catch {
            errorMessage = "開始錄音失敗：\(error.localizedDescription)"
        }
    }

    public func pause() async {
        guard let controller else { return }
        do {
            try await controller.pause()
            state = await controller.state
        } catch {
            errorMessage = "暫停失敗：\(error.localizedDescription)"
        }
    }

    public func resume() async {
        guard let controller else { return }
        do {
            try await controller.resume()
            state = await controller.state
        } catch {
            errorMessage = "繼續錄音失敗：\(error.localizedDescription)"
        }
    }

    public func stop() async {
        guard let controller else { return }
        do {
            try await controller.stop()
        } catch {
            errorMessage = "停止時發生錯誤，錄音資料已保存，下次啟動會自動恢復索引：\(error.localizedDescription)"
        }
        state = await controller.state
        stopClockPolling()
        level = .silent
        sessions = (try? library.sessions()) ?? sessions
    }

    /// 在 Finder 顯示 session 資料夾（規格書決議 8 的可發現性要求）。
    public func directory(for session: Session) -> URL {
        library.directory(for: session.sessionID)
    }

    // MARK: - 私有

    private func tearDownActiveSession() async {
        if state == .recording || state == .paused {
            await stop()
        }
        stopClockPolling()
        levelTask?.cancel()
        levelTask = nil
        controller = nil
        pipeline = nil
    }

    private func checkDiskSpace() throws {
        if try DiskSpace.isBelowRecommendedMinimum(at: sessionsRoot) {
            let available = try DiskSpace.availableBytes(at: sessionsRoot)
            let formatter = ByteCountFormatter()
            diskSpaceWarning =
                "磁碟可用空間僅 \(formatter.string(fromByteCount: available))，"
                + "錄音約需每小時 350MB，請先清出空間。仍可繼續，但有中斷風險。"
        }
    }

    private func subscribeLevels(of pipeline: LiveRecordingPipeline) {
        levelTask?.cancel()
        levelTask = Task {
            let updates = await pipeline.levelUpdates()
            for await level in updates {
                self.level = level
            }
            self.level = .silent
        }
    }

    private func startClockPolling() {
        guard clockTask == nil else { return }
        clockTask = Task {
            while !Task.isCancelled {
                if let controller = self.controller {
                    self.mediaSeconds = await controller.mediaSeconds
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopClockPolling() {
        clockTask?.cancel()
        clockTask = nil
    }

    // MARK: - 顯示輔助

    public var formattedDuration: String {
        let total = Int(mediaSeconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    public var stateDescription: (text: String, systemImage: String) {
        switch state {
        case .idle: ("未錄音", "mic.slash")
        case .recording: ("錄音中", "record.circle.fill")
        case .paused: ("已暫停", "pause.circle.fill")
        case .stopped: ("已停止", "stop.circle.fill")
        }
    }

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
