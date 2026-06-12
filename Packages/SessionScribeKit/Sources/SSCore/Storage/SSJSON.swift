import Foundation

/// 所有持久化檔案共用的 JSON 編解碼設定。
/// 日期一律 ISO-8601；鍵排序使輸出穩定，利於測試比對與 diff。
public enum SSJSON {

    /// 單行輸出，供 JSONL 逐行寫入使用。
    public static var lineEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// 多行縮排輸出，供 metadata.json 等獨立檔案使用。
    public static var fileEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
