import SSCore
import SwiftUI

/// 選單列錄音控制面板（spec 第五節）：與主視窗共享同一個 RecordingViewModel，
/// 所有動作皆為既有 viewModel 方法的薄封裝，不另開資料路徑。
/// 文案極簡，沿用主視窗語彙。
public struct MenuBarControlsView: View {
    @Bindable var model: RecordingViewModel
    @Environment(\.openWindow) private var openWindow

    public init(model: RecordingViewModel) {
        self.model = model
    }

    private var isActive: Bool {
        model.state == .recording || model.state == .paused
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: model.stateDescription.systemImage)
                Text(model.stateDescription.text)
                Spacer()
                if isActive {
                    Text(model.formattedDuration)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .appFont(.callout)

            controlButtons

            if isActive {
                Divider()
                markerButtons
            }

            Divider()

            Button("開啟主視窗") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 240)
        .appTypography()
    }

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 8) {
            switch model.state {
            case .idle, .stopped:
                Button {
                    Task { await model.startRecording() }
                } label: {
                    Label("開始錄音", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            case .recording:
                Button {
                    Task { await model.pause() }
                } label: {
                    Label("暫停", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    Task { await model.stop() }
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            case .paused:
                Button {
                    Task { await model.resume() }
                } label: {
                    Label("繼續", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    Task { await model.stop() }
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 錄音中依當前模板提供四鍵快速標記；同一個 viewModel action，
    /// mediaSeconds 對齊行為與主視窗一致（spec 第五節）。
    private var markerButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快速標記")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(
                    Array(model.activeMarkerTypes.prefix(4).enumerated()),
                    id: \.element.rawValue
                ) { index, type in
                    Button {
                        model.addMarker(type)
                    } label: {
                        Text(type.label)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(MarkerVisualStyle.style(forSlot: index).tint)
                }
            }
            .controlSize(.small)
        }
    }
}

/// 選單列圖示：閒置為 app 符號、錄音中紅色系符號、暫停為暫停符號
/// （SF Symbol，不自繪；spec 第五節）。
public struct MenuBarIconView: View {
    let model: RecordingViewModel

    public init(model: RecordingViewModel) {
        self.model = model
    }

    public var body: some View {
        Image(systemName: symbolName)
    }

    private var symbolName: String {
        switch model.state {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle"
        case .idle, .stopped: "waveform"
        }
    }
}
