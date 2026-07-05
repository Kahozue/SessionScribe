import SwiftUI

enum AppFontStyle: Sendable {
    case title2
    case title3
    case headline
    case subheadline
    case body
    case callout
    case caption
    case caption2

    var basePointSize: Double {
        switch self {
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .subheadline: 15
        case .body: DisplaySettings.defaultFontSize
        case .callout: 16
        case .caption: 12
        case .caption2: 11
        }
    }

    var defaultWeight: Font.Weight {
        switch self {
        case .headline: .semibold
        default: .regular
        }
    }
}

enum InspectorCardTypography {
    static let summaryBody = AppFontStyle.callout
    static let summarySubheading = AppFontStyle.callout
    static let summaryListItem = AppFontStyle.callout
    static let summarySource = AppFontStyle.callout

    static let eventMetadata = AppFontStyle.callout
    static let eventContent = AppFontStyle.callout
    static let eventSource = AppFontStyle.callout
}

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

    /// 字幕浮層獨立字級與透明度，與主視窗 fontSize 脫鉤（規格 1.2 字幕浮層）。
    public static let captionFontSizeKey = "captionFontSize"
    public static let captionOpacityKey = "captionOpacity"
    public static let defaultCaptionFontSize = 24.0
    public static let captionFontSizeRange = 16.0...48.0
    public static let defaultCaptionOpacity = 0.7
    public static let captionOpacityRange = 0.3...1.0

    /// 辨識語言與即時翻譯（規格 1.2 Phase 3）。辨識語言同時決定 SpeechTranscriber
    /// locale 與翻譯來源；翻譯目標可選，預設中文；翻譯預設關。
    public static let recognitionLanguageKey = "recognitionLanguage"
    public static let translationEnabledKey = "translationEnabled"
    public static let translationTargetKey = "translationTarget"

    /// 雲端整理（v0.3 Text Cloud Assist）。設定本體存 CloudLLMSettings.defaultsKey，
    /// 這裡只放 UI 觀察用的旗標鍵，實際讀寫走 CloudLLMSettings.load/save。
    public static let cloudAssistEnabledKey = "cloudAssistEnabledMirror"

    /// 選單列錄音控制開關（作品集輪，spec 第五節）。預設開；關閉時 MenuBarExtra scene 不建立。
    public static let menuBarControlsEnabledKey = "menuBarControlsEnabled"

    static func clampedCaptionFontSize(_ raw: Double) -> Double {
        min(max(raw, captionFontSizeRange.lowerBound), captionFontSizeRange.upperBound)
    }

    static func clampedCaptionOpacity(_ raw: Double) -> Double {
        min(max(raw, captionOpacityRange.lowerBound), captionOpacityRange.upperBound)
    }

    /// 全域 UI 放大級距。顯式字體另由 fontSize 轉換成點數，這裡保留給系統控制項。
    public static let uiTypeSize: DynamicTypeSize = .xLarge

    static func clampedFontSize(_ raw: Double) -> Double {
        min(max(raw, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    static func scaledFontSize(for style: AppFontStyle, baseFontSize: Double) -> Double {
        let scale = clampedFontSize(baseFontSize) / defaultFontSize
        return style.basePointSize * scale
    }

    static func font(
        _ style: AppFontStyle,
        baseFontSize: Double,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> Font {
        .system(
            size: scaledFontSize(for: style, baseFontSize: baseFontSize),
            weight: weight ?? style.defaultWeight,
            design: design)
    }

    /// "system" 回傳 nil（跟隨系統），"light"、"dark" 強制指定。
    public static func colorScheme(for raw: String) -> ColorScheme? {
        switch raw {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

extension View {
    func appTypography() -> some View {
        modifier(AppTypographyModifier())
    }

    func appFont(
        _ style: AppFontStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default,
        monospacedDigit: Bool = false,
        italic: Bool = false
    ) -> some View {
        modifier(
            AppFontModifier(
                style: style,
                weight: weight,
                design: design,
                monospacedDigit: monospacedDigit,
                italic: italic))
    }
}

private struct AppTypographyModifier: ViewModifier {
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize

    func body(content: Content) -> some View {
        content.font(DisplaySettings.font(.body, baseFontSize: fontSize))
    }
}

private struct AppFontModifier: ViewModifier {
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize

    let style: AppFontStyle
    let weight: Font.Weight?
    let design: Font.Design
    let monospacedDigit: Bool
    let italic: Bool

    private var resolvedFont: Font {
        var font = DisplaySettings.font(
            style,
            baseFontSize: fontSize,
            weight: weight,
            design: design)
        if monospacedDigit {
            font = font.monospacedDigit()
        }
        if italic {
            font = font.italic()
        }
        return font
    }

    func body(content: Content) -> some View {
        content.font(resolvedFont)
    }
}
