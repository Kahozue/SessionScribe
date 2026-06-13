import AppKit
import Foundation
import Observation
import SSAudio
import SSCore
import SSTranscription
import UniformTypeIdentifiers

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
    public var infoMessage: String?
    public var micPermissionDenied = false
    /// 剛匯入、等使用者決定是否立即轉寫的 session。
    public var pendingTranscription: Session?
    /// 等待選擇匯出格式的 session；非 nil 時 UI 顯示匯出選項視窗。
    public var exportRequest: Session?

    /// 字幕浮層是否開啟（規格 1.2）：工具列鈕反覆點切換開關，字幕浮層關閉鈕同步歸零。
    public var floatingCaptionVisible = false

    public private(set) var inputDevices: [AudioInputDevice] = []
    public var selectedDeviceUID: String?

    /// 本場模式：邊錄音邊轉寫或純錄音（工具列模式選擇，跨啟動記憶）。
    public var transcribeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(transcribeEnabled, forKey: Self.transcribeEnabledKey)
        }
    }
    private static let transcribeEnabledKey = "transcribeEnabled"

    /// 側欄列表排序方式（跨啟動記憶）。
    public enum SessionSortOrder: String, CaseIterable, Identifiable, Sendable {
        case newestFirst
        case oldestFirst
        case titleAscending

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .newestFirst: "由新到舊"
            case .oldestFirst: "由舊到新"
            case .titleAscending: "依名稱"
            }
        }
    }

    public var sortOrder: SessionSortOrder {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        }
    }
    private static let sortOrderKey = "sessionSortOrder"

    /// 下一場要套用的模板 id（工具列選擇，跨啟動記憶）。
    public var selectedTemplateID: String {
        didSet {
            UserDefaults.standard.set(selectedTemplateID, forKey: Self.selectedTemplateKey)
        }
    }
    private static let selectedTemplateKey = "selectedTemplateID"

    public var availableTemplates: [SessionTemplate] { SessionTemplate.builtIns }

    /// 當前場次的模板；尚未建立場次時退回下一場選定的模板（供按鈕預覽）。
    public var activeTemplate: SessionTemplate {
        SessionTemplate.template(for: activeSession?.templateID ?? selectedTemplateID)
    }

    /// 即時標記按鈕要呈現的四個 markerType（依當前模板）。
    public var activeMarkerTypes: [MarkerType] {
        activeTemplate.markerTypes
    }

    public private(set) var transcript: [TranscriptSegment] = []
    public private(set) var volatileText: String?
    /// finalized 段落的譯文（規格 1.2 Phase 3），以 segmentID 對應。即時顯示不持久化。
    public private(set) var translations: [String: String] = [:]
    /// 辨識模型下載進度 0...1；非 nil 表示正在下載，UI 顯示進度條。下載完成或無需下載為 nil。
    public private(set) var modelDownloadProgress: Double?
    public private(set) var markers: [Marker] = []
    public private(set) var libraryConfig = LibraryConfig()

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
    private var translationCoordinator: TranslationCoordinator?
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
        transcribeEnabled =
            UserDefaults.standard.object(forKey: Self.transcribeEnabledKey) as? Bool ?? true
        sortOrder =
            SessionSortOrder(
                rawValue: UserDefaults.standard.string(forKey: Self.sortOrderKey) ?? ""
            ) ?? .newestFirst
        selectedTemplateID =
            UserDefaults.standard.string(forKey: Self.selectedTemplateKey)
            ?? SessionTemplate.builtIns[0].id
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
        } catch {
            errorMessage = "建立資料夾失敗：\(error.localizedDescription)"
        }
        // 以下每項各自降級：崩潰恢復與設定讀取的暫時性／單檔錯誤都不該打掉整個列表
        // （比照「損毀項目逐項略過、不阻斷列表」的原則）。
        if let recovered = try? library.recoverCrashedSessions() {
            for session in recovered {
                let audioDirectory = library.directory(for: session.sessionID)
                    .appending(path: SessionFiles.audioDirectory)
                _ = try? AudioManifestRecovery.rebuild(audioDirectory: audioDirectory)
            }
        }
        sessions = (try? library.sessions()) ?? sessions
        libraryConfig = (try? LibraryConfigFile.read(from: sessionsRoot)) ?? libraryConfig
        inputDevices = AudioInputDevices.available()
    }

    // MARK: - 分類與批次（規格 1.1 第 7 項）

    /// 依分類分組；隱藏分類的 session 不出現在側欄。
    public var visibleCategories: [SessionCategory] {
        libraryConfig.categories.filter { !$0.hidden }
    }

    public func sessions(in categoryID: String?) -> [Session] {
        applySort(sessions.filter { $0.categoryID == categoryID })
    }

    /// 未分類的 session；分類定義已不存在者也算未分類，不讓 session 憑空消失。
    public var uncategorizedSessions: [Session] {
        applySort(
            sessions.filter { session in
                guard let categoryID = session.categoryID else { return true }
                return !libraryConfig.categories.contains { $0.id == categoryID }
            })
    }

    private func applySort(_ list: [Session]) -> [Session] {
        switch sortOrder {
        case .newestFirst:
            list.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            list.sorted { $0.createdAt < $1.createdAt }
        case .titleAscending:
            list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// 重新命名（側欄或檢視頁點標題觸發），metadata 即時落盤。
    public func renameSession(_ sessionID: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try library.rename(sessionID: sessionID, to: trimmed)
            sessions = try library.sessions()
            if activeSession?.sessionID == sessionID {
                activeSession?.title = trimmed
            }
        } catch {
            errorMessage = "重新命名失敗：\(error.localizedDescription)"
        }
    }

    /// 從磁碟重讀列表（檢視頁改名等外部變更後同步側欄）。
    public func refreshSessions() {
        sessions = (try? library.sessions()) ?? sessions
    }

    public func addCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (libraryConfig.categories.map(\.order).max() ?? -1) + 1
        libraryConfig.categories.append(SessionCategory(name: trimmed, order: nextOrder))
        persistConfig()
    }

    public func renameCategory(id: String, to name: String) {
        guard let index = libraryConfig.categories.firstIndex(where: { $0.id == id }) else {
            return
        }
        libraryConfig.categories[index].name = name
        persistConfig()
    }

    public func toggleCategoryHidden(id: String) {
        guard let index = libraryConfig.categories.firstIndex(where: { $0.id == id }) else {
            return
        }
        libraryConfig.categories[index].hidden.toggle()
        persistConfig()
    }

    /// 刪除分類定義；其下 session 移回未分類。
    public func deleteCategory(id: String) {
        let affected = Set(sessions.filter { $0.categoryID == id }.map(\.sessionID))
        do {
            try library.assign(categoryID: nil, to: affected)
            libraryConfig.categories.removeAll { $0.id == id }
            persistConfig()
            sessions = try library.sessions()
        } catch {
            errorMessage = "刪除分類失敗：\(error.localizedDescription)"
        }
    }

    public func assignCategory(_ categoryID: String?, to sessionIDs: Set<String>) {
        do {
            try library.assign(categoryID: categoryID, to: sessionIDs)
            sessions = try library.sessions()
        } catch {
            errorMessage = "移動分類失敗：\(error.localizedDescription)"
        }
    }

    public func deleteSessions(_ sessionIDs: Set<String>) {
        for sessionID in sessionIDs {
            SessionPlayerCache.shared.remove(
                audioDirectory: library.directory(for: sessionID)
                    .appending(path: SessionFiles.audioDirectory))
        }
        do {
            try library.delete(sessionIDs: sessionIDs)
            sessions = try library.sessions()
            infoMessage = "已刪除 \(sessionIDs.count) 個 session（移至垃圾桶）。"
        } catch {
            errorMessage = "刪除失敗：\(error.localizedDescription)"
        }
    }

    private func persistConfig() {
        do {
            try LibraryConfigFile.write(libraryConfig, to: sessionsRoot)
        } catch {
            errorMessage = "儲存分類設定失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - 名詞表校正（v0.2）

    /// 新增校正規則（from→to）；空白 from 略過。規則於下一場轉寫生效。
    public func addLexiconRule(from: String, to: String) {
        let trimmedFrom = from.trimmingCharacters(in: .whitespaces)
        let trimmedTo = to.trimmingCharacters(in: .whitespaces)
        guard !trimmedFrom.isEmpty else { return }
        libraryConfig.lexicon.append(LexiconRule(from: trimmedFrom, to: trimmedTo))
        persistConfig()
    }

    public func removeLexiconRules(atOffsets offsets: IndexSet) {
        libraryConfig.lexicon.remove(atOffsets: offsets)
        persistConfig()
    }

    // MARK: - 自訂標記類型（v0.2）

    /// 模板四鍵之外的使用者自訂標記類型。
    public var customMarkerTypes: [MarkerType] { libraryConfig.markerTypes }

    /// 新增自訂標記類型；rawValue 與 label 皆需非空，rawValue 重複則略過。
    public func addMarkerType(rawValue: String, label: String) {
        let trimmedRaw = rawValue.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        guard !trimmedRaw.isEmpty, !trimmedLabel.isEmpty else { return }
        guard !libraryConfig.markerTypes.contains(where: { $0.rawValue == trimmedRaw }) else {
            return
        }
        libraryConfig.markerTypes.append(MarkerType(rawValue: trimmedRaw, label: trimmedLabel))
        persistConfig()
    }

    public func removeMarkerTypes(atOffsets offsets: IndexSet) {
        libraryConfig.markerTypes.remove(atOffsets: offsets)
        persistConfig()
    }

    // MARK: - 跨逐字稿搜尋（規格 1.1 第 9 項）

    public func search(_ query: String) -> [SearchHit] {
        (try? TranscriptSearchService(library: library).search(query)) ?? []
    }

    // MARK: - Session 控制

    /// 建立新 session、備妥錄音管線並依降級鏈選擇轉寫引擎。
    public func newSession() async {
        guard state != .recording && state != .paused else { return }
        await tearDownActiveSession()
        do {
            try checkDiskSpace()
            let deviceName = inputDevices.first { $0.id == selectedDeviceUID }?.name
            // 辨識語言（規格 1.2 Phase 3）：決定 SpeechTranscriber locale 與翻譯來源。
            let recognitionCode =
                UserDefaults.standard.string(forKey: DisplaySettings.recognitionLanguageKey)
                ?? CaptionLanguage.zhTW.code
            var session = Session(
                sessionID: Session.makeID(),
                title: Self.nextRecordingTitle(existing: sessions),
                templateID: selectedTemplateID,
                locale: recognitionCode,
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
            translations = [:]
            mediaSeconds = 0
            state = .idle

            // 引擎降級鏈：SpeechAnalyzer、SFSpeechRecognizer、純錄音。
            // 使用者選了純錄音模式時直接跳過引擎選擇。
            transcriptionState = .preparing
            let useMock = UserDefaults.standard.bool(forKey: DisplaySettings.useMockEngineKey)
            let preparedEngine: (any TranscriptionEngine)?
            if transcribeEnabled {
                modelDownloadProgress = 0
                preparedEngine = await EngineSelector.selectAndPrepare(
                    from: EngineSelector.defaultChain(useMock: useMock),
                    locale: Locale(identifier: session.locale),
                    progress: { fraction in
                        Task { @MainActor in
                            self.modelDownloadProgress = fraction < 1 ? fraction : nil
                        }
                    })
                modelDownloadProgress = nil
            } else {
                preparedEngine = nil
            }
            if let engine = preparedEngine {
                let coordinator = TranscriptionCoordinator(
                    engine: engine, store: store, lexicon: libraryConfig.lexicon)
                self.coordinator = coordinator
                await pipeline.attachTranscription(coordinator)
                session.asrEngine = engine.info.name
                try await store.saveMetadata(session)
                transcriptionState = .ready(engine.info.name)
                await setUpTranslation(recognitionCode: recognitionCode)
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

    /// 工具列單一錄音鈕的入口：沒有進行中的 session 就先建一個再開始。
    public func startRecording() async {
        if controller == nil || state == .stopped {
            await newSession()
        }
        await start()
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
        await translationCoordinator?.finish()
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
        MarkerTimeline.inlineMarkers(for: segment, markers: markers)
    }

    public func removeMarker(_ markerID: String) {
        guard let store else { return }
        let updated = markers.filter { $0.markerID != markerID }
        guard updated.count != markers.count else { return }
        Task {
            do {
                try await store.saveMarkers(updated)
                markers = updated
            } catch {
                errorMessage = "取消標記失敗：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 匯出

    /// 整場匯出入口：先跳匯出選項視窗選格式，確認後才選目的資料夾。
    public func export(session: Session) {
        exportRequest = session
    }

    public func exportActiveSession() {
        guard let activeSession else { return }
        export(session: activeSession)
    }

    /// 匯出選項確認後執行：使用者選資料夾，依勾選格式寫出。
    public func performExport(session: Session, formats: Set<ExportFormat>) {
        guard !formats.isEmpty else { return }
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
                    to: destination.appending(path: "\(session.sessionID)_export"),
                    formats: formats)
                infoMessage = "匯出完成：\(session.sessionID)_export"
            } catch {
                errorMessage = "匯出失敗：\(error.localizedDescription)"
            }
        }
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
            infoMessage = "已匯出 \(chosen.count) 個選取段落"
        } catch {
            errorMessage = "匯出失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - 匯入（規格 1.1 第 6 項）

    /// 選擇音檔匯入為 imported session；完成後詢問是否立即轉寫。
    public func importAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = AudioImporter.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "匯入"
        panel.message = "選擇要匯入的音訊檔"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let session = try await AudioImporter.importFile(
                    at: url, into: sessionsRoot, appVersion: Self.appVersion)
                sessions = try library.sessions()
                pendingTranscription = session
            } catch {
                errorMessage = "匯入失敗：\(error.localizedDescription)"
            }
        }
    }

    /// 對匯入的 session 做離線轉寫（背景執行，完成後提示）。
    public func transcribeImported(_ session: Session) {
        Task {
            let store = SessionStore(directory: library.directory(for: session.sessionID))
            let useMock = UserDefaults.standard.bool(forKey: DisplaySettings.useMockEngineKey)
            guard
                let engine = await EngineSelector.selectAndPrepare(
                    from: EngineSelector.defaultChain(useMock: useMock),
                    locale: Locale(identifier: session.locale))
            else {
                errorMessage = "沒有可用的轉寫引擎。"
                return
            }
            let coordinator = TranscriptionCoordinator(
                engine: engine, store: store, lexicon: libraryConfig.lexicon)
            do {
                try await OfflineTranscriber.transcribe(
                    sessionDirectory: store.directory, session: session,
                    coordinator: coordinator)
                let count = (try? await store.loadSegments())?.count ?? 0
                infoMessage = "離線轉寫完成：\(session.title)，共 \(count) 段。"
            } catch {
                errorMessage = "離線轉寫失敗：\(error.localizedDescription)"
            }
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
        translationCoordinator = nil
        markerService = nil
        store = nil
        modelDownloadProgress = nil
        transcriptionState = .none
    }

    /// 設定頁的預先下載：對目前選定的辨識語言下載／備妥模型，回報進度。
    /// 先下好，正式錄音時模型即就緒、不必等。
    public func downloadRecognitionModel() {
        let code =
            UserDefaults.standard.string(forKey: DisplaySettings.recognitionLanguageKey)
            ?? CaptionLanguage.zhTW.code
        guard modelDownloadProgress == nil else { return }
        Task {
            modelDownloadProgress = 0
            let engine = AppleSpeechEngine()
            do {
                try await engine.prepare(
                    locale: Locale(identifier: code),
                    progress: { fraction in
                        Task { @MainActor in
                            self.modelDownloadProgress = fraction < 1 ? fraction : nil
                        }
                    })
                infoMessage = "\(CaptionLanguage.from(code: code).displayName)辨識模型已就緒。"
            } catch {
                errorMessage = "下載辨識模型失敗：\(error.localizedDescription)"
            }
            modelDownloadProgress = nil
        }
    }

    private func subscribeTranscription(_ coordinator: TranscriptionCoordinator) async {
        let finalized = await coordinator.finalizedUpdates()
        let volatiles = await coordinator.volatileUpdates()
        transcriptTasks.append(
            Task {
                for await segment in finalized {
                    self.transcript.append(segment)
                    // 翻譯（規格 1.2 Phase 3）：派獨立 Task，譯文延後到達不卡逐字稿。
                    if let translationCoordinator = self.translationCoordinator {
                        let id = segment.segmentID
                        let text = segment.text
                        Task { await translationCoordinator.translate(segmentID: id, text: text) }
                    }
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

    /// 備妥本場即時翻譯（規格 1.2 Phase 3）：翻譯關閉、來源＝目標、或非 26.4 皆略過。
    /// prepare（含必要時下載模型）在錄音前完成；失敗則本場僅顯示原文，不影響轉寫錄音。
    private func setUpTranslation(recognitionCode: String) async {
        translationCoordinator = nil
        guard UserDefaults.standard.bool(forKey: DisplaySettings.translationEnabledKey) else {
            return
        }
        let targetCode =
            UserDefaults.standard.string(forKey: DisplaySettings.translationTargetKey)
            ?? CaptionLanguage.zhTW.code
        guard targetCode != recognitionCode else { return }
        guard #available(macOS 26.4, *) else {
            infoMessage = "即時翻譯需要 macOS 26.4 以上，本場僅顯示原文。"
            return
        }
        let coordinator = TranslationCoordinator(translator: AppleTranslator())
        translationCoordinator = coordinator
        let updates = await coordinator.updates()
        transcriptTasks.append(
            Task {
                for await translated in updates {
                    self.translations[translated.segmentID] = translated.text
                }
            })
        // 模型準備（含必要時下載）在背景進行，絕不卡錄音啟動；就緒前的段落不翻譯。
        infoMessage = "翻譯模型準備中，就緒後譯文才會出現。"
        let source = CaptionLanguage.from(code: recognitionCode).language
        let target = CaptionLanguage.from(code: targetCode).language
        transcriptTasks.append(
            Task {
                await coordinator.prepare(source: source, target: target)
                if await coordinator.preparationFailed {
                    self.infoMessage = "翻譯模型未就緒，本場僅顯示原文。"
                }
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

    /// 字幕浮層的兩行滾動字幕（規格 1.2）。
    public var captionLines: CaptionLines {
        CaptionLines.derive(
            transcript: transcript, volatileText: volatileText, translations: translations)
    }

    /// 某段 finalized 的譯文（規格 1.2 Phase 3），主視窗列表內嵌顯示用。
    public func translation(for segmentID: String) -> String? {
        translations[segmentID]
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

    /// 「新錄音1、新錄音2…」遞增命名：取既有同模式標題的最大編號加一。
    static func nextRecordingTitle(existing sessions: [Session]) -> String {
        let numbers = sessions.compactMap { session -> Int? in
            guard let match = session.title.wholeMatch(of: /新錄音(\d+)/) else { return nil }
            return Int(match.1)
        }
        return "新錄音\((numbers.max() ?? 0) + 1)"
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
