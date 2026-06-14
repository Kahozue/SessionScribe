import AppKit
import SSAudio
import SSCore
import SSTranscription
import SwiftUI

/// 錄音檢視頁的 view model：載入 metadata、segments、markers，
/// 透過 SessionPlayerCache 共用播放器（切換 session 進度不歸零），
/// 並推導歌詞式定位的當前 segment。
@MainActor
@Observable
final class SessionDetailViewModel {
    private(set) var session: Session?
    private(set) var segments: [TranscriptSegment] = []
    private(set) var markers: [Marker] = []
    private(set) var summary: TranscriptSummary?
    private(set) var events: [StructuredEvent] = []
    private(set) var player: SessionPlayer?
    var errorMessage: String?
    private(set) var transcribing = false
    private(set) var transcribeProgress = 0.0
    private(set) var summarizing = false
    private(set) var organizing = false
    private(set) var organizeProgress = 0.0

    let directory: URL
    private let store: SessionStore

    init(directory: URL) {
        self.directory = directory
        self.store = SessionStore(directory: directory)
    }

    // MARK: 整理/摘要引擎路由（本機 vs 雲端，v0.3 Text Cloud Assist）

    private var cloudSettings: CloudLLMSettings { CloudLLMSettings.load() }
    private let keychain: KeychainStore = SystemKeychainStore()

    private var resolvedOrganizer: EventOrganizing {
        AssistResolver.eventOrganizer(settings: cloudSettings, keychain: keychain)
    }
    private var resolvedSummarizer: TranscriptSummarizing {
        AssistResolver.summarizer(settings: cloudSettings, keychain: keychain)
    }

    /// 目前生效的引擎是否為雲端（需總開關開、引擎=雲端、供應商與 key 齊備）。
    var usingCloudAssist: Bool {
        AssistResolver.client(settings: cloudSettings, keychain: keychain) != nil
    }

    func load() async {
        do {
            session = try await store.loadMetadata()
            segments = try await store.loadSegments()
            markers = try await store.loadMarkers()
            summary = (try TranscriptSummaryFile.readIfPresent(from: directory))?.summary
            events = (try EventsFile.readIfPresent(from: directory))?.events ?? []
            player = try? SessionPlayerCache.shared.player(
                for: directory.appending(path: SessionFiles.audioDirectory))
        } catch {
            errorMessage = "載入 session 失敗：\(error.localizedDescription)"
        }
    }

    var sessionTemplate: SessionTemplate {
        SessionTemplate.template(for: session?.templateID ?? SessionTemplate.builtIns[0].id)
    }

    var markersByID: [String: Marker] {
        Dictionary(uniqueKeysWithValues: markers.map { ($0.markerID, $0) })
    }

    func inlineMarkers(for segment: TranscriptSegment) -> [Marker] {
        MarkerTimeline.inlineMarkers(for: segment, markers: markers)
    }

    /// 由 markers 與前後文 segments 生成事件草稿並落盤（覆寫既有 events.json）。
    func generateDrafts() {
        guard let session else { return }
        events = EventDraftBuilder.drafts(
            markers: markers, segments: segments, sessionID: session.sessionID)
        persistEvents()
    }

    /// 編輯後寫回；來源欄位由呼叫端保留不動。
    func updateEvent(_ event: StructuredEvent) {
        guard let index = events.firstIndex(where: { $0.eventID == event.eventID }) else { return }
        events[index] = event
        persistEvents()
    }

    private func persistEvents() {
        do {
            try EventsFile.write(EventsDocument(events: events), to: directory)
        } catch {
            errorMessage = "儲存事件草稿失敗：\(error.localizedDescription)"
        }
    }

    private func persistSummary() {
        guard let summary else { return }
        do {
            try TranscriptSummaryFile.write(
                TranscriptSummaryDocument(summary: summary), to: directory)
        } catch {
            errorMessage = "儲存摘要失敗：\(error.localizedDescription)"
        }
    }

