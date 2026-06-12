import Foundation

/// 自訂分類（規格 1.1 第 7 項）：可改名、可隱藏、可排序。
public struct SessionCategory: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var hidden: Bool
    public var order: Int

    public init(id: String = UUID().uuidString, name: String, hidden: Bool = false, order: Int) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.order = order
    }
}

/// sessions 根目錄的 library.json：分類定義等程式庫層設定。
public struct LibraryConfig: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var categories: [SessionCategory]

    public init(schemaVersion: Int = SchemaVersion.current, categories: [SessionCategory] = []) {
        self.schemaVersion = schemaVersion
        self.categories = categories
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case categories
    }
}

public enum LibraryConfigFile {
    public static let fileName = "library.json"

    /// 不存在時回傳空設定；讀回的分類依 order 排序。
    public static func read(from root: URL) throws -> LibraryConfig {
        let url = root.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LibraryConfig()
        }
        var config = try SSJSON.decoder.decode(LibraryConfig.self, from: Data(contentsOf: url))
        config.categories.sort { $0.order < $1.order }
        return config
    }

    public static func write(_ config: LibraryConfig, to root: URL) throws {
        let data = try SSJSON.fileEncoder.encode(config)
        try data.write(to: root.appending(path: fileName), options: .atomic)
    }
}
