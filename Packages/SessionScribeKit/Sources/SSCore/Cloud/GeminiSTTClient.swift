import Foundation

/// Gemini generateContent inline audio。回傳純逐字文字，無時間，整段一句。
public struct GeminiSTTClient: CloudSTTClient {
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
        struct InlineData: Encodable { let mimeType: String; let data: String }
        struct Part: Encodable { var text: String?; var inlineData: InlineData? }
        struct Content: Encodable { let role: String; let parts: [Part] }
        let contents: [Content]
    }
    private struct Response: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable { struct Part: Decodable { let text: String? }; let parts: [Part] }
            let content: Content
        }
        let candidates: [Candidate]
    }

    public func transcribe(audioFileURL: URL, languageCode: String?) async throws -> [CloudSTTSegment] {
        guard !apiKey.isEmpty else { throw CloudLLMError.missingAPIKey }
        let audio = try Data(contentsOf: audioFileURL).base64EncodedString()
        let url = baseURL.appending(path: "v1beta/models/\(model):generateContent")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let prompt = "請逐字轉寫這段音訊，只輸出逐字內容，不要加說明或時間戳。"
        let body = Body(contents: [.init(role: "user", parts: [
            .init(text: prompt, inlineData: nil),
            .init(text: nil, inlineData: .init(mimeType: "audio/mp4", data: audio)),
        ])])
        req.httpBody = try JSONEncoder().encode(body)

        let (data, http) = try await transport(req)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudLLMError.http(status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let text = decoded.candidates.first?.content.parts.first?.text else {
            throw CloudLLMError.malformedResponse("STT 回應無法解析")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [CloudSTTSegment(startSeconds: 0, endSeconds: 0, text: trimmed)]
    }
}