    func removeMarker(_ markerID: String) {
        let updatedMarkers = markers.filter { $0.markerID != markerID }
        guard updatedMarkers.count != markers.count else { return }
        Task {
            do {
                try await store.saveMarkers(updatedMarkers)
                markers = updatedMarkers
                let updatedEvents = events.map { event in
                    var cleaned = event
                    cleaned.sourceMarkerIDs.removeAll { $0 == markerID }
                    return cleaned
                }
                if updatedEvents != events {
                    events = updatedEvents
                    persistEvents()
                }
            } catch {
                errorMessage = "取消標記失敗：\(error.localizedDescription)"
            }
        }
    }

    /// 本機模型不可用時的原因（裝置不符、未開 Apple Intelligence、模型未就緒）；可用為 nil。
    var organizeAvailabilityMessage: String? {
        EventOrganizer.availabilityMessage()
    }

    var summaryAvailabilityMessage: String? {
        TranscriptSummarizer.availabilityMessage()
    }

    /// 對整份 finalized 逐字稿產生摘要；輸出為 transcript_summary.json。
    func generateSummaryWithAI() {
        guard let session, !segments.isEmpty, !summarizing else { return }
        summarizing = true
        let segs = segments
        let sessionID = session.sessionID
        let locale = Locale(identifier: session.locale)
        Task {
            defer { summarizing = false }
            do {
                summary = try await resolvedSummarizer.summarize(
                    from: segs, sessionID: sessionID, locale: locale)
                persistSummary()
                await markTextCloudAssistIfNeeded()
            } catch {
                errorMessage = "AI 產生摘要失敗：\(error.localizedDescription)"
            }
        }
    }

    /// 魔杖入口：已有草稿就整理（補語意欄位），沒有草稿就直接從逐字稿生成。
    /// 與「依標記彙整」解耦：沒有標記、只有逐字稿時也能直接用。
    func runAIOrganize() {
        if events.isEmpty {
            generateEventsWithAI()
        } else {
            organizeEvents()
        }
    }

    /// 用本機 LLM 整理現有事件草稿的語意欄位；保留來源與 needs_review。
    func organizeEvents() {
        guard let session, !events.isEmpty, !organizing else { return }
        organizing = true
        organizeProgress = 0
        let current = events
        let locale = Locale(identifier: session.locale)
        Task {
            defer { organizing = false }
            do {
                let organizer = resolvedOrganizer
                let organized = try await organizer.organize(current, locale: locale) { progress in
                    Task { @MainActor in self.organizeProgress = progress }
                }
                events = organized
                persistEvents()
                await markTextCloudAssistIfNeeded()
            } catch {
                errorMessage = "AI 整理失敗：\(error.localizedDescription)"
            }
        }
    }

    /// 無標記時的 AI 路徑：直接讀逐字稿生成事件草稿並落盤。
    func generateEventsWithAI() {
        guard let session, !segments.isEmpty, !organizing else { return }
        organizing = true
        organizeProgress = 0
        let segs = segments
        let sessionID = session.sessionID
        let locale = Locale(identifier: session.locale)
        Task {
            defer { organizing = false }
            do {
                events = try await resolvedOrganizer.generateEvents(
                    from: segs, sessionID: sessionID, locale: locale)
                persistEvents()
                await markTextCloudAssistIfNeeded()
            } catch {
                errorMessage = "AI 產生草稿失敗：\(error.localizedDescription)"
            }
        }
    }

    /// 魔杖可按的條件：引擎可用（雲端生效或本機模型可用），且有逐字稿可生成或已有草稿可整理。
    var canRunAI: Bool {
        (usingCloudAssist || organizeAvailabilityMessage == nil)
            && (!segments.isEmpty || !events.isEmpty)
    }

    var canGenerateSummary: Bool {
        (usingCloudAssist || summaryAvailabilityMessage == nil) && !segments.isEmpty
    }

    /// 跑雲端整理/摘要成功後，如實把該 session 的 privacyMode 記為 textCloudAssist。
    private func markTextCloudAssistIfNeeded() async {
        guard usingCloudAssist, var current = session,
              current.privacyMode != .textCloudAssist else { return }
        current.privacyMode = .textCloudAssist
        do {
            try await store.saveMetadata(current)
            session = current
        } catch {
            errorMessage = "更新隱私模式失敗：\(error.localizedDescription)"
        }
    }

