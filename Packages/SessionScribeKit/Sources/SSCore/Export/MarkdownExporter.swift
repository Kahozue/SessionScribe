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

    /// structured_notes.md 匯出（v0.2）：依模板呈現結構化事件。
    /// 論文口試用「口試紀錄」版型與口試導向欄位標籤，其餘模板用通用版。
    public static func structuredNotes(
        session: Session,
        events: [StructuredEvent]
    ) -> String {
        let isThesis = session.templateID == "thesis_defense"
        let templateName = SessionTemplate.template(for: session.templateID).name
        var lines: [String] = []
        lines.append(isThesis ? "# 口試紀錄" : "# \(session.title)（結構化筆記）")
        lines.append("")
        lines.append("## 基本資訊")
        lines.append("")
        lines.append("- 標題：\(session.title)")
        lines.append("- 模板：\(templateName)")
        lines.append("- 語言：\(session.locale)")
        lines.append("- ASR 引擎：\(session.asrEngine)")
        lines.append("- 建立時間：\(ISO8601DateFormatter().string(from: session.createdAt))")
        lines.append("- 事件數：\(events.count)")
        lines.append("")
        lines.append("## 事件")
        lines.append("")

        if events.isEmpty {
            lines.append("（尚無結構化事件）")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        let sorted = events.sorted { $0.startSeconds < $1.startSeconds }
        for (index, event) in sorted.enumerated() {
            let time =
                "\(TimeFormatting.hms(event.startSeconds)) - "
                + TimeFormatting.hms(event.endSeconds)
            let review = event.needsReview ? "（需複查）" : ""
            let heading = event.topic.isEmpty ? event.type : event.topic
            lines.append("### \(index + 1). \(heading)　[\(time)]\(review)")
            lines.append("")
            lines.append("- 類型：\(event.type)")
            if !event.speaker.isEmpty {
                let role = event.speakerRole.isEmpty ? "" : "（\(event.speakerRole)）"
                lines.append("- 發言者：\(event.speaker)\(role)")
            }
            if !event.content.isEmpty {
                lines.append("- \(isThesis ? "提問內容" : "內容")：\(event.content)")
            }
            if !event.responseSummary.isEmpty {
                lines.append("- 回應摘要：\(event.responseSummary)")
            }
            if !event.actionItem.isEmpty {
                lines.append("- \(isThesis ? "待補" : "待辦")：\(event.actionItem)")
            }
            if !event.priority.isEmpty {
                lines.append("- 優先：\(event.priority)")
            }
            if !event.tags.isEmpty {
                lines.append("- 標籤：\(event.tags.joined(separator: "、"))")
            }
            if !event.sourceSegmentIDs.isEmpty {
                lines.append("- 來源段落：\(event.sourceSegmentIDs.joined(separator: ", "))")
            }
            lines.append("")
        }
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
