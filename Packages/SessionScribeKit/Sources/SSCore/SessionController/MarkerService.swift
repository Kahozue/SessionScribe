import Foundation

/// marker 與 segment 的時間窗動態關聯（規格書第八節）。
/// `nearest_segment_ids` 只是寫入當下的快照；讀取與匯出一律用本函式重算。
public enum MarkerSegmentAssociation {

    /// 預設前後視窗（秒）。
    public static let defaultWindow: Double = 30

    /// 取 marker 時間點前後視窗內重疊的 finalized segments，依開始時間排序。
    public static func nearestSegmentIDs(
        for mediaSeconds: Double,
        in segments: [TranscriptSegment],
        window: Double = defaultWindow
    ) -> [String] {
        segments
            .filter {
                $0.isFinal
                    && $0.endSeconds >= mediaSeconds - window
                    && $0.startSeconds <= mediaSeconds + window
            }
            .sorted { $0.startSeconds < $1.startSeconds }
            .map(\.segmentID)
    }
}

/// 事件標記服務：建立 marker、對齊媒體時間、快照鄰近 segments、立即落盤。
/// 按下標記到落盤之間零確認步驟（規格書第九節）。
public actor MarkerService {

    private let store: SessionStore
    private let sessionID: String
    private var count: Int
    private let now: @Sendable () -> Date

    public init(
        store: SessionStore,
        sessionID: String,
        existingCount: Int = 0,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.sessionID = sessionID
        self.count = existingCount
        self.now = now
    }

    @discardableResult
    public func addMarker(
        type: MarkerType,
        mediaSeconds: Double,
        segments: [TranscriptSegment],
        note: String = ""
    ) async throws -> Marker {
        count += 1
        let marker = Marker(
            markerID: String(format: "m_%04d", count),
            sessionID: sessionID,
            mediaSeconds: mediaSeconds,
            type: type.rawValue,
            label: type.label,
            note: note,
            nearestSegmentIDs: MarkerSegmentAssociation.nearestSegmentIDs(
                for: mediaSeconds, in: segments),
            createdAt: now())
        try await store.appendMarker(marker)
        return marker
    }
}
