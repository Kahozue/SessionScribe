import Foundation

/// 錄音前的磁碟可用空間檢查（規格書第六節第 10 條）。
/// 空間不足時 UI 警告但不阻擋，由使用者決定是否繼續。
public enum DiskSpace {

    /// 建議最低可用空間。48kHz 16-bit 單聲道約 350MB 一小時，
    /// 取兩小時餘裕：低於此值 UI 應顯示警告。
    public static let recommendedMinimumBytes: Int64 = 1_000_000_000

    /// 指定路徑所在卷的可用空間（重要用途配額）。
    public static func availableBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    public static func isBelowRecommendedMinimum(at url: URL) throws -> Bool {
        try availableBytes(at: url) < recommendedMinimumBytes
    }
}
