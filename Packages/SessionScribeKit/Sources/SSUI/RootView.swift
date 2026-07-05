import AppKit
import SSAudio
import SSCore
import SwiftUI

/// App 主視窗的三欄殼層：sidebar（搜尋、排序、分類、session 列表、多選與批次列）、
/// main（即時逐字稿或錄音檢視頁）、inspector（可收合，標記與後續擴充）。
public struct RootView: View {
    @Bindable private var model: RecordingViewModel
    @State private var showInspector = true
    @State private var selection: Set<String> = []
    @State private var sidebarSelection: Set<String> = []
    @State private var searchText = ""
    @State private var searchHistory = SearchHistory.load()
    @State private var searchHighlight: SearchHit?
    /// 非同步搜尋結果與其對應的查詢字串；兩者不一致代表掃描仍在進行。
    @State private var searchHits: [SearchHit] = []
    @State private var searchedText = ""
    @State private var showCategoryManager = false
    @State private var confirmBatchDelete = false
    @State private var infoSession: Session?
    /// 長按列觸發的多選模式（仿 iOS）：列前顯示勾選圈，底部浮出刪除列。
    @State private var selectionMode = false
    /// 已折疊的側欄區段 id（未分類用固定鍵）。
    @State private var collapsedSections: Set<String> = []
    /// 側欄點選中列標題觸發的改名狀態。
    @State private var renamingSessionID: String?
    @State private var renameDraft = ""
    @FocusState private var renameFieldFocused: Bool
    @FocusState private var transcriptFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(DisplaySettings.appearanceKey)
    private var appearance = "system"

