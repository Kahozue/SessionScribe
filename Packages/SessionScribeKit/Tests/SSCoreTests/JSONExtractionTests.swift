import Testing
@testable import SSCore

struct JSONExtractionTests {
    @Test func 純物件原樣回傳() throws {
        let out = try JSONExtraction.firstJSONValue(in: #"{"a":1}"#)
        #expect(out == #"{"a":1}"#)
    }

    @Test func 剝除程式碼圍欄() throws {
        let raw = "```json\n{\"a\":1}\n```"
        let out = try JSONExtraction.firstJSONValue(in: raw)
        #expect(out == #"{"a":1}"#)
    }

    @Test func 前後雜訊取第一個物件() throws {
        let raw = "這是結果：{\"a\":{\"b\":2}} 以上。"
        let out = try JSONExtraction.firstJSONValue(in: raw)
        #expect(out == #"{"a":{"b":2}}"#)
    }

    @Test func 支援陣列() throws {
        let out = try JSONExtraction.firstJSONValue(in: "前綴 [1,2,3] 後綴")
        #expect(out == "[1,2,3]")
    }

    @Test func 忽略字串內的括號() throws {
        let out = try JSONExtraction.firstJSONValue(in: #"{"t":"a}b"}"#)
        #expect(out == #"{"t":"a}b"}"#)
    }

    @Test func 無_JSON_時拋錯() {
        #expect(throws: CloudLLMError.self) {
            _ = try JSONExtraction.firstJSONValue(in: "完全沒有 JSON")
        }
    }
}
