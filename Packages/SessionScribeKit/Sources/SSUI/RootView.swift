import SwiftUI

/// App 主視窗的三欄殼層：sidebar（session 列表）、main（即時逐字稿）、
/// inspector（事件標記與狀態）。M0 僅佈局與狀態指示，控制項待 M2 起接線。
public struct RootView: View {
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
    }

    private var sidebar: some View {
        List {
            Section("Sessions") {
                Text("尚無 session")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    private var transcriptArea: some View {
        ContentUnavailableView {
            Label("尚未開始記錄", systemImage: "waveform")
        } description: {
            Text("建立 session 並開始錄音後，即時逐字稿會顯示在這裡。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("事件標記")
                .font(.headline)
            Text("錄音開始後可用 Q、R、S、A 或 Cmd+1 至 Cmd+4 建立標記。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                // M2：建立新 session
            } label: {
                Label("新增 Session", systemImage: "plus")
            }
            .disabled(true)
            .help("建立新 session（M2 提供）")
        }
        ToolbarItemGroup {
            Button {
                // M2：開始錄音
            } label: {
                Label("開始", systemImage: "record.circle")
            }
            .disabled(true)

            Button {
                // M2：暫停
            } label: {
                Label("暫停", systemImage: "pause.circle")
            }
            .disabled(true)

            Button {
                // M2：停止並保存
            } label: {
                Label("停止", systemImage: "stop.circle")
            }
            .disabled(true)

            Button {
                // M3：匯出
            } label: {
                Label("匯出", systemImage: "square.and.arrow.up")
            }
            .disabled(true)
        }
        ToolbarItemGroup {
            StatusBadge(text: "本機模式", systemImage: "lock.shield")
            StatusBadge(text: "未錄音", systemImage: "mic.slash")
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

#Preview {
    RootView()
}
