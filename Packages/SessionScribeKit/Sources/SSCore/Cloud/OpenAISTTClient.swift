import Foundation

/// OpenAI /audio/transcriptions（multipart/form-data）。
/// 要求 verbose_json 取得 segment 級時間；無 segments 時整段一句。
public struct OpenAISTTClient: CloudSTTClient {
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

    private struct Verbose: Decodable {
        struct Segment: Decodable { let start: Double; let end: Double; let text: String }
        let text: String?
        let segments: [Segment]?
    }

    public func transcribe(audioFileURL: URL, languageCode: String?) async throws -> [CloudSTTSegment] {
        guard !apiKey.isEmpty else { throw CloudLLMError.missingAPIKey }
        let boundary = "ss-\(UUID().uuidString)"
        var req = URLRequest(url: baseURL.appending(path: "audio/transcriptions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audio = try Data(contentsOf: audioFileURL)
        var fields: [(String, String)] = [("model", model), ("response_format", "verbose_json")]
        if let languageCode { fields.append(("language", languageCode)) }
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (data, http) = try await transport(req)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudLLMError.http(status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(Verbose.self, from: data) else {
            throw CloudLLMError.malformedResponse("STT 回應無法解析")
        }
        if let segments = decoded.segments, !segments.isEmpty {
            return segments.map {
                CloudSTTSegment(startSeconds: $0.start, endSeconds: $0.end,
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        let text = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return [CloudSTTSegment(startSeconds: 0, endSeconds: 0, text: text)]
    }
}
