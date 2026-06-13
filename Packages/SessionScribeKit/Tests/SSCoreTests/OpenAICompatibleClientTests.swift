import Foundation
import Testing
@testable import SSCore

struct OpenAICompatibleClientTests {
    private func client(transport: @escaping HTTPTransport) -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-test", model: "gpt-4o-mini", transport: transport)
    }

    @Test func request_組裝正確() throws {
        let req = try OpenAICompatibleClient(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-test", model: "gpt-4o-mini",
            transport: DefaultHTTPTransport.live
        ).makeRequest(system: "S", user: "U")
        #expect(req.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "gpt-4o-mini")
        let messages = body?["messages"] as? [[String: String]]
        #expect(messages?.first?["role"] == "system")
        #expect(messages?.first?["content"] == "S")
        #expect(messages?.last?["content"] == "U")
    }

    @Test func 解析回應內容() async throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"嗨"}}]}"#
        let c = client { _ in (Data(json.utf8), HTTPURLResponse(
            url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        let out = try await c.complete(system: "S", user: "U")
        #expect(out == "嗨")
    }

    @Test func http錯誤狀態轉成錯誤() async {
        let c = client { _ in (Data("nope".utf8), HTTPURLResponse(
            url: URL(string: "https://x")!, statusCode: 401, httpVersion: nil, headerFields: nil)!) }
        await #expect(throws: CloudLLMError.self) {
            _ = try await c.complete(system: "S", user: "U")
        }
    }
}
