import AppKit
import SSAudio
import SSCore
import SwiftUI

/// App 主視窗的三欄殼層：sidebar（搜尋、分類、session 列表、多選與批次列）、
/// main（即時逐字稿或錄音檢視頁）、inspector（可收合，標記與後續擴充）。
public struct RootView: View {
    @Bindable private var model: RecordingViewModel
    @State private var showInspector = true
    @State private var selection: Set<String> = []
    @State private var sidebarSelection: Set<String> = []
    @State private var searchText = ""
    @State private var searchHistory = SearchHistory.load()
    @State private var searchHighlight: SearchHit?
    @State private var showCategoryManager = false
    @State private var confirmBatchDelete = false
    @State private var infoSession: Session?
    @FocusState private var transcriptFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @AppStorage(DisplaySettings.appearanceKey)
    private var appearance = "system"

    public init(model: RecordingViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailArea
        }
        .toolbar { toolbarContent }
        .navigationTitle("SessionScribe")
        .task { await model.onLaunch() }
        .preferredColorScheme(DisplaySettings.colorScheme(for: appearance))
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagerView(model: model)
        }
        .sheet(item: $infoSession) { session in
            SessionInfoView(session: session)
        }
        .alert("需要麥克風權限", isPresented: $model.micPermissionDenied) {
            Button("開啟系統設定") {
                NSWorkspace.shared.open(MicrophonePermission.settingsURL)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("錄音需要麥克風權限。請在「系統設定、隱私權與安全性、麥克風」允許 SessionScribe。")
        }
        .alert(
            "磁碟空間不足",
            isPresented: Binding(
                get: { model.diskSpaceWarning != nil },
                set: { if !$0 { model.diskSpaceWarning = nil } })
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(model.diskSpaceWarning ?? "")
        }
        .alert(
            "完成",
            isPresented: Binding(
                get: { model.infoMessage != nil },
                set: { if !$0 { model.infoMessage = nil } })
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.infoMessage ?? "")
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
            "刪除選取的 \(sidebarSelection.count) 個 session？",
            isPresented: $confirmBatchDelete,
            titleVisibility: .visible
        ) {
            Button("刪除（移至垃圾桶）", role: .destructive) {
                model.deleteSessions(sidebarSelection)
                sidebarSelection = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("錄音、逐字稿與標記會一併移至垃圾桶，可從垃圾桶復原。")
        }
        .confirmationDialog(
            "匯入完成",
            isPresented: Binding(
                get: { model.pendingTranscription != nil },
                set: { if !$0 { model.pendingTranscription = nil } }),
            titleVisibility: .visible
        ) {
            Button("立即離線轉寫") {
                if let session = model.pendingTranscription {
                    model.transcribeImported(session)
                    sidebarSelection = [session.sessionID]
                }
            }
            Button("稍後再說", role: .cancel) {
                if let session = model.pendingTranscription {
                    sidebarSelection = [session.sessionID]
                }
            }
        } message: {
            Text("「\(model.pendingTranscription?.title ?? "")」已匯入。要現在轉寫成逐字稿嗎？之後也可以在檢視頁啟動轉寫。")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResultsSection
            } else {
                sessionSections
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜尋逐字稿與標記")
        .searchSuggestions { searchSuggestionRows }
        .onSubmit(of: .search) { recordSearch() }
        .contextMenu(forSelectionType: String.self) { ids in
            sessionContextMenu(for: ids)
        }
        .safeAreaInset(edge: .bottom) {
            if sidebarSelection.count > 1 {
                batchActionBar
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }

    /// 搜尋紀錄建議（規格 1.1 第 9 項擴充：紀錄與清除）。
    @ViewBuilder
    private var searchSuggestionRows: some View {
        if searchText.isEmpty && !searchHistory.isEmpty {
            Section("最近搜尋") {
                ForEach(searchHistory, id: \.self) { item in
                    Label(item, systemImage: "clock.arrow.circlepath")
                        .searchCompletion(item)
                }
                Button {
                    SearchHistory.clear()
                    searchHistory = []
                } label: {
                    Label("清除搜尋紀錄", systemImage: "trash")
                }
            }
        }
    }

    private func recordSearch() {
        SearchHistory.record(searchText)
        searchHistory = SearchHistory.load()
    }

    /// 多選時浮出的批次操作列：明顯的批量移動與刪除入口。
    private var batchActionBar: some View {
        HStack(spacing: 8) {
            Text("已選 \(sidebarSelection.count) 個")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("未分類") {
                    model.assignCategory(nil, to: sidebarSelection)
                }
                ForEach(model.libraryConfig.categories) { category in
                    Button(category.name) {
                        model.assignCategory(category.id, to: sidebarSelection)
                    }
                }
            } label: {
                Label("移至分類", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button(role: .destructive) {
                confirmBatchDelete = true
            } label: {
                Label("刪除", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var searchResultsSection: some View {
        Section("搜尋結果") {
            let hits = model.search(searchText)
            if hits.isEmpty {
                Text("沒有符合「\(searchText)」的內容")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(hits) { hit in
                    Button {
                        searchHighlight = hit
                        sidebarSelection = [hit.sessionID]
                        recordSearch()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(
                                    systemName: hit.markerID != nil
                                        ? "bookmark.fill" : "text.bubble")
                                .foregroundStyle(.secondary)
                                Text(hit.sessionTitle)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer()
                                Text(TimeFormatting.hms(hit.mediaSeconds))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(hit.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var sessionSections: some View {
        Section("未分類") {
            if model.uncategorizedSessions.isEmpty {
                Text("尚無 session")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.uncategorizedSessions) { session in
                    sessionRow(session)
                        .tag(session.sessionID)
                }
            }
        }
        ForEach(model.visibleCategories) { category in
            Section(category.name) {
                ForEach(model.sessions(in: category.id)) { session in
                    sessionRow(session)
                        .tag(session.sessionID)
                }
            }
        }
    }

    /// 列表只顯示標題與必要徽章；id 與時間等細節收進「詳細資訊」第二層。
    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 6) {
            Text(session.title)
                .lineLimit(1)
            if session.sessionID == model.activeSession?.sessionID,
                model.state == .recording || model.state == .paused
            {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("錄音中")
            }
            Spacer()
            if session.source == .imported {
                badge("匯入")
            }
            if session.recovered {
                badge("已恢復")
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private func sessionContextMenu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first,
            let session = model.sessions.first(where: { $0.sessionID == id })
        {
            Button("詳細資訊…") {
                infoSession = session
            }
            Button("匯出…") {
                model.export(session: session)
            }
            Button("在 Finder 顯示") {
                NSWorkspace.shared.activateFileViewerSelecting([model.directory(for: session)])
            }
            Divider()
        }
        if !ids.isEmpty {
            Menu("移至分類") {
                Button("未分類") {
                    model.assignCategory(nil, to: ids)
                }
                ForEach(model.libraryConfig.categories) { category in
                    Button(category.name) {
                        model.assignCategory(category.id, to: ids)
                    }
                }
            }
            Button("刪除\(ids.count > 1 ? "選取的 \(ids.count) 個" : "")…", role: .destructive) {
                sidebarSelection = ids
                confirmBatchDelete = true
            }
        }
        Divider()
        Button("管理分類…") {
            showCategoryManager = true
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailArea: some View {
        if sidebarSelection.count == 1, let id = sidebarSelection.first,
            id != model.activeSession?.sessionID,
            let session = model.sessions.first(where: { $0.sessionID == id })
        {
            SessionDetailView(
                directory: model.directory(for: session),
                highlightSegmentID: searchHighlight?.sessionID == id
                    ? searchHighlight?.segmentID : nil,
                showInspector: $showInspector
            )
            .id(id)
        } else {
            transcriptArea
                .inspector(isPresented: $showInspector) {
                    inspectorPanel
                }
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if model.activeSession == nil {
            ContentUnavailableView {
                Label("尚未開始記錄", systemImage: "waveform")
            } description: {
                Text("按工具列的錄音鈕開始（會自動建立新錄音），或匯入既有音檔。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.transcript.isEmpty && model.volatileText == nil {
            ContentUnavailableView {
                Label(
                    model.state == .recording ? "錄音中" : "準備就緒",
                    systemImage: model.state == .recording ? "record.circle" : "waveform")
            } description: {
                Text(
                    model.state == .recording
                        ? (model.transcriptionState == .recordingOnly
                            ? "純錄音模式，不轉寫。" : "等待第一句轉寫結果。")
                        : "按工具列的錄音鈕開始。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TranscriptListView(model: model, selection: $selection)
                .focusable()
                .focused($transcriptFocused)
                .onKeyPress { press in
                    handleMarkerKey(press.characters)
                }
        }
    }

    /// 單鍵快捷的焦點規則（規格書決議 6）：只在逐字稿區持有焦點時生效。
    private func handleMarkerKey(_ characters: String) -> KeyPress.Result {
        guard model.state == .recording || model.state == .paused else { return .ignored }
        switch characters.lowercased() {
        case "q":
            model.addMarker(.question)
        case "r":
            model.addMarker(.requiredRevision)
        case "s":
            model.addMarker(.suggestion)
        case "a":
            model.addMarker(.importantAnswer)
        default:
            return .ignored
        }
        return .handled
    }

    // MARK: - Inspector（即時畫面）

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("事件標記")
                .font(.headline)
            MarkerButtonsView(
                isEnabled: model.state == .recording || model.state == .paused
            ) { type in
                model.addMarker(type)
            }
            if model.markers.isEmpty {
                Text("錄音中按 Q、R、S、A（逐字稿區聚焦時）或 Cmd+1 至 Cmd+4 建立標記。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List(model.markers.reversed()) { marker in
                    markerRow(marker)
                }
                .listStyle(.inset)
            }
            Spacer(minLength: 0)
            if !selection.isEmpty {
                Button {
                    model.exportSelection(selection)
                } label: {
                    Label("匯出選取的 \(selection.count) 段…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
    }

    private func markerRow(_ marker: Marker) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Label(marker.label, systemImage: "bookmark.fill")
                    .font(.callout)
                Spacer()
                Text(TimeFormatting.hms(marker.mediaSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !marker.note.isEmpty {
                Text(marker.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.importAudio()
            } label: {
                Label("匯入音檔", systemImage: "square.and.arrow.down")
            }
            .disabled(model.state == .recording || model.state == .paused)
            .help("匯入音訊檔作為新 session，可選擇是否轉寫")

            inputDevicePicker
        }
        ToolbarItemGroup {
            modePicker
            recordButton
            Button {
                Task { await model.stop() }
            } label: {
                Label("停止", systemImage: "stop.circle")
            }
            .disabled(model.state != .recording && model.state != .paused)
            .help("停止並保存")

            Button {
                model.exportActiveSession()
            } label: {
                Label("匯出", systemImage: "square.and.arrow.up")
            }
            .disabled(model.activeSession == nil)
            .help("匯出目前 session（Markdown、CSV、JSON）")

            Button {
                openWindow(id: "floating-transcript")
            } label: {
                Label("浮動逐字稿", systemImage: "macwindow.on.rectangle")
            }
            .help("開啟置頂的即時逐字稿視窗")
        }
        ToolbarItemGroup {
            statusArea
            Button {
                showInspector.toggle()
            } label: {
                Label("右欄", systemImage: "sidebar.trailing")
            }
            .help("顯示或隱藏右欄")
        }
    }

    /// 單一錄音鈕：未錄音時開始（自動建立「新錄音N」）、錄音中暫停、暫停中繼續。
    @ViewBuilder
    private var recordButton: some View {
        switch model.state {
        case .recording:
            Button {
                Task { await model.pause() }
            } label: {
                Label("暫停", systemImage: "pause.circle.fill")
            }
            .help("暫停錄音")
        case .paused:
            Button {
                Task { await model.resume() }
            } label: {
                Label("繼續", systemImage: "play.circle.fill")
            }
            .help("繼續錄音")
        case .idle, .stopped:
            Button {
                Task { await model.startRecording() }
            } label: {
                Label("錄音", systemImage: "record.circle")
            }
            .help("開始錄音（自動建立新錄音）")
        }
    }

    /// 本場模式：邊錄音邊轉寫或純錄音。錄音中不可切換。
    private var modePicker: some View {
        Picker("模式", selection: $model.transcribeEnabled) {
            Label("錄音＋轉寫", systemImage: "waveform.badge.mic").tag(true)
            Label("純錄音", systemImage: "mic").tag(false)
        }
        .pickerStyle(.menu)
        .disabled(model.state == .recording || model.state == .paused)
        .help("本次錄音是否同時轉寫（下一場生效）")
    }

    /// 狀態區：統一以徽章呈現，保持一致性。
    @ViewBuilder
    private var statusArea: some View {
        StatusBadge(text: "本機模式", systemImage: "lock.shield")
        StatusBadge(
            text: model.stateDescription.text,
            systemImage: model.stateDescription.systemImage)
        if let transcription = model.transcriptionDescription {
            StatusBadge(text: transcription.text, systemImage: transcription.systemImage)
        }
        if model.state == .recording || model.state == .paused {
            StatusBadge(text: model.formattedDuration, systemImage: "timer")
            LevelMeterView(level: model.level)
        }
    }

    private var inputDevicePicker: some View {
        Picker("輸入裝置", selection: $model.selectedDeviceUID) {
            Text("系統預設輸入").tag(String?.none)
            ForEach(model.inputDevices) { device in
                Text(device.name).tag(String?.some(device.id))
            }
        }
        .pickerStyle(.menu)
        .disabled(model.state == .recording || model.state == .paused)
        .help("選擇音訊輸入裝置（下一場生效）")
    }
}

/// 狀態徽章：文字加圖示，不單靠顏色傳達狀態。
struct StatusBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(text)
    }
}
