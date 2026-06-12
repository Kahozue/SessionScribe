import AppKit
import Foundation
import Observation
import SSAudio
import SSCore
import SSTranscription

/// 錄音與轉寫流程的 view model：持有 SessionController、LiveRecordingPipeline、
/// TranscriptionCoordinator 與 MarkerService，把狀態、逐字稿、標記、音量
/// 發佈給 UI。所有錯誤以文字呈現，不讓 UI 崩潰。
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
    public var exportMessage: String?
    public var micPermissionDenied = false

    public private(set) var inputDevices: [AudioInputDevice] = []
    public var selectedDeviceUID: String?

    public private(set) var transcript: [TranscriptSegment] = []
    public private(set) var volatileText: String?
    public private(set) var markers: [Marker] = []

    public enum TranscriptionState: Equatable {
        case none
        case preparing
        case ready(String)
        case active(String)
        case recordingOnly
        case failed
    }
    public private(set) var transcriptionState: TranscriptionState = .none

    // MARK: - 內部

    private var controller: SessionController?
    private var pipeline: LiveRecordingPipeline?
    private var coordinator: TranscriptionCoordinator?
    private var markerService: MarkerService?
    private var store: SessionStore?
    private var levelTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var transcriptTasks: [Task<Void, Never>] = []
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

    /// 建立新 session、備妥錄音管線並依降級鏈選擇轉寫引擎。
    public func newSession() async {
        guard state != .recording && state != .paused else { return }
        await tearDownActiveSession()
        do {
            try checkDiskSpace()
            let deviceName = inputDevices.first { $0.id == selectedDeviceUID }?.name
            var session = Session(
                sessionID: Session.makeID(),
                title: "新場次 \(Self.titleDateFormatter.string(from: Date()))",
                templateID: "thesis_defense",
                locale: "zh-TW",
                audioInput: deviceName ?? "系統預設輸入",
                appVersion: Self.appVersion
            )
            let store = try await SessionStore.create(session, in: sessionsRoot)
            self.store = store
            let pipeline = LiveRecordingPipeline(
                audioDirectory: store.directory.appending(path: SessionFiles.audioDirectory),
                deviceUID: selectedDeviceUID)
            self.pipeline = pipeline
            markerService = MarkerService(store: store, sessionID: session.sessionID)
            transcript = []
            markers = []
            volatileText = nil
            mediaSeconds = 0
            state = .idle

            // 引擎降級鏈：SpeechAnalyzer、SFSpeechRecognizer、純錄音。
            transcriptionState = .preparing
            let useMock = UserDefaults.standard.bool(forKey: DisplaySettings.useMockEngineKey)
            if let engine = await EngineSelector.selectAndPrepare(
                from: EngineSelector.defaultChain(useMock: useMock),
                locale: Locale(identifier: session.locale))
            {
                let coordinator = TranscriptionCoordinator(engine: engine, store: store)
                self.coordinator = coordinator
                await pipeline.attachTranscription(coordinator)
                session.asrEngine = engine.info.name
                try await store.saveMetadata(session)
                transcriptionState = .ready(engine.info.name)
            } else {
                coordinator = nil
                transcriptionState = .recordingOnly
            }

            controller = SessionController(
                session: session, store: store, pipeline: pipeline,
                sleepInhibitor: SleepInhibitor())
            activeSession = session
            subscribeLevels(of: pipeline)
            sessions = try library.sessions()
        } catch {
            errorMessage = "建立 session 失敗：\(error.localizedDescription)"
        }
    }

    public func start() async {
        guard let controller else { return }
        // 先啟動轉寫；失敗即轉純錄音，不阻擋錄音（核心原則 2）。
        if let coordinator, let session = activeSession {
            await subscribeTranscription(coordinator)
            do {
                try await coordinator.start(
                    sessionID: session.sessionID,
                    locale: Locale(identifier: session.locale))
                transcriptionState = .active(coordinator.engineInfo.name)
            } catch {
                self.coordinator = nil
                await pipeline?.attachTranscription(nil)
                transcriptionState = .failed
            }
        }
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
        volatileText = nil
        if case .active = transcriptionState {
            transcriptionState = .none
        }
        sessions = (try? library.sessions()) ?? sessions
    }

    // MARK: - 標記

    /// 按鍵或按鈕觸發：對齊當前媒體時間，立即落盤，零確認步驟。
    public func addMarker(_ type: MarkerType) {
        guard state == .recording || state == .paused,
            let markerService, let controller
        else { return }
        Task {
            do {
                let seconds = await controller.mediaSeconds
                let marker = try await markerService.addMarker(
                    type: type, mediaSeconds: seconds, segments: transcript)
                markers.append(marker)
            } catch {
                errorMessage = "標記寫入失敗：\(error.localizedDescription)"
            }
        }
    }

    /// segment 時間範圍內的 markers，逐字稿列表內嵌顯示用。
    public func inlineMarkers(for segment: TranscriptSegment) -> [Marker] {
        markers.filter {
            $0.mediaSeconds >= segment.startSeconds && $0.mediaSeconds < segment.endSeconds
        }
    }

    // MARK: - 匯出

    /// 整場匯出：使用者選資料夾，寫出 transcript.md、markers.csv、session.json 與 jsonl 副本。
    public func export(session: Session) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "匯出到此資料夾"
        panel.message = "選擇 \(session.title) 的匯出目的地"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let store = SessionStore(directory: library.directory(for: session.sessionID))
        Task {
            do {
                try await ExportService.export(
                    store: store, session: session,
                    to: destination.appending(path: "\(session.sessionID)_export"))
                exportMessage = "匯出完成：\(session.sessionID)_export"
            } catch {
                errorMessage = "匯出失敗：\(error.localizedDescription)"
            }
        }
    }

    public func exportActiveSession() {
        guard let activeSession else { return }
        export(session: activeSession)
    }

    /// 選取匯出：把選取的 segments 與時間範圍內的 markers 匯出為單一 Markdown。
    public func exportSelection(_ segmentIDs: Set<String>) {
        guard let session = activeSession, !segmentIDs.isEmpty else { return }
        let chosen = transcript
            .filter { segmentIDs.contains($0.segmentID) }
            .sorted { $0.startSeconds < $1.startSeconds }
        guard let first = chosen.first, let last = chosen.last else { return }
        let related = markers.filter {
            $0.mediaSeconds >= first.startSeconds && $0.mediaSeconds <= last.endSeconds
        }
        let markdown = MarkdownExporter.transcript(
            session: session, segments: chosen, markers: related)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.sessionID)_選取段落.md"
        panel.prompt = "匯出"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(markdown.utf8).write(to: url, options: .atomic)
            exportMessage = "已匯出 \(chosen.count) 個選取段落"
        } catch {
            errorMessage = "匯出失敗：\(error.localizedDescription)"
        }
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
        for task in transcriptTasks {
            task.cancel()
        }
        transcriptTasks = []
        controller = nil
        pipeline = nil
        coordinator = nil
        markerService = nil
        store = nil
        transcriptionState = .none
    }

    private func subscribeTranscription(_ coordinator: TranscriptionCoordinator) async {
        let finalized = await coordinator.finalizedUpdates()
        let volatiles = await coordinator.volatileUpdates()
        transcriptTasks.append(
            Task {
                for await segment in finalized {
                    self.transcript.append(segment)
                }
                // 流在仍錄音時終止代表引擎中途死亡；錄音不受影響。
                if self.state == .recording || self.state == .paused {
                    self.transcriptionState = .failed
                }
            })
        transcriptTasks.append(
            Task {
                for await update in volatiles {
                    self.volatileText = update.text
                }
                self.volatileText = nil
            })
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
        TimeFormatting.hms(mediaSeconds)
    }

    public var stateDescription: (text: String, systemImage: String) {
        switch state {
        case .idle: ("未錄音", "mic.slash")
        case .recording: ("錄音中", "record.circle.fill")
        case .paused: ("已暫停", "pause.circle.fill")
        case .stopped: ("已停止", "stop.circle.fill")
        }
    }

    public var transcriptionDescription: (text: String, systemImage: String)? {
        switch transcriptionState {
        case .none: nil
        case .preparing: ("準備引擎中", "hourglass")
        case .ready(let name): ("引擎：\(name)", "waveform.badge.mic")
        case .active(let name): ("轉寫中：\(name)", "waveform.badge.mic")
        case .recordingOnly: ("純錄音模式", "mic")
        case .failed: ("轉寫錯誤，錄音持續", "exclamationmark.triangle")
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
