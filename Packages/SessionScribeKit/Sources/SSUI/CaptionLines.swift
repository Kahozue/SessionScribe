import Foundation
import SSCore

/// 字幕浮層的兩行滾動字幕推導（規格 1.2）：
/// 當前句（有 volatile 顯示 volatile，否則最後一句 finalized）與前一句 finalized，
/// 各自帶可選譯文（volatile 不翻，故當前句為 volatile 時無譯文）。
/// 純函式，與 view 解耦以利測試。
public struct CaptionLines: Equatable, Sendable {
    /// 上行：前一句 finalized（淡、小）。沒有就 nil。
    public var previous: String?
    public var previousTranslation: String?
    /// 下行：當前句（亮、大）。完全沒內容時 nil。
    public var current: String?
    public var currentTranslation: String?
    /// 當前句是否為未定稿的 volatile。
    public var isVolatile: Bool

    public init(
        previous: String?,
        previousTranslation: String? = nil,
        current: String?,
        currentTranslation: String? = nil,
        isVolatile: Bool
    ) {
        self.previous = previous
        self.previousTranslation = previousTranslation
        self.current = current
        self.currentTranslation = currentTranslation
        self.isVolatile = isVolatile
    }

    public var isEmpty: Bool { current == nil }

    /// 由逐字稿、volatile 尾段與譯文表推導兩行字幕。
    /// 有非空 volatile：當前句=volatile（無譯文）、前一句=最後一句 finalized。
    /// 無 volatile：當前句=最後一句 finalized、前一句=倒數第二句 finalized。
    /// 譯文以 segmentID 從 translations 查；volatile 不翻。
    public static func derive(
        transcript: [TranscriptSegment],
        volatileText: String?,
        translations: [String: String] = [:]
    ) -> CaptionLines {
        let last = transcript.last
        let trimmed = volatileText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let volatile = trimmed, !volatile.isEmpty {
            return CaptionLines(
                previous: last?.text,
                previousTranslation: last.flatMap { translations[$0.segmentID] },
                current: volatile,
                currentTranslation: nil,
                isVolatile: true)
        }
        let secondLast = transcript.dropLast().last
        return CaptionLines(
            previous: secondLast?.text,
            previousTranslation: secondLast.flatMap { translations[$0.segmentID] },
            current: last?.text,
            currentTranslation: last.flatMap { translations[$0.segmentID] },
            isVolatile: false)
    }
}
