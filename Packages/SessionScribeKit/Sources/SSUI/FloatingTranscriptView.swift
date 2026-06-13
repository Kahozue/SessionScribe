import SSCore
import SwiftUI

/// 浮動即時逐字稿視窗內容（規格 1.1 第 1 項）：
/// always-on-top 由 app 端的 Window scene 設定 `.windowLevel(.floating)`；
/// 顯示完整捲動歷史與 volatile 尾段，字級與主視窗共用設定。
public struct FloatingTranscriptView: View {
    let model: RecordingViewModel
    @State private var selection: Set<String> = []
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize
    @AppStorage(DisplaySettings.appearanceKey)
    private var appearance = "system"

    public init(model: RecordingViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(
                    model.stateDescription.text,
                    systemImage: model.stateDescription.systemImage)
                .font(.callout)
                if model.state == .recording || model.state == .paused {
                    Text(model.formattedDuration)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                fontSizeControls
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            if model.transcript.isEmpty && model.volatileText == nil {
                ContentUnavailableView {
                    Label("等待逐字稿", systemImage: "waveform")
                } description: {
                    Text("開始錄音後即時逐字稿會顯示在這裡。")
                }
            } else {
                TranscriptListView(
                    model: model, selection: $selection, showsSelection: false)
            }
        }
        .frame(minWidth: 320, minHeight: 200)
        .background(.thinMaterial)
        .dynamicTypeSize(DisplaySettings.uiTypeSize)
        .preferredColorScheme(DisplaySettings.colorScheme(for: appearance))
    }

    private var fontSizeControls: some View {
        HStack(spacing: 2) {
            Button {
                fontSize = max(DisplaySettings.fontSizeRange.lowerBound, fontSize - 1)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .help("縮小字級")
            Button {
                fontSize = min(DisplaySettings.fontSizeRange.upperBound, fontSize + 1)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .help("放大字級")
        }
        .buttonStyle(.borderless)
    }
}
