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
        VStack(alignment: .leading, spacing: 8) {
            if let previous = lines.previous {
                lineGroup(
                    text: previous, translation: lines.previousTranslation,
                    isPrevious: true, isVolatile: false, placeholder: false)
            }
            lineGroup(
                text: lines.current ?? "等待語音…", translation: lines.currentTranslation,
                isPrevious: false, isVolatile: lines.isVolatile,
                placeholder: lines.current == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(captionOpacity)))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        // 不開 textSelection：否則文字會攔截拖曳，整條字幕就拖不動視窗。
    }

    /// 一行字幕：原文（前一句淡、當前句亮）＋可選譯文（青色調，疊在原文下）。
    private func lineGroup(
        text: String, translation: String?,
        isPrevious: Bool, isVolatile: Bool, placeholder: Bool
    ) -> some View {
        let size = isPrevious ? captionFontSize * 0.7 : captionFontSize
        return VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(size: size, weight: isPrevious ? .regular : .semibold))
                .italic(isVolatile)
                .foregroundStyle(
                    placeholder
                        ? .white.opacity(0.4)
                        : (isPrevious ? .white.opacity(0.55) : .white))
                .lineLimit(isPrevious ? 1 : 2)
                .truncationMode(isPrevious ? .head : .tail)
                .fixedSize(horizontal: false, vertical: true)
            if let translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: size * 0.82, weight: .regular))
                    .foregroundStyle(.cyan.opacity(isPrevious ? 0.5 : 0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                model.floatingCaptionVisible = false
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