    /// 點標題改名：metadata 即時落盤。
    func rename(to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard var updated = session, !trimmed.isEmpty, trimmed != updated.title else { return }
        updated.title = trimmed
        session = updated
        Task {
            do {
                try await store.saveMetadata(updated)
            } catch {
                errorMessage = "重新命名失敗：\(error.localizedDescription)"
            }
        }
    }

    /// 歌詞式定位：播放時間落在哪個 segment（取最後一個已開始的）。
    var currentSegmentID: String? {
        guard let player, !segments.isEmpty else { return nil }
        let time = player.currentSeconds
        return segments.last { $0.startSeconds <= time }?.segmentID
    }

    /// 對既有音訊離線轉寫（匯入的 session 或純錄音場次）。
    /// reset=true 為重新轉錄：先清空既有逐字稿再轉，避免附加重複。
    func transcribe(reset: Bool = false) async {
        guard let session, !transcribing else { return }
        transcribing = true
        transcribeProgress = 0
        defer { transcribing = false }
        if reset {
            do {
                try await store.resetSegments()
                segments = []
            } catch {
                errorMessage = "清空舊逐字稿失敗：\(error.localizedDescription)"
                return
            }
        }
        let useMock = UserDefaults.standard.bool(forKey: DisplaySettings.useMockEngineKey)
        guard
            let engine = await EngineSelector.selectAndPrepare(
                from: EngineSelector.defaultChain(useMock: useMock),
                locale: Locale(identifier: session.locale))
        else {
            errorMessage = "沒有可用的轉寫引擎。"
            return
        }
        // 名詞表存於 sessions 根目錄（本 session 目錄的上層）的 library.json。
        let config = (try? LibraryConfigFile.read(from: directory.deletingLastPathComponent()))
            ?? LibraryConfig()
        let coordinator = TranscriptionCoordinator(
            engine: engine, store: store, lexicon: config.lexicon)
        do {
            try await OfflineTranscriber.transcribe(
                sessionDirectory: directory, session: session, coordinator: coordinator
            ) { progress in
                Task { @MainActor in self.transcribeProgress = progress }
            }
            segments = try await store.loadSegments()
        } catch {
            errorMessage = "轉寫失敗：\(error.localizedDescription)"
        }
    }
}

/// 錄音檢視頁（規格 1.1 第 5、10 項）：metadata、chunk 串接播放、
/// 進度條、倍速、歌詞模式與列表模式雙顯示。
enum SummaryBadgePolicy {
    static func showsReviewBadge(for _: TranscriptSummary?) -> Bool {
        false
    }
}

public struct SessionDetailView: View {
    @State private var model: SessionDetailViewModel
    /// 搜尋跳轉時要定位的 segment。
    let highlightSegmentID: String?
    /// 右欄（事件標記與後續擴充）收合狀態，與主視窗工具列的切換鈕共用。
    @Binding var showInspector: Bool
    /// 改名後通知外層（側欄列表同步）。
    let onRename: (() -> Void)?

    /// 搜尋跳轉的高亮：定位後短暫顯示再淡出（規格 1.1 第 9 項回饋修正）。
    @State private var activeHighlightID: String?
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var editingEvent: StructuredEvent?
    @State private var summaryExpanded = true
    @State private var eventsExpanded = true
    @State private var markersExpanded = true
    @State private var showReTranscribeConfirm = false
    @FocusState private var titleFieldFocused: Bool
    @AppStorage(DisplaySettings.transcriptModeKey)
    private var transcriptMode = DisplaySettings.lyricsMode

    private static let playbackRates: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    public init(
        directory: URL,
        highlightSegmentID: String? = nil,
        showInspector: Binding<Bool> = .constant(true),
        onRename: (() -> Void)? = nil
    ) {
        _model = State(initialValue: SessionDetailViewModel(directory: directory))
        self.highlightSegmentID = highlightSegmentID
        self._showInspector = showInspector
        self.onRename = onRename
    }

