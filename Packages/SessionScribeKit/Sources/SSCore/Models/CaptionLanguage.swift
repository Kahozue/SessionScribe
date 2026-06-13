import Foundation

/// 字幕支援的語言（規格 1.2 Phase 3）：同時當辨識來源與翻譯目標的選項。
public enum CaptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case zhTW = "zh-TW"
    case english = "en"
    case japanese = "ja"

    public var id: String { rawValue }
    public var code: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhTW: "中文"
        case .english: "英文"
        case .japanese: "日文"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }
    public var language: Locale.Language { Locale.Language(identifier: rawValue) }

    /// 未知 code 退回中文，保證設定值損毀不會崩。
    public static func from(code: String?) -> CaptionLanguage {
        guard let code, let lang = CaptionLanguage(rawValue: code) else { return .zhTW }
        return lang
    }
}
