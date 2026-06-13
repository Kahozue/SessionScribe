import Foundation
import Testing
@testable import SSCore

struct GeminiClientTests {
    private func client(transport: @escaping HTTPTransport) -> GeminiClient {
        GeminiClient(
            baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
            apiKey: "g-key", model: "gemini-2.0-flash", transport: transport)
    }

    @Test func request_組裝正確() throws {
        let req = try client { _ in (Data(), HTTPURLResponse()) }.makeRequest(system: "S", user: "U")
        #expect(req.url?.absoluteString ==
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        let gen = body?["generationConfig"] as? [String: Any]
        #expect(gen?["responseMimeType"] as? String == "application/json")
    }

    @Test func 解析回應內容() async throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"嗨"}]}}]}"#
        let c = client { _ in (Data(json.utf8), HTTPURLResponse(
            url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        #expect(try await c.complete(system: "S", user: "U") == "嗨")
    }
}
