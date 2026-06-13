import Foundation

/// Gemini generateContent 格式。
/// 來源：ai.google.dev generateContent（POST {baseURL}/v1beta/models/{model}:generateContent、
/// x-goog-api-key、systemInstruction + contents + generationConfig.responseMimeType、
/// 回應取 candidates[0].content.parts[0].text）。
public struct GeminiClient: CloudLLMClient {
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
        struct Part: Encodable { let text: String }
        struct Content: Encodable { let role: String?; let parts: [Part] }
        struct SystemInstruction: Encodable { let parts: [Part] }
        struct GenerationConfig: Encodable { let responseMimeType: String; let temperature: Double }
        let systemInstruction: SystemInstruction
        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    private struct Response: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable { struct Part: Decodable { let text: String? }; let parts: [Part] }
            let content: Content
        }
        let candidates: [Candidate]
    }

    func makeRequest(system: String, user: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw CloudLLMError.missingAPIKey }
        let url = baseURL.appending(path: "v1beta/models/\(model):generateContent")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body = Body(
            systemInstruction: .init(parts: [.init(text: system)]),
            contents: [.init(role: "user", parts: [.init(text: user)])],
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.2))
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
              let text = decoded.candidates.first?.content.parts.first?.text else {
            throw CloudLLMError.malformedResponse("candidates[0].content.parts[0].text 缺失")
        }
        return text
    }
}
