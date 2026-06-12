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

    /// RFC 4180：含逗號、引號或換行的欄位以雙引號包裹，內部引號加倍。
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
