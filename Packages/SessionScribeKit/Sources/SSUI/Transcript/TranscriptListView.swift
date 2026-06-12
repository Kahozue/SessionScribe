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
            .onChange(of: model.transcript.count) {
                scrollToTail(proxy)
            }
            .onChange(of: model.volatileText) {
                scrollToTail(proxy)
            }
        }
    }

    private func scrollToTail(_ proxy: ScrollViewProxy) {
        withAnimation(.spring(duration: 0.35)) {
            if model.volatileText != nil {
                proxy.scrollTo("volatile-tail", anchor: .bottom)
            } else if let last = model.transcript.last {
                proxy.scrollTo(last.segmentID, anchor: .bottom)
            }
        }
    }
}

/// 一筆 finalized segment 的卡片。
struct SegmentRowView: View {
    let segment: TranscriptSegment
    let inlineMarkers: [Marker]
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(
                    "\(TimeFormatting.hms(segment.startSeconds)) - "
                        + TimeFormatting.hms(segment.endSeconds)
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                ForEach(inlineMarkers) { marker in
                    MarkerChip(marker: marker)
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

    var body: some View {
        Label(marker.label, systemImage: "bookmark.fill")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.yellow.opacity(0.25), in: Capsule())
            .help(
                marker.note.isEmpty
                    ? "\(marker.label)（\(TimeFormatting.hms(marker.mediaSeconds))）"
                    : "\(marker.label)（\(TimeFormatting.hms(marker.mediaSeconds))）：\(marker.note)")
    }
}
