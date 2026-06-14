import Foundation
import Testing
@testable import SSCore

private func stub(
    _ json: String,
    status: Int = 200,
    expectedFields: [String] = [],
    rejectedFields: [String] = [],
    expectedTimeout: TimeInterval? = nil
) -> HTTPTransport {
    { req in
        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        if let expectedTimeout {
            #expect(req.timeoutInterval == expectedTimeout)
        }
        for field in expectedFields {
            #expect(body.contains(field))
        }
        for field in rejectedFields {
            #expect(!body.contains(field))
        }
        let http = HTTPURLResponse(url: req.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), http)
    }
}

struct CloudSTTClientTests {
    @Test func openAI音訊轉寫使用長逾時() throws {
        let client = OpenAISTTClient(baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk", model: "gpt-4o-transcribe-diarize")
        let tmp = FileManager.default.temporaryDirectory.appending(path: "timeout-\(UUID()).m4a")
        try Data([0]).write(to: tmp)
        let req = try client.makeRequest(audioFileURL: tmp, languageCode: "zh")
        #expect(req.timeoutInterval == CloudHTTPTimeouts.audioTranscription)
    }

    @Test func openAI解析verbose_json分段() async throws {
        let body = """
        {"text":"全文","segments":[
          {"start":0.0,"end":1.5,"text":"第一段"},
          {"start":1.5,"end":3.0,"text":"第二段"}]}
        """
        let client = OpenAISTTClient(baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk", model: "whisper-1",
            transport: stub(body, expectedFields: ["verbose_json", "language"]))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "a-\(UUID()).m4a")
        try Data([0, 1, 2]).write(to: tmp)
        let segs = try await client.transcribe(audioFileURL: tmp, languageCode: "zh")
        #expect(segs.count == 2)
        #expect(segs[0].text == "第一段")
        #expect(segs[1].startSeconds == 1.5)
    }

    @Test func openAI解析diarized_json並保留speaker() async throws {
        let body = """
        {"text":"全文","segments":[
          {"start":0.0,"end":1.5,"text":"第一段","speaker":"speaker_0"},
          {"start":1.5,"end":3.0,"text":"第二段","speaker":"speaker_1"}]}
        """
        let client = OpenAISTTClient(baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk", model: "gpt-4o-transcribe-diarize",
            transport: stub(body,
                expectedFields: ["diarized_json", "chunking_strategy", "auto"],
                rejectedFields: ["verbose_json"]))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "diarize-\(UUID()).m4a")
        try Data([0, 1, 2]).write(to: tmp)
        let segs = try await client.transcribe(audioFileURL: tmp, languageCode: "zh")
        #expect(segs.count == 2)
        #expect(segs[0].speaker == "speaker_0")
        #expect(segs[1].text == "第二段")
    }

    @Test func openAI無segments時整段一句() async throws {
        let client = OpenAISTTClient(baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk", model: "whisper-1", transport: stub(#"{"text":"只有全文"}"#))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "b-\(UUID()).m4a")
        try Data([0]).write(to: tmp)
        let segs = try await client.transcribe(audioFileURL: tmp, languageCode: nil)
        #expect(segs.count == 1)
        #expect(segs[0].text == "只有全文")
    }

    @Test func openAIGPT4oTranscribe系列使用json格式() async throws {
        for model in ["gpt-4o-transcribe", "gpt-4o-mini-transcribe"] {
            let client = OpenAISTTClient(baseURL: URL(string: "https://api.example.com/v1")!,
                apiKey: "sk", model: model,
                transport: stub(#"{"text":"只有全文"}"#,
                    expectedFields: ["json"],
                    rejectedFields: ["verbose_json", "diarized_json", "chunking_strategy"]))
            let tmp = FileManager.default.temporaryDirectory
                .appending(path: "\(model)-\(UUID()).m4a")
            try Data([0]).write(to: tmp)
            let segs = try await client.transcribe(audioFileURL: tmp, languageCode: nil)
            #expect(segs.count == 1)
            #expect(segs[0].text == "只有全文")
        }
    }

    @Test func gemini取text為單段() async throws {
        let body = #"{"candidates":[{"content":{"parts":[{"text":"逐字內容"}]}}]}"#
        let client = GeminiSTTClient(baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
            apiKey: "k", model: "gemini-2.0-flash",
            transport: stub(body, expectedTimeout: CloudHTTPTimeouts.audioTranscription))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "c-\(UUID()).m4a")
        try Data([0]).write(to: tmp)
        let segs = try await client.transcribe(audioFileURL: tmp, languageCode: nil)
        #expect(segs.count == 1)
        #expect(segs[0].text == "逐字內容")
    }

    @Test func 非2xx拋http錯誤() async throws {
        let client = OpenAISTTClient(baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk", model: "whisper-1", transport: stub("nope", status: 401))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "d-\(UUID()).m4a")
        try Data([0]).write(to: tmp)
        await #expect(throws: CloudLLMError.self) {
            _ = try await client.transcribe(audioFileURL: tmp, languageCode: nil)
        }
    }
}
