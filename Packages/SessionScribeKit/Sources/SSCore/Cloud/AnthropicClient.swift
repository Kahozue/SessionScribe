import Foundation

/// Anthropic Messages 格式。
/// 來源：platform.claude.com Messages API（POST /v1/messages、x-api-key、
/// anthropic-version、max_tokens 必填、回應取 content[].text）。
public struct AnthropicClient: CloudLLMClient {
    let baseURL: URL
    let apiKey: String
    let model: String
    let transport: HTTPTransport

    public init(baseURL: URL, apiKey: String, model: String,
                transport: @escaping HTTPTransport = DefaultHTTPTransport.live) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
    }

    private struct Body: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    func makeRequest(system: String, user: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw CloudLLMError.missingAPIKey }
        var req = URLRequest(url: baseURL.appending(path: "v1/messages"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body = Body(model: model, max_tokens: 2048, system: system,
                        messages: [.init(role: "user", content: user)])
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    public func complete(system: String, user: String) async throws -> String {
        let req = try makeRequest(system: system, user: user)
        let (data, http) = try await transport(req)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudLLMError.http(status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw CloudLLMError.malformedResponse("content[].text 缺失")
        }
        return text
    }
}
