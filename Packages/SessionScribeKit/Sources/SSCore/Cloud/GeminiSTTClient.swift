import Foundation

/// Gemini generateContent inline audio。Task D 填實作。
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

    public func transcribe(audioFileURL: URL, languageCode: String?) async throws -> [CloudSTTSegment] {
        throw CloudLLMError.malformedResponse("尚未實作")
    }
}
