import Foundation

/// 事件草稿產生器（規格書 v0.2）：依 marker 時間戳取前 30 秒、後 90 秒
/// 視窗內的 finalized segments，生成 `needs_review: true` 的事件草稿。
/// AI 不在此介入；草稿只做機械性彙整，判斷留給人工編輯。
public enum EventDraftBuilder {

    public static let defaultWindowBefore: Double = 30
    public static let defaultWindowAfter: Double = 90

    public static func drafts(
        markers: [Marker],
        segments: [TranscriptSegment],
        sessionID: String,
        windowBefore: Double = defaultWindowBefore,
        windowAfter: Double = defaultWindowAfter,
        now: () -> Date = { Date() }
    ) -> [StructuredEvent] {
        let createdAt = Date(
            timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        let sortedMarkers = markers.sorted { $0.mediaSeconds < $1.mediaSeconds }
        return sortedMarkers.enumerated().map { index, marker in
            let windowStart = max(0, marker.mediaSeconds - windowBefore)
            let windowEnd = marker.mediaSeconds + windowAfter
            let related = segments
                .filter {
                    $0.isFinal && $0.endSeconds >= windowStart && $0.startSeconds <= windowEnd
                }
                .sorted { $0.startSeconds < $1.startSeconds }
            return StructuredEvent(
                eventID: String(format: "evt_%04d", index + 1),
                sessionID: sessionID,
                startSeconds: related.first?.startSeconds ?? marker.mediaSeconds,
                endSeconds: related.last?.endSeconds ?? marker.mediaSeconds,
                type: marker.type,
                topic: marker.note,
                content: related.map(\.text).joined(separator: "\n"),
                priority: Self.priority(for: marker.type),
                confidence: "low",
                needsReview: true,
                sourceSegmentIDs: related.map(\.segmentID),
                sourceMarkerIDs: [marker.markerID],
                createdAt: createdAt)
        }
    }

    /// marker type 對應的預設優先程度；自訂 type 取 medium。
    static func priority(for markerType: String) -> String {
        switch markerType {
        case MarkerType.requiredRevision.rawValue: "high"
        case MarkerType.suggestion.rawValue: "low"
        default: "medium"
        }
    }
}
