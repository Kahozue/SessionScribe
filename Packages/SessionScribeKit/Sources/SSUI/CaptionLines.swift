import Foundation
import SSCore

/// 字幕浮層的兩行滾動字幕推導（規格 1.2 字幕浮層）：
/// 當前句（有 volatile 顯示 volatile，否則最後一句 finalized）與前一句 finalized。
/// 純函式，與 view 解耦以利測試。
public struct CaptionLines: Equatable, Sendable {
    /// 上行：前一句 finalized（淡、小）。沒有就 nil。
    public var previous: String?
    /// 下行：當前句（亮、大）。完全沒內容時 nil。
    public var current: String?
    /// 當前句是否為未定稿的 volatile。
    public var isVolatile: Bool

    public init(previous: String?, current: String?, isVolatile: Bool) {
        self.previous = previous
        self.current = current
        self.isVolatile = isVolatile
    }

    public var isEmpty: Bool { current == nil }

    /// 由逐字稿與 volatile 尾段推導兩行字幕。
    /// 有非空 volatile：當前句=volatile、前一句=最後一句 finalized。
    /// 無 volatile：當前句=最後一句 finalized、前一句=倒數第二句 finalized。
    public static func derive(
        transcript: [TranscriptSegment], volatileText: String?
    ) -> CaptionLines {
        let trimmed = volatileText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let volatile = trimmed, !volatile.isEmpty {
            return CaptionLines(
                previous: transcript.last?.text,
                current: volatile,
                isVolatile: true)
        }
        let tail = transcript.suffix(2)
        return CaptionLines(
            previous: tail.count == 2 ? tail.first?.text : nil,
            current: transcript.last?.text,
            isVolatile: false)
    }
}
