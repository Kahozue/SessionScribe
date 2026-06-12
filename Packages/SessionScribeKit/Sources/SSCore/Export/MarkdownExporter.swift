import Foundation

/// transcript.md 匯出：metadata 區塊加依時間排序的 finalized segments，
/// markers 依時間軸內嵌。接受 segment 子集，選取匯出與全量匯出同一條路。
public enum MarkdownExporter {

    public static func transcript(
        session: Session,
        segments: [TranscriptSegment],
        markers: [Marker]
    ) -> String {
        var lines: [String] = []
        lines.append("# \(session.title)")
        lines.append("")
        lines.append("- session_id：\(session.sessionID)")
        lines.append("- 語言：\(session.locale)")
        lines.append("- 引擎：\(session.asrEngine)")
        lines.append("- 建立時間：\(ISO8601DateFormatter().string(from: session.createdAt))")
        lines.append("- segments：\(segments.count)")
        lines.append("- markers：\(markers.count)")
        lines.append("")
        lines.append("## 逐字稿")
        lines.append("")

        let sortedSegments = segments.sorted { $0.startSeconds < $1.startSeconds }
        let sortedMarkers = markers.sorted { $0.mediaSeconds < $1.mediaSeconds }

        if sortedSegments.isEmpty && sortedMarkers.isEmpty {
            lines.append("（無逐字稿內容）")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        var markerIndex = 0
        func appendMarkers(before limit: Double) {
            while markerIndex < sortedMarkers.count,
                sortedMarkers[markerIndex].mediaSeconds < limit
            {
                lines.append(markerLine(sortedMarkers[markerIndex]))
                lines.append("")
                markerIndex += 1
            }
        }

        for segment in sortedSegments {
            appendMarkers(before: segment.startSeconds)
            lines.append(
                "**[\(TimeFormatting.hms(segment.startSeconds)) - "
                    + "\(TimeFormatting.hms(segment.endSeconds))]** \(segment.text)")
            lines.append("")
        }
        appendMarkers(before: .infinity)

        return lines.joined(separator: "\n")
    }

    private static func markerLine(_ marker: Marker) -> String {
        var line = "> **標記｜\(marker.label)** [\(TimeFormatting.hms(marker.mediaSeconds))]"
        if !marker.note.isEmpty {
            line += " \(marker.note)"
        }
        return line
    }
}
