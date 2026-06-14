import Foundation
import Testing
@testable import SSCore

private struct StubClient: CloudLLMClient {
    let reply: String
    func complete(system: String, user: String) async throws -> String { reply }
}

struct CloudTranslatorTests {
    @Test func 翻譯回傳純文字() async throws {
        let t = CloudTranslator(client: StubClient(reply: "Hello"),
            target: Locale.Language(identifier: "en"))
        try await t.prepare(source: Locale.Language(identifier: "zh-TW"),
                            target: Locale.Language(identifier: "en"))
        let out = try await t.translate("你好")
        #expect(out == "Hello")
    }

    @Test func 翻譯解析JSON物件() async throws {
        let t = CloudTranslator(client: StubClient(reply: #"{"translation":"Hello"}"#),
            target: Locale.Language(identifier: "en"))
        let out = try await t.translate("你好")
        #expect(out == "Hello")
    }

    @Test func 去除前後空白與引號雜訊() async throws {
        let t = CloudTranslator(client: StubClient(reply: "  \"Hello\"  \n"),
            target: Locale.Language(identifier: "en"))
        let out = try await t.translate("你好")
        #expect(out == "Hello")
    }

    @Test func 去除CJK引號() async throws {
        let t = CloudTranslator(client: StubClient(reply: "「你好」"),
            target: Locale.Language(identifier: "zh-TW"))
        let out = try await t.translate("hello")
        #expect(out == "你好")
    }
}