    public var body: some View {
        content
            .inspector(isPresented: $showInspector) {
                detailInspector
            }
            .appTypography()
    }

    private var content: some View {
        VStack(spacing: 0) {
            if let session = model.session {
                header(session)
                Divider()
                playbackBar
                Divider()
                if model.segments.isEmpty {
                    emptyTranscriptArea
                } else if transcriptMode == DisplaySettings.listMode {
                    PlainTranscriptView(
                        segments: model.segments,
                        markers: model.markers,
                        markerTemplate: model.sessionTemplate,
                        currentSegmentID: model.currentSegmentID,
                        highlightSegmentID: activeHighlightID
                    ) { segment in
                        model.player?.seek(to: segment.startSeconds)
                    }
                } else {
                    LyricsTranscriptView(
                        segments: model.segments,
                        markers: model.markers,
                        markerTemplate: model.sessionTemplate,
                        currentSegmentID: model.currentSegmentID,
                        highlightSegmentID: activeHighlightID
                    ) { segment in
                        model.player?.seek(to: segment.startSeconds)
                    }
                }
            } else {
                ProgressView("載入中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.directory) { await model.load() }
        .task(id: highlightSegmentID) {
            activeHighlightID = highlightSegmentID
            guard highlightSegmentID != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.5)) {
                activeHighlightID = nil
            }
        }
        .alert(
            "發生錯誤",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "重新轉錄這段音訊？",
            isPresented: $showReTranscribeConfirm,
            titleVisibility: .visible
        ) {
            Button("重新轉錄", role: .destructive) {
                Task { await model.transcribe(reset: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("會以目前的辨識語言與名詞表重新產生逐字稿並覆蓋現有逐字稿。既有的摘要、結構化事件與譯文不會自動更新，可能與新稿不符，需要時請自行重新產生。")
        }
    }

    /// 檢視頁右欄：整份摘要、結構化事件草稿與事件標記；點時間跳轉播放、點事件卡編輯。
    private var detailInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                Divider()
                structuredEventsSection
                Divider()
                markersSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
        .sheet(item: $editingEvent) { event in
            EventEditSheet(event: event) { model.updateEvent($0) }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { summaryExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: summaryExpanded ? "chevron.down" : "chevron.right")
                        .appFont(.caption)
                    Text("逐字稿摘要")
                        .appFont(.headline)
                    Spacer()
                    if SummaryBadgePolicy.showsReviewBadge(for: model.summary) {
                        Text("需複查")
                            .appFont(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.22), in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .help(summaryExpanded ? "收合" : "展開")

            Button {
                model.generateSummaryWithAI()
            } label: {
                Label(
                    model.summary == nil ? "AI 產生摘要" : "重新產生摘要",
                    systemImage: "wand.and.stars"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.summarizing || !model.canGenerateSummary)
            .help(model.summaryAvailabilityMessage ?? "用本機 AI 產生整份逐字稿摘要")

            if model.summarizing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("AI 產生摘要中…").appFont(.caption).foregroundStyle(.secondary)
                }
            } else if let message = model.summaryAvailabilityMessage, !model.segments.isEmpty {
                Text(message).appFont(.caption).foregroundStyle(.secondary)
            }

            if summaryExpanded {
                if let summary = model.summary {
                    summaryCard(summary)
                } else {
                    Text(
                        model.segments.isEmpty
                            ? "這個 session 還沒有逐字稿。先轉錄，再產生摘要。"
                            : "尚未產生摘要。"
                    )
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summaryCard(_ summary: TranscriptSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.content.isEmpty {
                Text("摘要內容空白，請重新產生。")
                    .appFont(InspectorCardTypography.summaryBody)
                    .foregroundStyle(.secondary)
            } else {
                Text(summary.content)
                    .appFont(InspectorCardTypography.summaryBody)
                    .textSelection(.enabled)
            }

            if !summary.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("重點")
                        .appFont(InspectorCardTypography.summarySubheading, weight: .bold)
                        .foregroundStyle(.secondary)
                    ForEach(summary.keyPoints, id: \.self) { point in
                        Text("• \(point)")
                            .appFont(InspectorCardTypography.summaryListItem)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if !summary.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待辦")
                        .appFont(InspectorCardTypography.summarySubheading, weight: .bold)
                        .foregroundStyle(.secondary)
                    ForEach(summary.actionItems, id: \.self) { item in
                        Text("• \(item)")
                            .appFont(InspectorCardTypography.summaryListItem)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Text("來源：\(summary.sourceSegmentIDs.count) 段逐字稿")
                .appFont(InspectorCardTypography.summarySource)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var structuredEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { eventsExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: eventsExpanded ? "chevron.down" : "chevron.right")
                        .appFont(.caption)
                    Text(
                        model.events.isEmpty ? "結構化事件" : "結構化事件（\(model.events.count)）"
                    )
                    .appFont(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .help(eventsExpanded ? "收合" : "展開")

            HStack(spacing: 8) {
                // 機械草稿：依標記前後文彙整（保留原本做法）。
                Button {
                    model.generateDrafts()
                } label: {
                    Label("依標記彙整", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.markers.isEmpty || model.organizing)
                .help(model.markers.isEmpty ? "沒有標記可彙整" : "依標記前後文產生／重新產生草稿")
                // 本機 LLM：沒草稿就從逐字稿直接生成，有草稿就補齊欄位。產物一律 needs_review。
                Button {
                    model.runAIOrganize()
                } label: {
                    Label(
                        model.events.isEmpty ? "AI 產生草稿" : "AI 整理",
                        systemImage: "wand.and.stars"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.organizing || !model.canRunAI)
                .help(model.organizeAvailabilityMessage ?? "用本機 AI 從逐字稿整理事件（型別、主題、摘要、待辦）")
            }
            .controlSize(.large)

            if model.organizing {
                if model.organizeProgress > 0 {
                    ProgressView(value: model.organizeProgress) {
                        Text("AI 整理中 \(Int(model.organizeProgress * 100))%").appFont(.caption)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("AI 處理中…").appFont(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let message = model.organizeAvailabilityMessage,
                !model.events.isEmpty || !model.segments.isEmpty
            {
                Text(message).appFont(.caption).foregroundStyle(.secondary)
            }

            if eventsExpanded {
                if model.events.isEmpty {
                    Text(
                        model.segments.isEmpty
                            ? "這個 session 還沒有逐字稿。先轉錄，再用「AI 產生草稿」或標記後「依標記彙整」。"
                            : "尚未有草稿。有標記可按「依標記彙整」，或直接按「AI 產生草稿」讓本機 AI 從逐字稿整理。"
                    )
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(model.events) { event in
                        eventCard(event)
                    }
                }
            }
        }
    }

    private func eventCard(_ event: StructuredEvent) -> some View {
        let style = MarkerVisualStyle.style(
            for: event, markersByID: model.markersByID, template: model.sessionTemplate)
        return Button {
            editingEvent = event
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(style.tint)
                    Text(event.topic.isEmpty ? event.type : event.topic)
                        .appFont(.callout, weight: .bold)
                        .lineLimit(1)
                    Spacer()
                    if event.needsReview {
                        Text("需複查")
                            .appFont(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.22), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(event.type)
                        .appFont(InspectorCardTypography.eventMetadata)
                        .foregroundStyle(.secondary)
                    Button {
                        model.player?.seek(to: event.startSeconds)
                    } label: {
                        Text(TimeFormatting.hms(event.startSeconds))
                            .appFont(
                                InspectorCardTypography.eventMetadata,
                                monospacedDigit: true)
                    }
                    .buttonStyle(.plain)
                    .help("跳到 \(TimeFormatting.hms(event.startSeconds))")
                }
                if !event.content.isEmpty {
                    Text(event.content)
                        .appFont(InspectorCardTypography.eventContent)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("來源：\(event.sourceSegmentIDs.count) 段、\(event.sourceMarkerIDs.count) 標記")
                    .appFont(InspectorCardTypography.eventSource)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(style.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style.border, lineWidth: 1)
        )
        .help("點擊編輯這筆事件")
    }

    private var markersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { markersExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: markersExpanded ? "chevron.down" : "chevron.right")
                        .appFont(.caption)
                    Text(
                        model.markers.isEmpty ? "事件標記" : "事件標記（\(model.markers.count)）"
                    )
                    .appFont(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .help(markersExpanded ? "收合" : "展開")

            if markersExpanded {
                if model.markers.isEmpty {
                    Text("這個 session 沒有標記。")
                        .appFont(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.markers) { marker in
                        MarkerInspectorRow(
                            marker: marker,
                            style: MarkerVisualStyle.style(
                                for: marker, template: model.sessionTemplate),
                            onJump: { model.player?.seek(to: marker.mediaSeconds) }
                        ) {
                            model.removeMarker(marker.markerID)
                        }
                    }
                }
            }
        }
    }

    /// 標題列：點標題文字改名（仿 iOS）；資訊列只留語言、分段數、標記數。
    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if editingTitle {
                    TextField("名稱", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                        .appFont(.title2, weight: .bold)
                        .focused($titleFieldFocused)
                        .frame(maxWidth: 360)
                        .onSubmit { commitRename() }
                        .onExitCommand { editingTitle = false }
                } else {
                    Text(session.title)
                        .appFont(.title2, weight: .bold)
                        .onTapGesture {
                            titleDraft = session.title
                            editingTitle = true
                            titleFieldFocused = true
                        }
                        .help("點擊重新命名")
                }
                if session.source == .imported {
                    Text("匯入")
                        .appFont(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if session.recovered {
                    Text("已恢復")
                        .appFont(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                PrivacyModeBadge(mode: session.privacyMode)
                Spacer()
                displayModeToggle
            }
            HStack(spacing: 10) {
                Text("\(session.locale)　分段：\(model.segments.count)　標記：\(model.markers.count)")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                if !model.segments.isEmpty && model.player != nil {
                    if model.transcribing {
                        ProgressView(value: model.transcribeProgress)
                            .frame(width: 90)
                    } else {
                        Button {
                            showReTranscribeConfirm = true
                        } label: {
                            Label("重新轉錄", systemImage: "arrow.clockwise")
                                .appFont(.callout)
                        }
                        .buttonStyle(.borderless)
                        .help("以目前辨識語言與名詞表重新產生逐字稿，覆蓋現有逐字稿")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commitRename() {
        model.rename(to: titleDraft)
        editingTitle = false
        onRename?()
    }

    /// 顯示模式切換：點擊在歌詞模式與列表模式間循環，與倍速同樣的輕量互動。
    private var displayModeToggle: some View {
        Button {
            transcriptMode =
                transcriptMode == DisplaySettings.lyricsMode
                ? DisplaySettings.listMode : DisplaySettings.lyricsMode
        } label: {
            Label(
                transcriptMode == DisplaySettings.lyricsMode ? "歌詞模式" : "列表模式",
                systemImage: transcriptMode == DisplaySettings.lyricsMode
                    ? "music.note.list" : "list.bullet")
            .appFont(.callout)
        }
        .buttonStyle(.borderless)
        .help("切換逐字稿顯示方式（歌詞模式與列表模式循環）")
    }

    @ViewBuilder
    private var playbackBar: some View {
        if let player = model.player {
            HStack(spacing: 10) {
                Button {
                    if !player.isPlaying {
                        SessionPlayerCache.shared.pauseAll(except: player)
                    }
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .appFont(.title3)
                }
                .buttonStyle(.borderless)
                .help(player.isPlaying ? "暫停" : "播放")
                Button {
                    let index =
                        Self.playbackRates.firstIndex(of: player.playbackRate) ?? 3
                    player.playbackRate =
                        Self.playbackRates[(index + 1) % Self.playbackRates.count]
                } label: {
                    Text(String(format: "%g×", player.playbackRate))
                        .appFont(.callout, monospacedDigit: true)
                        .frame(minWidth: 40)
                }
                .buttonStyle(.borderless)
                .help("播放倍速（點擊循環切換）")
                Text(TimeFormatting.hms(player.currentSeconds))
                    .appFont(.caption, monospacedDigit: true)
                Slider(
                    value: Binding(
                        get: { player.currentSeconds },
                        set: { player.seek(to: $0) }),
                    in: 0...max(player.totalSeconds, 0.01))
                Text(TimeFormatting.hms(player.totalSeconds))
                    .appFont(.caption, monospacedDigit: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            Text("此 session 沒有可播放的音訊。")
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var emptyTranscriptArea: some View {
        ContentUnavailableView {
            Label("沒有逐字稿", systemImage: "text.bubble")
        } description: {
            Text("這個 session 還沒有轉寫結果。")
        } actions: {
            if model.transcribing {
                ProgressView(value: model.transcribeProgress) {
                    Text("離線轉寫中 \(Int(model.transcribeProgress * 100))%")
                }
                .frame(width: 220)
            } else if model.player != nil {
                Button("離線轉寫這段音訊") {
                    Task { await model.transcribe() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 歌詞模式（規格 1.1 第 10 項）：當前 segment 放大、全不透明、加粗，
/// 其餘縮小降不透明度，spring 動畫切換並自動置中。
/// 內文可選取複製；點時間戳跳轉播放位置。
struct LyricsTranscriptView: View {
    let segments: [TranscriptSegment]
    let markers: [Marker]
    let markerTemplate: SessionTemplate
    let currentSegmentID: String?
    let highlightSegmentID: String?
    let onSelect: (TranscriptSegment) -> Void
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(segments) { segment in
                        lyricsRow(segment)
                            .id(segment.segmentID)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .onChange(of: currentSegmentID) {
                guard let currentSegmentID else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(currentSegmentID, anchor: .center)
                }
            }
            .onAppear {
                if let highlightSegmentID {
                    proxy.scrollTo(highlightSegmentID, anchor: .center)
                }
            }
        }
    }

    private func lyricsRow(_ segment: TranscriptSegment) -> some View {
        let isCurrent = segment.segmentID == currentSegmentID
        let isHighlighted = segment.segmentID == highlightSegmentID
        let inlineMarkers = MarkerTimeline.inlineMarkers(for: segment, markers: markers)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(TimeFormatting.hms(segment.startSeconds))
                    .appFont(.caption2, monospacedDigit: true)
                    .foregroundStyle(.tertiary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(segment)
                    }
                    .help("點擊時間跳到 \(TimeFormatting.hms(segment.startSeconds))")
                ForEach(inlineMarkers) { marker in
                    MarkerChip(
                        marker: marker,
                        style: MarkerVisualStyle.style(for: marker, template: markerTemplate))
                }
            }
            Text(segment.text)
                .font(.system(
                    size: isCurrent ? fontSize * 1.3 : fontSize,
                    weight: isCurrent ? .bold : .regular))
                .lineSpacing(fontSize * 0.3)
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .opacity(isCurrent ? 1.0 : 0.5)
                .textSelection(.enabled)
        }
        .scaleEffect(isCurrent ? 1.0 : 0.97, anchor: .leading)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentSegmentID)
    }
}

/// 列表模式：時間徽章加內文的一般排版，適合閱讀與大段選取複製；
/// 點時間徽章跳轉播放位置，不自動捲動。
struct PlainTranscriptView: View {
    let segments: [TranscriptSegment]
    let markers: [Marker]
    let markerTemplate: SessionTemplate
    let currentSegmentID: String?
    let highlightSegmentID: String?
    let onSelect: (TranscriptSegment) -> Void
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(segments) { segment in
                        plainRow(segment)
                            .id(segment.segmentID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onAppear {
                if let highlightSegmentID {
                    proxy.scrollTo(highlightSegmentID, anchor: .center)
                }
            }
        }
    }

    private func plainRow(_ segment: TranscriptSegment) -> some View {
        let isCurrent = segment.segmentID == currentSegmentID
        let isHighlighted = segment.segmentID == highlightSegmentID
        let inlineMarkers = MarkerTimeline.inlineMarkers(for: segment, markers: markers)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    onSelect(segment)
                } label: {
                    Text(
                        "\(TimeFormatting.hms(segment.startSeconds)) - "
                            + TimeFormatting.hms(segment.endSeconds)
                    )
                    .appFont(.caption, monospacedDigit: true)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("點擊跳到 \(TimeFormatting.hms(segment.startSeconds))")
                ForEach(inlineMarkers) { marker in
                    MarkerChip(
                        marker: marker,
                        style: MarkerVisualStyle.style(for: marker, template: markerTemplate))
                }
            }
            Text(segment.text)
                .font(.system(size: fontSize, weight: isCurrent ? .semibold : .regular))
                .lineSpacing(fontSize * 0.35)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 事件草稿編輯表單（v0.2）：可改語意欄位與 needs_review；
/// eventID、來源 segment／marker、時間與 createdAt 等來源欄位唯讀不變。
struct EventEditSheet: View {
    let event: StructuredEvent
    let onSave: (StructuredEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var topic: String
    @State private var speaker: String
    @State private var speakerRole: String
    @State private var content: String
    @State private var responseSummary: String
    @State private var actionItem: String
    @State private var priority: String
    @State private var tagsText: String
    @State private var needsReview: Bool

    init(event: StructuredEvent, onSave: @escaping (StructuredEvent) -> Void) {
        self.event = event
        self.onSave = onSave
        _topic = State(initialValue: event.topic)
        _speaker = State(initialValue: event.speaker)
        _speakerRole = State(initialValue: event.speakerRole)
        _content = State(initialValue: event.content)
        _responseSummary = State(initialValue: event.responseSummary)
        _actionItem = State(initialValue: event.actionItem)
        _priority = State(
            initialValue: ["high", "medium", "low"].contains(event.priority)
                ? event.priority : "medium")
        _tagsText = State(initialValue: event.tags.joined(separator: "、"))
        _needsReview = State(initialValue: event.needsReview)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("編輯事件").appFont(.headline)
                Spacer()
            }
            .padding()
            Divider()
            Form {
                Section("分類") {
                    TextField("主題", text: $topic)
                    Picker("優先", selection: $priority) {
                        Text("高").tag("high")
                        Text("中").tag("medium")
                        Text("低").tag("low")
                    }
                    Toggle("需複查（needs_review）", isOn: $needsReview)
                }
                Section("發言") {
                    TextField("發言者", text: $speaker)
                    TextField("角色", text: $speakerRole)
                }
                Section("內容") {
                    TextField("提問／內容", text: $content, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("回應摘要", text: $responseSummary, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("待辦／待補", text: $actionItem, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("標籤（以、或逗號分隔）", text: $tagsText)
                }
                Section("來源（唯讀）") {
                    LabeledContent(
                        "時間",
                        value: "\(TimeFormatting.hms(event.startSeconds)) - "
                            + TimeFormatting.hms(event.endSeconds))
                    LabeledContent(
                        "來源段落",
                        value: event.sourceSegmentIDs.isEmpty
                            ? "無" : event.sourceSegmentIDs.joined(separator: ", "))
                    LabeledContent(
                        "來源標記",
                        value: event.sourceMarkerIDs.isEmpty
                            ? "無" : event.sourceMarkerIDs.joined(separator: ", "))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("儲存") {
                    onSave(edited())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 580)
    }

    private func edited() -> StructuredEvent {
        var updated = event
        updated.topic = topic
        updated.speaker = speaker
        updated.speakerRole = speakerRole
        updated.content = content
        updated.responseSummary = responseSummary
        updated.actionItem = actionItem
        updated.priority = priority
        updated.tags =
            tagsText
            .split(whereSeparator: { $0 == "、" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        updated.needsReview = needsReview
        return updated
    }
}
