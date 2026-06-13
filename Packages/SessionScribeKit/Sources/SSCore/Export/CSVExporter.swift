import Foundation

/// markers.csv 匯出（規格書決議 5）：時間、類型、備註、鄰近 segment 文字。
/// 鄰近文字由時間戳動態重算，不用寫入時的快照。
public enum CSVExporter {

    public static func markersCSV(
        markers: [Marker],
        segments: [TranscriptSegment]
    ) -> String {
        var lines = ["media_seconds,time,type,label,note,nearest_segment_text"]
        for marker in markers.sorted(by: { $0.mediaSeconds < $1.mediaSeconds }) {
            let nearestIDs = MarkerSegmentAssociation.nearestSegmentIDs(
                for: marker.mediaSeconds, in: segments)
            let segmentsByID = Dictionary(
                uniqueKeysWithValues: segments.map { ($0.segmentID, $0) })
            let nearestText = nearestIDs.compactMap { segmentsByID[$0]?.text }
                .joined(separator: " / ")
            let fields = [
                String(marker.mediaSeconds),
                TimeFormatting.hms(marker.mediaSeconds),
                marker.type,
                marker.label,
                marker.note,
                nearestText,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// events.csv 匯出（v0.2）：結構化事件的完整欄位，陣列欄位以分號串接。
    public static func eventsCSV(events: [StructuredEvent]) -> String {
        var lines = [
            "event_id,time_start,time_end,speaker,speaker_role,type,topic,content,"
                + "response_summary,action_item,priority,confidence,needs_review,"
                + "source_segment_ids,source_marker_ids,tags"
        ]
        for event in events.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let fields = [
                event.eventID,
                TimeFormatting.hms(event.startSeconds),
                TimeFormatting.hms(event.endSeconds),
                event.speaker,
                event.speakerRole,
                event.type,
                event.topic,
                event.content,
                event.responseSummary,
                event.actionItem,
                event.priority,
                event.confidence,
                event.needsReview ? "true" : "false",
                event.sourceSegmentIDs.joined(separator: ";"),
                event.sourceMarkerIDs.joined(separator: ";"),
                event.tags.joined(separator: ";"),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// RFC 4180：含逗號、引號或換行的欄位以雙引號包裹，內部引號加倍。
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
