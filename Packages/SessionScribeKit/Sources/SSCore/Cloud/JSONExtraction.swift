import Foundation

/// 從 LLM 回覆抽出第一個完整 JSON 物件或陣列。容忍 ```json 圍欄與前後雜訊，
/// 以括號配對掃描並忽略字串內與跳脫字元，回傳該段子字串。
public enum JSONExtraction {
    public static func firstJSONValue(in text: String) throws -> String {
        let chars = Array(text)
        guard let start = chars.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            throw CloudLLMError.malformedResponse("找不到 JSON")
        }
        let open = chars[start]
        let close: Character = open == "{" ? "}" : "]"
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < chars.count {
            let c = chars[index]
            if escaped {
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "\"" {
                inString.toggle()
            } else if !inString {
                if c == open { depth += 1 }
                else if c == close {
                    depth -= 1
                    if depth == 0 {
                        return String(chars[start...index])
                    }
                }
            }
            index += 1
        }
        throw CloudLLMError.malformedResponse("JSON 括號未閉合")
    }
}
