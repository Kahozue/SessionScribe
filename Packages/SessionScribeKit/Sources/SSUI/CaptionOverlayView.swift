import SwiftUI

/// 字幕浮層（規格 1.2）：取代舊的面板式 FloatingTranscriptView。
/// 一條半透明深色字幕條，兩行滾動（前一句淡、當前句亮），無時間戳、無捲動歷史。
/// 視窗在 app 端以 `.windowStyle(.plain)` 設成無邊框透明，本 view 自己畫圓角底與關閉鈕。
public struct CaptionOverlayView: View {
    let model: RecordingViewModel
    @AppStorage(DisplaySettings.captionFontSizeKey)
    private var captionFontSize = DisplaySettings.defaultCaptionFontSize
    @AppStorage(DisplaySettings.captionOpacityKey)
    private var captionOpacity = DisplaySettings.defaultCaptionOpacity
    @State private var isHovering = false
    @Environment(\.dismissWindow) private var dismissWindow

    public init(model: RecordingViewModel) {
        self.model = model
    }

    public var body: some View {
        let lines = model.captionLines
        ZStack(alignment: .topTrailing) {
            captionBar(lines)
            if isHovering {
                controls
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .padding(10)
        .frame(minWidth: 480, idealWidth: 720, maxWidth: 960)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private func captionBar(_ lines: CaptionLines) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let previous = lines.previous {
                Text(previous)
                    .font(.system(size: captionFontSize * 0.7, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(lines.current ?? "等待語音…")
                .font(.system(size: captionFontSize, weight: .semibold))
                .italic(lines.isVolatile)
                .foregroundStyle(lines.current == nil ? .white.opacity(0.4) : .white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(captionOpacity)))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        .textSelection(.enabled)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                captionFontSize = DisplaySettings.clampedCaptionFontSize(captionFontSize - 2)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .help("縮小字幕字級")
            Button {
                captionFontSize = DisplaySettings.clampedCaptionFontSize(captionFontSize + 2)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .help("放大字幕字級")
            Slider(
                value: $captionOpacity,
                in: DisplaySettings.captionOpacityRange)
                .frame(width: 70)
                .help("字幕底色透明度")
            Button {
                dismissWindow(id: "floating-transcript")
            } label: {
                Image(systemName: "xmark")
            }
            .help("關閉字幕浮層")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}
