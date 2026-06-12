/// 媒體時間秒數的顯示格式化。canonical 格式是秒數（Double），
/// 字串只在 UI 與匯出時產生（規格書決議 1）。
public enum TimeFormatting {

    /// HH:mm:ss，小數秒捨去。
    public static func hms(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
