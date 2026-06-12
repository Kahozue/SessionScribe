import Foundation

/// session.json 匯出：metadata、segments、markers 合併為單一 JSON，
/// 方便程式化讀取；jsonl 原檔另以副本保留。
public enum JSONExporter {

    private struct Bundle: Encodable {
        let session: Session
        let segments: [TranscriptSegment]
        let markers: [Marker]
    }

    public static func sessionBundle(
        session: Session,
        segments: [TranscriptSegment],
        markers: [Marker]
    ) throws -> Data {
        try SSJSON.fileEncoder.encode(
            Bundle(session: session, segments: segments, markers: markers))
    }
}
