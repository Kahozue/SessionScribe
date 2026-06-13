import Foundation
import Testing
@testable import SSCore

struct AnthropicClientTests {
    private func client(transport: @escaping HTTPTransport) -> AnthropicClient {
        AnthropicClient(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant", model: "claude-sonnet-4-6", transport: transport)
    }

    @Test func request_組裝正確() throws {
        let req = try client { _ in (Data(), HTTPURLResponse()) }.makeRequest(system: "S", user: "U")
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "claude-sonnet-4-6")
        #expect(body?["max_tokens"] as? Int == 2048)
        #expect(body?["system"] as? String == "S")
    }

    @Test func 解析回應內容() async throws {
        let json = #"{"content":[{"type":"text","text":"嗨"}]}"#
        let c = client { _ in (Data(json.utf8), HTTPURLResponse(
            url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        #expect(try await c.complete(system: "S", user: "U") == "嗨")
    }
}
