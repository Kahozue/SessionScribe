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

    public static let defaultFontSize = 16.0
    public static let fontSizeRange = 11.0...28.0

    /// 全域 UI（chrome：工具列、側欄、Inspector、設定、按鈕等語意字體）放大級距。
    /// 預設為系統的 .large，提到 .xLarge 等於整體放大約一號；
    /// 逐字稿本文是固定點數、不受此影響，另由 fontSize 控制。
    public static let uiTypeSize: DynamicTypeSize = .xLarge

    /// "system" 回傳 nil（跟隨系統），"light"、"dark" 強制指定。
    public static func colorScheme(for raw: String) -> ColorScheme? {
        switch raw {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