    private static let uncategorizedSectionID = "uncategorized"

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
        .toolbar(removing: .title)
        .navigationTitle("SessionScribe")
        .task { await model.onLaunch() }
        .appTypography()
        .dynamicTypeSize(DisplaySettings.uiTypeSize)
        .preferredColorScheme(DisplaySettings.colorScheme(for: appearance))
        .onChange(of: model.state) { _, newState in
            // 停止錄音後直接選取該則，detailArea 切到含播放器的檢視頁。
            if newState == .stopped, let id = model.activeSession?.sessionID {
                sidebarSelection = [id]
            }
        }
        .onChange(of: searchText) { _, newValue in
            // 搜尋欄清空即移除逐字稿的跳轉高亮。
            if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                searchHighlight = nil
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagerView(model: model)
        }
        .sheet(item: $infoSession) { session in
            SessionInfoView(session: session)
        }
        .sheet(item: $model.exportRequest) { session in
            ExportOptionsView(session: session) { formats in
                model.performExport(session: session, formats: formats)
            }
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
                selectionMode = false
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
            Button(model.pendingTranscriptionActionTitle) {
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
        List(selection: selectionMode ? .constant(Set<String>()) : $sidebarSelection) {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResultsSection
            } else {
                sessionSections
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜尋逐字稿與標記")
        .searchSuggestions { searchSuggestionRows }
        .onSubmit(of: .search) { recordSearch() }
        // 輸入停頓後才掃描，且掃描在背景執行緒：全庫 JSONL 線性掃描
        // 不能逐鍵同步跑在主執行緒（輸入會卡）。改字即取消重來。
        .task(id: searchText) {
            let trimmed = searchText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                searchHits = []
                searchedText = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let hits = await model.search(trimmed)
            guard !Task.isCancelled else { return }
            searchHits = hits
            searchedText = trimmed
        }
        .contextMenu(forSelectionType: String.self) { ids in
            sessionContextMenu(for: ids)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            sidebarControlBar
        }
        .safeAreaInset(edge: .bottom) {
            if selectionMode {
                selectionModeBar
            } else if sidebarSelection.count > 1 {
                batchActionBar
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }

    /// 搜尋框下方的工具列：排序方式與分類管理入口（規格 1.1 第 7 項可發現性）。
    private var sidebarControlBar: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("排序", selection: $model.sortOrder) {
                    ForEach(RecordingViewModel.SessionSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.sortOrder.displayName, systemImage: "arrow.up.arrow.down")
                    .appFont(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("列表排序方式")
            Spacer()
            Button {
                showCategoryManager = true
            } label: {
                Label("分類", systemImage: "folder.badge.gearshape")
                    .appFont(.callout)
            }
            .buttonStyle(.borderless)
            .help("管理分類（新增、改名、隱藏、刪除）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

    /// 長按觸發的多選模式底欄：置中的刪除按鈕（仿 iOS），附移動分類與取消。
    private var selectionModeBar: some View {
        HStack {
            Button("取消") { exitSelectionMode() }
                .buttonStyle(.borderless)
            Spacer()
            Button(role: .destructive) {
                confirmBatchDelete = true
            } label: {
                Label(
                    sidebarSelection.isEmpty ? "刪除" : "刪除（\(sidebarSelection.count)）",
                    systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(sidebarSelection.isEmpty)
            Spacer()
            Menu {
                categoryAssignButtons(for: sidebarSelection)
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(sidebarSelection.isEmpty)
            .help("移至分類")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Cmd 多選時浮出的批次操作列：明顯的批量移動與刪除入口。
    private var batchActionBar: some View {
        HStack(spacing: 8) {
            Text("已選 \(sidebarSelection.count) 個")
                .appFont(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                categoryAssignButtons(for: sidebarSelection)
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

    @ViewBuilder
    private func categoryAssignButtons(for ids: Set<String>) -> some View {
        Button("未分類") {
            model.assignCategory(nil, to: ids)
        }
        ForEach(model.libraryConfig.categories) { category in
            Button(category.name) {
                model.assignCategory(category.id, to: ids)
            }
        }
    }

    private var searchResultsSection: some View {
        Section("搜尋結果") {
            if searchHits.isEmpty {
                if searchedText == searchText.trimmingCharacters(in: .whitespaces) {
                    Text("沒有符合「\(searchText)」的內容")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("搜尋中…").foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(searchHits) { hit in
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
                                    .appFont(.callout)
                                    .lineLimit(1)
                                Spacer()
                                Text(TimeFormatting.hms(hit.mediaSeconds))
                                    .appFont(.caption2, monospacedDigit: true)
                                    .foregroundStyle(.secondary)
                            }
                            Text(hit.snippet)
                                .appFont(.caption)
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
        Section(isExpanded: expandedBinding(Self.uncategorizedSectionID)) {
            if model.uncategorizedSessions.isEmpty {
                Text("尚無 session")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.uncategorizedSessions) { session in
                    sessionRow(session)
                        .tag(session.sessionID)
                }
            }
        } header: {
            sectionHeader("未分類", dropCategoryID: nil)
        }
        ForEach(model.visibleCategories) { category in
            Section(isExpanded: expandedBinding(category.id)) {
                ForEach(model.sessions(in: category.id)) { session in
                    sessionRow(session)
                        .tag(session.sessionID)
                }
            } header: {
                sectionHeader(category.name, dropCategoryID: category.id)
            }
        }
    }

    /// 區段標頭：加重字級與顏色（修正過淡過細），並作為拖放目標收 session。
    private func sectionHeader(_ title: String, dropCategoryID: String?) -> some View {
        Text(title)
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(.primary)
            .dropDestination(for: String.self) { ids, _ in
                model.assignCategory(dropCategoryID, to: Set(ids))
                return true
            }
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(id) },
            set: { expanded in
                if expanded {
                    collapsedSections.remove(id)
                } else {
                    collapsedSections.insert(id)
                }
            })
    }

    /// 列表只顯示標題與必要徽章；id 與時間等細節收進「詳細資訊」第二層。
    /// 點選中列的標題改名；長按進入多選模式；可拖到區段標頭換分類。
    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 6) {
            if selectionMode {
                Image(
                    systemName: sidebarSelection.contains(session.sessionID)
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(
                    sidebarSelection.contains(session.sessionID)
                        ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            if renamingSessionID == session.sessionID {
                TextField("名稱", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFieldFocused)
                    .onSubmit { commitSidebarRename(session) }
                    .onExitCommand { renamingSessionID = nil }
            } else {
                Text(session.title)
                    .lineLimit(1)
                    .onTapGesture { handleTitleTap(session) }
            }
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
        .contentShape(Rectangle())
        .draggable(session.sessionID)
        .simultaneousGesture(
            TapGesture().onEnded {
                if selectionMode {
                    toggleSelection(session.sessionID)
                }
            })
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                enterSelectionMode(with: session.sessionID)
            })
    }

    /// 點標題文字：未選中先選中，已是唯一選中則進入改名（仿 iOS 兩段式）。
    private func handleTitleTap(_ session: Session) {
        guard !selectionMode else { return }
        if sidebarSelection == [session.sessionID] {
            renameDraft = session.title
            renamingSessionID = session.sessionID
            renameFieldFocused = true
        } else {
            sidebarSelection = [session.sessionID]
        }
    }

    private func commitSidebarRename(_ session: Session) {
        model.renameSession(session.sessionID, to: renameDraft)
        renamingSessionID = nil
    }

    private func toggleSelection(_ id: String) {
        if sidebarSelection.contains(id) {
            sidebarSelection.remove(id)
        } else {
            sidebarSelection.insert(id)
        }
    }

    private func enterSelectionMode(with id: String) {
        guard !selectionMode else { return }
        selectionMode = true
        sidebarSelection = [id]
    }

    private func exitSelectionMode() {
        selectionMode = false
        sidebarSelection = []
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .appFont(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private func sessionContextMenu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first,
            let session = model.sessions.first(where: { $0.sessionID == id })
        {
            Button("重新命名") {
                sidebarSelection = [id]
                renameDraft = session.title
                renamingSessionID = id
                renameFieldFocused = true
            }
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
                categoryAssignButtons(for: ids)
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

    /// 只有錄音中／暫停中的 activeSession 才走即時逐字稿頁；
    /// 已停止的場次一律進檢視頁（含播放器），修正剛停止的錄音看不到內容的問題。
    @ViewBuilder
    private var detailArea: some View {
        if sidebarSelection.count == 1, let id = sidebarSelection.first,
            let session = model.sessions.first(where: { $0.sessionID == id }),
            !(id == model.activeSession?.sessionID
                && (model.state == .recording || model.state == .paused))
        {
            SessionDetailView(
                directory: model.directory(for: session),
                highlightSegmentID: searchHighlight?.sessionID == id
                    ? searchHighlight?.segmentID : nil,
                showInspector: $showInspector,
                onRename: { model.refreshSessions() }
            )
            .id(id)
        } else {
            transcriptArea
                .inspector(isPresented: $showInspector) {
                    inspectorPanel
                }
        }
    }

    /// 工具列匯出鈕的對象：優先取側欄單選的檢視中 session，否則退回錄音中的
    /// activeSession。瀏覽既有錄音時 activeSession 為 nil，故不能只看它。
    private var exportTargetSession: Session? {
        if sidebarSelection.count == 1, let id = sidebarSelection.first,
            let session = model.sessions.first(where: { $0.sessionID == id })
        {
            return session
        }
        return model.activeSession
    }

    @ViewBuilder
    private var transcriptArea: some View {
        VStack(spacing: 0) {
            if let progress = model.modelDownloadProgress {
                downloadBanner(progress)
            }
            transcriptContent
        }
    }

    /// 辨識模型下載進度橫幅：開始錄音前若模型未裝就會出現，填滿才開始轉寫。
    private func downloadBanner(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("下載辨識模型中… \(Int(progress * 100))%（就緒後才會開始轉寫）")
                    .appFont(.callout)
                Spacer()
            }
            ProgressView(value: progress)
        }
        .padding(10)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var transcriptContent: some View {
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
    /// 單鍵 Q/R/S/A 是論文口試模板的字母助記，對應四鍵位置；其他模板
    /// 只用 Cmd+1 至 4（位置對應該模板的四個 markerType）。
    private func handleMarkerKey(_ characters: String) -> KeyPress.Result {
        guard model.state == .recording || model.state == .paused else { return .ignored }
        guard model.activeTemplate.id == "thesis_defense" else { return .ignored }
        let index: Int
        switch characters.lowercased() {
        case "q": index = 0
        case "r": index = 1
        case "s": index = 2
        case "a": index = 3
        default: return .ignored
        }
        guard index < model.activeMarkerTypes.count else { return .ignored }
        model.addMarker(model.activeMarkerTypes[index])
        return .handled
    }

    // MARK: - Inspector（即時畫面）

    /// 空標記時的提示：論文口試模板提 Q/R/S/A，其餘模板只提 Cmd 編號。
    private var markerHint: String {
        model.activeTemplate.id == "thesis_defense"
            ? "錄音中按 Q、R、S、A（逐字稿區聚焦時）或 Cmd+1 至 Cmd+4 建立標記。"
            : "錄音中按 Cmd+1 至 Cmd+4 建立標記（依「\(model.activeTemplate.name)」模板的四鍵）。"
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("事件標記")
                .appFont(.headline)
            MarkerButtonsView(
                markerTypes: model.activeMarkerTypes,
                showLetterHints: model.activeTemplate.id == "thesis_defense",
                isEnabled: model.state == .recording || model.state == .paused
            ) { type in
                model.addMarker(type)
            }
            if !model.customMarkerTypes.isEmpty {
                Menu {
                    ForEach(model.customMarkerTypes, id: \.rawValue) { type in
                        Button(type.label) { model.addMarker(type) }
                    }
                } label: {
                    Label("更多標記", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .disabled(!(model.state == .recording || model.state == .paused))
                .help("自訂標記類型（設定頁管理）")
            }
            if model.markers.isEmpty {
                Text(markerHint)
                    .appFont(.callout)
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
        MarkerInspectorRow(
            marker: marker,
            style: MarkerVisualStyle.style(for: marker, template: model.activeTemplate),
            onJump: nil
        ) {
            model.removeMarker(marker.markerID)
        }
    }

    // MARK: - Toolbar

    private var activeCloudPrivacyMode: PrivacyMode {
        let settings = CloudLLMSettings.load()
        guard settings.enabled else { return .localOnly }
        let textCloud = [AssistFeature.summary, .events, .translation]
            .contains { settings.engine(for: $0) == .cloud }
        let audioCloud = [AssistFeature.offlineTranscript, .liveASR]
            .contains { settings.engine(for: $0) == .cloud }
        switch (textCloud, audioCloud) {
        case (true, true): return .textAndAudioCloud
        case (true, false): return .textCloudAssist
        case (false, true): return .audioCloudASR
        case (false, false): return .localOnly
        }
    }

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
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Text("SessionScribe")
                    .appFont(.headline)
                PrivacyModeBadge(mode: activeCloudPrivacyMode)
            }
        }
        ToolbarItemGroup {
            recordingOptionsMenu
            recordButton
            if model.state == .recording || model.state == .paused {
                Button {
                    Task { await model.stop() }
                } label: {
                    Label("停止", systemImage: "stop.circle")
                }
                .help("停止並保存")
            }

            Button {
                if let session = exportTargetSession {
                    model.export(session: session)
                }
            } label: {
                Label("匯出", systemImage: "square.and.arrow.up")
            }
            .disabled(exportTargetSession == nil)
            .help("匯出目前檢視或錄音中的 session（先選擇要匯出的內容）")

            Button {
                if model.floatingCaptionVisible {
                    dismissWindow(id: "floating-transcript")
                    model.floatingCaptionVisible = false
                } else {
                    openWindow(id: "floating-transcript")
                    model.floatingCaptionVisible = true
                }
            } label: {
                Label("浮動字幕", systemImage: "macwindow.on.rectangle")
            }
            .help("開關置頂的字幕浮層（再點一次關閉）")
        }
        ToolbarItemGroup {
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
                // 清掉側欄選取，主欄回到即時逐字稿頁顯示新場次。
                sidebarSelection = []
                Task { await model.startRecording() }
            } label: {
                Label("錄音", systemImage: "record.circle")
            }
            .help("開始錄音（自動建立新錄音）")
        }
    }

    /// 錄音選項整合選單：轉寫模式與輸入裝置同一入口，減少工具列雜訊。
    private var recordingOptionsMenu: some View {
        Menu {
            Picker("場景模板", selection: $model.selectedTemplateID) {
                ForEach(model.availableTemplates) { template in
                    Text(template.name).tag(template.id)
                }
            }
            .pickerStyle(.menu)
            Picker("錄音模式", selection: $model.transcribeEnabled) {
                Label("錄音＋轉寫", systemImage: "waveform.badge.mic").tag(true)
                Label("純錄音", systemImage: "mic").tag(false)
            }
            .pickerStyle(.inline)
            Picker("輸入裝置", selection: $model.selectedDeviceUID) {
                Text("系統預設輸入").tag(String?.none)
                ForEach(model.inputDevices) { device in
                    Text(device.name).tag(String?.some(device.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("錄音選項", systemImage: "slider.horizontal.3")
        }
        .disabled(model.state == .recording || model.state == .paused)
        .help("錄音模式與輸入裝置（下一場生效）")
    }
}
