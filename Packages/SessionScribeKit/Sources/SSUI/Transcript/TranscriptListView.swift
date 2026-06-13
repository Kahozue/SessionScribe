import SSCore
import SwiftUI

/// 即時逐字稿列表：finalized 卡片式排版（時間戳徽章、marker 內嵌），
/// volatile 尾段淡色就地替換，新內容自動捲到底，支援多選（選取匯出）。
public struct TranscriptListView: View {
    let model: RecordingViewModel
    @Binding var selection: Set<String>
    var showsSelection = true
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize

    public init(
        model: RecordingViewModel,
        selection: Binding<Set<String>>,
        showsSelection: Bool = true
    ) {
        self.model = model
        self._selection = selection
        self.showsSelection = showsSelection
    }

    public var body: some View {
        ScrollViewReader { proxy in
            List(selection: showsSelection ? $selection : .constant([])) {
                ForEach(model.transcript) { segment in
                    SegmentRowView(
                        segment: segment,
                        inlineMarkers: model.inlineMarkers(for: segment),
                        markerTemplate: model.activeTemplate,
                        fontSize: fontSize
                    )
                    .tag(segment.segmentID)
                }
                if let volatileText = model.volatileText {
                    VolatileRowView(text: volatileText, fontSize: fontSize)
                        .id("volatile-tail")
                }
            }
            .listStyle(.inset)
            // 新段落用輕量動畫；volatile 高頻更新時不加動畫，就地瞬間到底，
            // 避免彈簧動畫互相打斷造成的鈍感（即時感階段，只動呈現層）。
            .onChange(of: model.transcript.count) {
                scrollToTail(proxy, animated: true)
            }
            .onChange(of: model.volatileText) {
                scrollToTail(proxy, animated: false)
            }
        }
    }

    private func scrollToTail(_ proxy: ScrollViewProxy, animated: Bool) {
        let scroll = {
            if model.volatileText != nil {
                proxy.scrollTo("volatile-tail", anchor: .bottom)
            } else if let last = model.transcript.last {
                proxy.scrollTo(last.segmentID, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), scroll)
        } else {
            scroll()
        }
    }
}

/// 一筆 finalized segment 的卡片。
struct SegmentRowView: View {
    let segment: TranscriptSegment
    let inlineMarkers: [Marker]
    let markerTemplate: SessionTemplate
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(
                    "\(TimeFormatting.hms(segment.startSeconds)) - "
                        + TimeFormatting.hms(segment.endSeconds)
                )
                .appFont(.caption, monospacedDigit: true)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                ForEach(inlineMarkers) { marker in
                    MarkerChip(
                        marker: marker,
                        style: MarkerVisualStyle.style(for: marker, template: markerTemplate))
                }
            }
            Text(segment.text)
                .font(.system(size: fontSize))
                .lineSpacing(fontSize * 0.35)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .help(
            "\(TimeFormatting.hms(segment.startSeconds)) 至 "
                + TimeFormatting.hms(segment.endSeconds))
    }
}

/// volatile 尾段：較淡、斜體，視覺上明確表達未定稿。
struct VolatileRowView: View {
    let text: String
    let fontSize: Double

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "ellipsis.bubble")
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: fontSize).italic())
                .foregroundStyle(.secondary)
                .opacity(0.75)
        }
        .padding(.vertical, 3)
        .accessibilityLabel("轉寫中（未定稿）：\(text)")
    }
}

/// marker 的內嵌徽章：圖示加標籤文字，不單靠顏色。
struct MarkerChip: View {
    let marker: Marker
    let style: MarkerVisualStyle

    init(marker: Marker) {
        self.init(marker: marker, style: MarkerVisualStyle.style(for: marker, template: nil))
    }

    init(marker: Marker, style: MarkerVisualStyle) {
        self.marker = marker
        self.style = style
    }

    var body: some View {
        Label(marker.label, systemImage: "bookmark.fill")
            .appFont(.caption2)
            .foregroundStyle(style.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(style.background, in: Capsule())
            .overlay(Capsule().stroke(style.border, lineWidth: 1))
            .help(
                marker.note.isEmpty
                    ? "\(marker.label)（\(TimeFormatting.hms(marker.mediaSeconds))）"
                    : "\(marker.label)（\(TimeFormatting.hms(marker.mediaSeconds))）：\(marker.note)")
    }
}
