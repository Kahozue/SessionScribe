import Foundation

/// 雲端語音轉文字的一段結果，時間相對於整段音訊起點。
public struct CloudSTTSegment: Sendable, Equatable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String
    public init(startSeconds: Double, endSeconds: Double, text: String) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }
}

/// 雲端 STT 最小能力：給一個音訊檔（已轉成端點可接受的格式），回傳分段文字。
public protocol CloudSTTClient: Sendable {
    func transcribe(audioFileURL: URL, languageCode: String?) async throws -> [CloudSTTSegment]
}
