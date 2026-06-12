import Foundation

/// 跨逐字稿搜尋的查詢紀錄：去重、最近優先、上限十筆，存 UserDefaults。
enum SearchHistory {
    private static let key = "transcriptSearchHistory"
    private static let capacity = 10

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = load().filter { $0 != trimmed }
        history.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(history.prefix(capacity)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
