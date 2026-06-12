import AppKit
import SSAudio
import SSCore
import SwiftUI

/// App 主視窗的三欄殼層：sidebar（session 列表）、main（即時逐字稿）、
/// inspector（事件標記與狀態）。M2 接上錄音控制；逐字稿與標記待 M3、M4。
public struct RootView: View {
    @State private var model = RecordingViewModel()
    @State private var showInspector = true

    public init() {}

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
        .alert(
            "需要麥克風權限", isPresented: $model.micPermissionDenied
        ) {
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
            Button("在 Finder 顯示") {
                NSWorkspace.shared.activateFileViewerSelecting([model.directory(for: session)])
            }
        }
    }

    // MARK: - Main

    private var transcriptArea: some View {
        ContentUnavailableView {
            Label(
                model.state == .recording ? "錄音中" : "尚未開始記錄",
                systemImage: model.state == .recording ? "record.circle" : "waveform")
        } description: {
            Text(
                model.state == .recording
                    ? "錄音進行中。即時逐字稿功能將於 M4 提供。"
                    : "建立 session 並開始錄音後，即時逐字稿會顯示在這裡。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("事件標記")
                .font(.headline)
            Text("錄音開始後可用 Q、R、S、A 或 Cmd+1 至 Cmd+4 建立標記（M3 提供）。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
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
                // M3：匯出
            } label: {
                Label("匯出", systemImage: "square.and.arrow.up")
            }
            .disabled(true)
            .help("匯出（M3 提供）")
        }
        ToolbarItemGroup {
            StatusBadge(text: "本機模式", systemImage: "lock.shield")
            StatusBadge(
                text: model.stateDescription.text,
                systemImage: model.stateDescription.systemImage)
            if model.state == .recording || model.state == .paused {
                Text(model.formattedDuration)
                    .font(.body.monospacedDigit())
                    .accessibilityLabel("錄音時長 \(model.formattedDuration)")
                LevelMeterView(level: model.level)
            }
        }
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

extension RootView {
    /// 輸入裝置選擇。錄音中不可切換。
    private var inputDevicePicker: some View {
        Picker(
            "輸入裝置",
            selection: Binding(
                get: { model.selectedDeviceUID },
                set: { model.selectedDeviceUID = $0 })
        ) {
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

#Preview {
    RootView()
}
