import Foundation

/// 場景模板（規格書 v0.2）：決定四鍵標記的預設語意與結構化筆記的版型。
/// 論文口試只是預設之一，設計不綁死單一場景（規格書第一節）。
public struct SessionTemplate: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// 前四個對應 Q/R/S/A 與 Cmd+1 至 4。
    public let markerTypes: [MarkerType]

    public init(id: String, name: String, markerTypes: [MarkerType]) {
        self.id = id
        self.name = name
        self.markerTypes = markerTypes
    }

    public static let builtIns: [SessionTemplate] = [
        SessionTemplate(
            id: "thesis_defense", name: "論文口試",
            markerTypes: MarkerType.defaults),
        SessionTemplate(
            id: "meeting", name: "會議",
            markerTypes: [
                MarkerType(rawValue: "decision", label: "決議"),
                MarkerType(rawValue: "action_item", label: "待辦"),
                MarkerType(rawValue: "important_point", label: "重要"),
                MarkerType(rawValue: "question", label: "問題"),
            ]),
        SessionTemplate(
            id: "interview", name: "訪談",
            markerTypes: [
                MarkerType(rawValue: "key_point", label: "重點"),
                MarkerType(rawValue: "follow_up", label: "追問"),
                MarkerType(rawValue: "quote", label: "引用"),
                MarkerType(rawValue: "verify", label: "待查"),
            ]),
        SessionTemplate(
            id: "lecture", name: "講座",
            markerTypes: [
                MarkerType(rawValue: "key_point", label: "重點"),
                MarkerType(rawValue: "question", label: "疑問"),
                MarkerType(rawValue: "reference", label: "參考"),
                MarkerType(rawValue: "todo", label: "待辦"),
            ]),
    ]

    /// 未知 id 退回論文口試（既有 metadata 永遠可開）。
    public static func template(for id: String) -> SessionTemplate {
        builtIns.first { $0.id == id } ?? builtIns[0]
    }
}
