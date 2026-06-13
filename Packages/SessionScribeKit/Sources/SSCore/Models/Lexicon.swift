import Foundation

/// 名詞表校正規則（規格書 v0.2 第一層：轉寫後的文字替換）。
public struct LexiconRule: Codable, Equatable, Sendable, Identifiable {
    public var from: String
    public var to: String

    public var id: String { from }

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// 名詞表校正：依規則順序做全文字面替換。
/// 套用點在轉寫產生階段（TranscriptionCoordinator 落盤前），
/// 中英夾雜術語的辨識劣化由此緩解。
public enum Lexicon {

    public static func apply(_ text: String, rules: [LexiconRule]) -> String {
        rules.reduce(text) { result, rule in
            guard !rule.from.isEmpty else { return result }
            return result.replacingOccurrences(of: rule.from, with: rule.to)
        }
    }
}
