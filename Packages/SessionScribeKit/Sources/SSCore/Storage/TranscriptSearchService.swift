import Foundation

/// 一筆搜尋命中：segment 或 marker note。
public struct SearchHit: Equatable, Sendable, Identifiable {
    public let sessionID: String
    public let sessionTitle: String
    public let segmentID: String?
    public let markerID: String?
    public let mediaSeconds: Double
    public let snippet: String

    public var id: String {
        "\(sessionID)/\(segmentID ?? markerID ?? "")"
    }
}

/// 跨逐字稿搜尋（規格 1.1 第 9 項）：不分大小寫，掃描所有 session 的
/// finalized segments 與 marker note。檔案式線性掃描，session 數量級
/// 在百以內無需索引。
public struct TranscriptSearchService: Sendable {
    private let library: SessionLibrary

    public init(library: SessionLibrary) {
        self.library = library
    }

    public func search(_ query: String, limit: Int = 200) throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for session in try library.sessions() {
            let directory = library.directory(for: session.sessionID)
            let segments = (try? JSONLReader.read(
                TranscriptSegment.self,
                from: directory.appending(path: SessionFiles.liveSegments))) ?? []
            for segment in segments
            where segment.text.localizedCaseInsensitiveContains(trimmed) {
                hits.append(
                    SearchHit(
                        sessionID: session.sessionID, sessionTitle: session.title,
                        segmentID: segment.segmentID, markerID: nil,
                        mediaSeconds: segment.startSeconds, snippet: segment.text))
                if hits.count >= limit { return hits }
            }
            let markers = (try? JSONLReader.read(
                Marker.self,
                from: directory.appending(path: SessionFiles.manualMarkers))) ?? []
            for marker in markers
            where marker.note.localizedCaseInsensitiveContains(trimmed) {
                hits.append(
                    SearchHit(
                        sessionID: session.sessionID, sessionTitle: session.title,
                        segmentID: nil, markerID: marker.markerID,
                        mediaSeconds: marker.mediaSeconds, snippet: marker.note))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }
}
