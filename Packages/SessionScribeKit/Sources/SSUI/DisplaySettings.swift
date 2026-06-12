import SwiftUI

/// 顯示設定的 AppStorage 鍵與輔助。主視窗與浮動視窗共用同一組設定。
public enum DisplaySettings {
    public static let fontSizeKey = "transcriptFontSize"
    public static let appearanceKey = "appearanceMode"
    public static let useMockEngineKey = "useMockEngine"

    /// 檢視頁逐字稿顯示模式：歌詞模式或列表模式。
    public static let transcriptModeKey = "detailTranscriptMode"
    public static let lyricsMode = "lyrics"
    public static let listMode = "list"

    public static let defaultFontSize = 14.0
    public static let fontSizeRange = 11.0...28.0

    /// "system" 回傳 nil（跟隨系統），"light"、"dark" 強制指定。
    public static func colorScheme(for raw: String) -> ColorScheme? {
        switch raw {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
