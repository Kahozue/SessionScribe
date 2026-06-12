import AppKit
import SSAudio
import SSCore
import SwiftUI

/// App 主視窗的三欄殼層：sidebar（session 列表）、main（即時逐字稿）、
/// inspector（標記按鈕、事件列表、選取匯出）。
public struct RootView: View {
    @Bindable private var model: RecordingViewModel
    @State private var showInspector = true
    @State private var selection: Set<String> = []
    @FocusState private var transcriptFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize
    @AppStorage(DisplaySettings.appearanceKey)
    private var appearance = "system"
    @AppStorage(DisplaySettings.useMockEngineKey)
    private var useMockEngine = false

    public init(model: RecordingViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            transcriptArea
                .inspector(isPresented: $showInspector) {
                    inspectorPanel
                }
        }
        .toolbar { toolbarContent }
        .navigationTitle("SessionScribe")
        .task { await model.onLaunch() }
        .preferredColorScheme(DisplaySettings.colorScheme(for: appearance))
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
            "匯出",
            isPresented: Binding(
                get: { model.exportMessage != nil },
                set: { if !$0 { model.exportMessage = nil } })
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.exportMessage ?? "")
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section("Sessions") {
                if model.sessions.isEmpty {
                    Text("尚無 session")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
            }
            HStack(spacing: 6) {
                Text(session.sessionID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if session.recovered {
                    Text("已恢復")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .contextMenu {
            Button("匯出…") {
                model.export(session: session)
            }
            Button("在 Finder 顯示") {
                NSWorkspace.shared.activateFileViewerSelecting([model.directory(for: session)])
            }
        }
    }

    // MARK: - Main

    @ViewBuilder
    private var transcriptArea: some View {
        if model.activeSession == nil {
            ContentUnavailableView {
                Label("尚未開始記錄", systemImage: "waveform")
            } description: {
                Text("建立 session 並開始錄音後，即時逐字稿會顯示在這裡。")
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
                        ? "等待第一句轉寫結果。"
                        : "按工具列的開始鈕開始錄音與轉寫。")
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

    /// 單鍵快捷的焦點規則（規格書決議 6）：只在逐字稿區持有焦點時生效，
    /// 文字輸入框聚焦時不會走到這裡。
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

    // MARK: - Inspector

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
                Task { await model.newSession() }
            } label: {
                Label("新增 Session", systemImage: "plus")
            }
            .disabled(model.state == .recording || model.state == .paused)
            .help("建立新 session")

            inputDevicePicker
        }
        ToolbarItemGroup {
            Button {
                Task { await model.start() }
            } label: {
                Label("開始", systemImage: "record.circle")
            }
            .disabled(model.activeSession == nil || model.state != .idle)
            .help("開始錄音")

            if model.state == .paused {
                Button {
                    Task { await model.resume() }
                } label: {
                    Label("繼續", systemImage: "play.circle")
                }
                .help("繼續錄音")
            } else {
                Button {
                    Task { await model.pause() }
                } label: {
                    Label("暫停", systemImage: "pause.circle")
                }
                .disabled(model.state != .recording)
                .help("暫停錄音")
            }

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

            displayOptionsMenu
        }
        ToolbarItemGroup {
            StatusBadge(text: "本機模式", systemImage: "lock.shield")
            StatusBadge(
                text: model.stateDescription.text,
                systemImage: model.stateDescription.systemImage)
            if let transcription = model.transcriptionDescription {
                StatusBadge(text: transcription.text, systemImage: transcription.systemImage)
            }
            if model.state == .recording || model.state == .paused {
                Text(model.formattedDuration)
                    .font(.body.monospacedDigit())
                    .accessibilityLabel("錄音時長 \(model.formattedDuration)")
                LevelMeterView(level: model.level)
            }
        }
    }

    private var displayOptionsMenu: some View {
        Menu {
            Section("字級 \(Int(fontSize)) pt") {
                Button("放大字級") {
                    fontSize = min(DisplaySettings.fontSizeRange.upperBound, fontSize + 1)
                }
                .keyboardShortcut("+", modifiers: .command)
                Button("縮小字級") {
                    fontSize = max(DisplaySettings.fontSizeRange.lowerBound, fontSize - 1)
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("重設字級") {
                    fontSize = DisplaySettings.defaultFontSize
                }
            }
            Section("外觀") {
                Picker("外觀", selection: $appearance) {
                    Text("跟隨系統").tag("system")
                    Text("淺色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("開發") {
                Toggle("使用 Mock 引擎（下一場生效）", isOn: $useMockEngine)
            }
        } label: {
            Label("顯示選項", systemImage: "textformat.size")
        }
        .help("字級、外觀模式與引擎選項")
    }

    /// 輸入裝置選擇。錄音中不可切換。
    private var inputDevicePicker: some View {
        Picker("輸入裝置", selection: $model.selectedDeviceUID) {
            Text("系統預設輸入").tag(String?.none)
            ForEach(model.inputDevices) { device in
                Text(device.name).tag(String?.some(device.id))
            }
        }
        .pickerStyle(.menu)
        .disabled(model.state == .recording || model.state == .paused)
        .help("選擇音訊輸入裝置（建立 session 前選擇）")
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
