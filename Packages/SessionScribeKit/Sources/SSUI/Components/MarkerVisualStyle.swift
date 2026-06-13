import SSCore
import SwiftUI

enum MarkerVisualKey: String, Hashable {
    case blue
    case red
    case green
    case purple
    case gray
}

struct MarkerVisualStyle: Equatable {
    let key: MarkerVisualKey

    var tint: Color {
        switch key {
        case .blue: .blue
        case .red: .red
        case .green: .green
        case .purple: .purple
        case .gray: .gray
        }
    }

    var background: Color { tint.opacity(0.14) }
    var border: Color { tint.opacity(0.42) }

    static func style(forSlot index: Int) -> MarkerVisualStyle {
        let keys: [MarkerVisualKey] = [.blue, .red, .green, .purple]
        guard keys.indices.contains(index) else { return MarkerVisualStyle(key: .gray) }
        return MarkerVisualStyle(key: keys[index])
    }

    static func style(for marker: Marker, template: SessionTemplate?) -> MarkerVisualStyle {
        if let template,
            let index = template.markerTypes.firstIndex(where: {
                $0.rawValue == marker.type && $0.label == marker.label
            }) ?? template.markerTypes.firstIndex(where: { $0.rawValue == marker.type })
        {
            return style(forSlot: index)
        }
        return style(forType: marker.type)
    }

    static func style(
        for event: StructuredEvent,
        markersByID: [String: Marker],
        template: SessionTemplate?
    ) -> MarkerVisualStyle {
        for markerID in event.sourceMarkerIDs {
            if let marker = markersByID[markerID] {
                return style(for: marker, template: template)
            }
        }
        return style(forType: event.type)
    }

    private static func style(forType type: String) -> MarkerVisualStyle {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "question", "問題", "疑問", "decision", "決議":
            MarkerVisualStyle(key: .blue)
        case "required_revision", "必改", "follow_up", "追問", "action_item", "待辦", "todo":
            MarkerVisualStyle(key: .red)
        case "suggestion", "建議", "important_point", "重要", "key_point", "重點",
            "quote", "引用", "reference", "參考":
            MarkerVisualStyle(key: .green)
        case "important_answer", "重要回答", "verify", "待查":
            MarkerVisualStyle(key: .purple)
        default:
            MarkerVisualStyle(key: .gray)
        }
    }
}

enum MarkerTimeline {
    static func inlineMarkers(for segment: TranscriptSegment, markers: [Marker]) -> [Marker] {
        markers
            .filter { marker in
                marker.mediaSeconds >= segment.startSeconds
                    && marker.mediaSeconds < segment.endSeconds
            }
            .sorted { $0.mediaSeconds < $1.mediaSeconds }
    }
}

struct MarkerInspectorRow: View {
    let marker: Marker
    let style: MarkerVisualStyle
    let onJump: (() -> Void)?
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.callout)
                    .foregroundStyle(style.tint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("取消標記")
            .accessibilityLabel("取消\(marker.label)標記")

            if let onJump {
                Button(action: onJump) {
                    rowContent
                }
                .buttonStyle(.plain)
                .help("跳到 \(TimeFormatting.hms(marker.mediaSeconds))")
            } else {
                rowContent
            }
        }
        .padding(6)
        .background(style.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(style.border, lineWidth: 1)
        )
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(marker.label)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
