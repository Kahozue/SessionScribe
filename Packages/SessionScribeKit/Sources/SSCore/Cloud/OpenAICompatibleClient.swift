import Foundation

/// OpenAI Chat Completions 相容（OpenAI、DeepSeek、OpenRouter、本機相容端點等）。
public struct OpenAICompatibleClient: CloudLLMClient {
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
        struct ResponseFormat: Encodable { let type: String }
        let model: String
        let messages: [Message]
        let response_format: ResponseFormat
        let temperature: Double
    }

    private struct Response: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        let choices: [Choice]
    }

    func makeRequest(system: String, user: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw CloudLLMError.missingAPIKey }
        var req = URLRequest(url: baseURL.appending(path: "chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = Body(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            response_format: .init(type: "json_object"),
            temperature: 0.2)
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
              let content = decoded.choices.first?.message.content else {
            throw CloudLLMError.malformedResponse("choices[0].message.content 缺失")
        }
        return content
    }
}
