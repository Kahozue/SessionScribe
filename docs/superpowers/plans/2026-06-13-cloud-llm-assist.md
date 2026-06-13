# 雲端 LLM 整理（Text Cloud Assist）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為既有的事件整理與整份摘要兩項操作新增雲端 LLM 可選後端，支援 OpenAI 相容 / Anthropic / Gemini 三種線路格式，base URL / API key / model 可設，單一 app 帶 network.client 並由程式層堅守 Local Only。

**Architecture:** 在 `SSCore/Cloud/` 新增 `CloudLLMClient` 協定與三個格式轉接器（純 Foundation URLSession，transport 可注入以利測試）。雲端操作 `CloudEventOrganizer` / `CloudTranscriptSummarizer` 組 prompt、要求 JSON、容錯解析，重用既有 `EventOrganizer.buildEvent` / `applyOrganized` 與 `TranscriptSummarizer.buildSummary`，產物沿用 `StructuredEvent` / `TranscriptSummary`。`EventOrganizing` / `TranscriptSummarizing` 協定統一本機與雲端，`AssistResolver` 依設定路由並強制 Local Only。設定存 UserDefaults（不含 key）、API key 存 Keychain，UI 新增設定頁「雲端」分頁與非 Local Only 狀態標。

**Tech Stack:** Swift 6、SwiftPM、Foundation URLSession、SwiftUI、Security（Keychain）、Swift Testing（既有測試框架）。

**測試指令慣例：** `swift test --package-path Packages/SessionScribeKit --filter <名稱>`。完整跑 `swift test --package-path Packages/SessionScribeKit`。app 建置 `xcodebuild -scheme SessionScribe -destination 'platform=macOS' build`。

**提交慣例：** 在 `feature/cloud-llm-assist` 分支（已建）。commit 訊息用中文 conventional commits，結尾加 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

---

## 檔案結構

新增（`Packages/SessionScribeKit/Sources/SSCore/Cloud/`）：

- `CloudLLMClient.swift` — `CloudLLMClient` 協定、`HTTPTransport` typealias、`CloudLLMError`、`CloudProviderFormat`。
- `JSONExtraction.swift` — 從 LLM 回覆文字容錯抽出第一個 JSON 物件/陣列。
- `OpenAICompatibleClient.swift` — OpenAI Chat Completions 格式（OpenAI / DeepSeek / 相容端點）。
- `AnthropicClient.swift` — Anthropic Messages 格式。
- `GeminiClient.swift` — Gemini generateContent 格式。
- `CloudEventOrganizer.swift` — 雲端事件整理，conform `EventOrganizing`。
- `CloudTranscriptSummarizer.swift` — 雲端摘要，conform `TranscriptSummarizing`。
- `AssistEngine.swift` — `EventOrganizing` / `TranscriptSummarizing` 協定、`LocalEventOrganizer` / `LocalTranscriptSummarizer`、`AssistResolver`。
- `CloudLLMSettings.swift` — 設定模型（供應商設定清單、active、總開關、引擎）與 UserDefaults 讀寫。
- `KeychainStore.swift` — `KeychainStore` 協定、`SystemKeychainStore`、測試用 `InMemoryKeychainStore`。

修改：

- `Packages/SessionScribeKit/Sources/SSCore/SessionController/EventOrganizer.swift` — `instructions` / `generateInstructions` 改 internal 供雲端重用。
- `Packages/SessionScribeKit/Sources/SSCore/SessionController/TranscriptSummarizer.swift` — `instructions` 改 internal。
- `Packages/SessionScribeKit/Sources/SSUI/DisplaySettings.swift` — 新增雲端相關 AppStorage 鍵。
- `Packages/SessionScribeKit/Sources/SSUI/SettingsView.swift` — 新增「雲端」分頁。
- `Packages/SessionScribeKit/Sources/SSUI/Detail/SessionDetailView.swift` — ViewModel 經 `AssistResolver` 取整理器/摘要器、按鈕標籤反映引擎。
- `Packages/SessionScribeKit/Sources/SSUI/Components/`（新增 `PrivacyModeBadge.swift`）與主錄音畫面 — 非 Local Only 狀態標。
- `SessionScribe/SessionScribe.entitlements` — 加 `com.apple.security.network.client`。
- `docs/DATA_FORMATS.md`、`docs/SPEC.md`、`README`（如有）— 文件。

測試（`Packages/SessionScribeKit/Tests/SSCoreTests/`）：

- `JSONExtractionTests.swift`、`OpenAICompatibleClientTests.swift`、`AnthropicClientTests.swift`、`GeminiClientTests.swift`、`CloudEventOrganizerTests.swift`、`CloudTranscriptSummarizerTests.swift`、`AssistResolverTests.swift`、`CloudLLMSettingsTests.swift`、`KeychainStoreTests.swift`。

---

## Task 1：CloudLLMClient 協定與共用型別

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudLLMClient.swift`

- [ ] **Step 1: 寫檔（無對外行為，型別定義）**

```swift
import Foundation

/// 雲端 LLM 的最小能力：給 system 指示與 user 內容，回傳 assistant 純文字。
/// 三個格式轉接器各自實作；上層的整理/摘要只依賴此協定。
public protocol CloudLLMClient: Sendable {
    func complete(system: String, user: String) async throws -> String
}

/// 可注入的 HTTP 傳輸，預設包 URLSession；測試以 stub 回傳預錄資料，不打真網路。
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public enum CloudProviderFormat: String, Codable, Sendable, CaseIterable {
    case openAICompatible = "openai_compatible"
    case anthropic
    case gemini

    public var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 相容"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        }
    }
}

public enum CloudLLMError: Error, Sendable, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    case malformedResponse(String)
    case transport(String)

    public var userMessage: String {
        switch self {
        case .missingAPIKey: "尚未設定 API key。"
        case .http(let status, _) where status == 401: "API key 無效或未授權（401）。"
        case .http(let status, _) where status == 429: "雲端服務忙線或額度受限（429），請稍後再試。"
        case .http(let status, _): "雲端服務回應錯誤（\(status)）。"
        case .malformedResponse: "雲端回應格式無法解析。"
        case .transport(let detail): "連線失敗：\(detail)"
        }
    }
}

/// 預設傳輸：URLSession，並把非 HTTPURLResponse 視為傳輸錯誤。
public enum DefaultHTTPTransport {
    public static let live: HTTPTransport = { request in
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CloudLLMError.transport("非 HTTP 回應")
            }
            return (data, http)
        } catch let error as CloudLLMError {
            throw error
        } catch {
            throw CloudLLMError.transport(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: 建置確認編譯通過**

Run: `swift build --package-path Packages/SessionScribeKit`
Expected: Build complete（無錯誤）

- [ ] **Step 3: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudLLMClient.swift
git commit -m "feat: CloudLLMClient 協定與共用型別（雲端整理）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2：容錯 JSON 抽取

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/JSONExtraction.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/JSONExtractionTests.swift`

- [ ] **Step 1: 寫失敗測試**

```swift
import Testing
@testable import SSCore

struct JSONExtractionTests {
    @Test func 純物件原樣回傳() throws {
        let out = try JSONExtraction.firstJSONValue(in: #"{"a":1}"#)
        #expect(out == #"{"a":1}"#)
    }

    @Test func 剝除程式碼圍欄() throws {
        let raw = "```json\n{\"a\":1}\n```"
        let out = try JSONExtraction.firstJSONValue(in: raw)
        #expect(out == #"{"a":1}"#)
    }

    @Test func 前後雜訊取第一個物件() throws {
        let raw = "這是結果：{\"a\":{\"b\":2}} 以上。"
        let out = try JSONExtraction.firstJSONValue(in: raw)
        #expect(out == #"{"a":{"b":2}}"#)
    }

    @Test func 支援陣列() throws {
        let out = try JSONExtraction.firstJSONValue(in: "前綴 [1,2,3] 後綴")
        #expect(out == "[1,2,3]")
    }

    @Test func 忽略字串內的括號() throws {
        let out = try JSONExtraction.firstJSONValue(in: #"{"t":"a}b"}"#)
        #expect(out == #"{"t":"a}b"}"#)
    }

    @Test func 無 JSON 時拋錯() {
        #expect(throws: CloudLLMError.self) {
            _ = try JSONExtraction.firstJSONValue(in: "完全沒有 JSON")
        }
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter JSONExtractionTests`
Expected: FAIL（`JSONExtraction` 未定義）

- [ ] **Step 3: 實作**

```swift
import Foundation

/// 從 LLM 回覆抽出第一個完整 JSON 物件或陣列。容忍 ```json 圍欄與前後雜訊，
/// 以括號配對掃描並忽略字串內與跳脫字元，回傳該段子字串。
public enum JSONExtraction {
    public static func firstJSONValue(in text: String) throws -> String {
        let chars = Array(text)
        guard let start = chars.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            throw CloudLLMError.malformedResponse("找不到 JSON")
        }
        let open = chars[start]
        let close: Character = open == "{" ? "}" : "]"
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < chars.count {
            let c = chars[index]
            if escaped {
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "\"" {
                inString.toggle()
            } else if !inString {
                if c == open { depth += 1 }
                else if c == close {
                    depth -= 1
                    if depth == 0 {
                        return String(chars[start...index])
                    }
                }
            }
            index += 1
        }
        throw CloudLLMError.malformedResponse("JSON 括號未閉合")
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter JSONExtractionTests`
Expected: PASS（6 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/JSONExtraction.swift Packages/SessionScribeKit/Tests/SSCoreTests/JSONExtractionTests.swift
git commit -m "feat: 容錯 JSON 抽取（雲端回應解析）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3：OpenAICompatibleClient

對照官方文件（source-driven-development）：OpenAI Chat Completions，`POST {baseURL}/chat/completions`，`Authorization: Bearer {key}`，body 含 `messages` 與 `response_format:{type:"json_object"}`，回應取 `choices[0].message.content`。baseURL 預期含版本段（如 `https://api.openai.com/v1`、`https://api.deepseek.com/v1`）。

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/OpenAICompatibleClient.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/OpenAICompatibleClientTests.swift`

- [ ] **Step 1: 寫失敗測試**

```swift
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
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter OpenAICompatibleClientTests`
Expected: FAIL（`OpenAICompatibleClient` 未定義）

- [ ] **Step 3: 實作**

```swift
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
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter OpenAICompatibleClientTests`
Expected: PASS（3 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/OpenAICompatibleClient.swift Packages/SessionScribeKit/Tests/SSCoreTests/OpenAICompatibleClientTests.swift
git commit -m "feat: OpenAI 相容雲端轉接器

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4：AnthropicClient

對照 claude-api 技能與官方文件：`POST {baseURL}/v1/messages`，headers `x-api-key`、`anthropic-version: 2023-06-01`，body 含 `model`、`max_tokens`（必填）、`system`、`messages`，回應取 `content[0].text`。baseURL 預期為 `https://api.anthropic.com`（不含版本段）。實作時以 claude-api 技能確認當前 model id 與 `anthropic-version`。

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/AnthropicClient.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/AnthropicClientTests.swift`

- [ ] **Step 1: 寫失敗測試**

```swift
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
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter AnthropicClientTests`
Expected: FAIL（`AnthropicClient` 未定義）

- [ ] **Step 3: 實作**

```swift
import Foundation

/// Anthropic Messages 格式。
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
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter AnthropicClientTests`
Expected: PASS（2 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/AnthropicClient.swift Packages/SessionScribeKit/Tests/SSCoreTests/AnthropicClientTests.swift
git commit -m "feat: Anthropic Messages 雲端轉接器

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5：GeminiClient

對照官方文件：`POST {baseURL}/v1beta/models/{model}:generateContent`，header `x-goog-api-key: {key}`，body 含 `systemInstruction`、`contents`、`generationConfig.responseMimeType: "application/json"`，回應取 `candidates[0].content.parts[0].text`。baseURL 預期為 `https://generativelanguage.googleapis.com`。

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/GeminiClient.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/GeminiClientTests.swift`

- [ ] **Step 1: 寫失敗測試**

```swift
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
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter GeminiClientTests`
Expected: FAIL（`GeminiClient` 未定義）

- [ ] **Step 3: 實作**

```swift
import Foundation

/// Gemini generateContent 格式。
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
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter GeminiClientTests`
Expected: PASS（2 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/GeminiClient.swift Packages/SessionScribeKit/Tests/SSCoreTests/GeminiClientTests.swift
git commit -m "feat: Gemini generateContent 雲端轉接器

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6：本機指示改 internal 供雲端重用

**Files:**
- Modify: `Packages/SessionScribeKit/Sources/SSCore/SessionController/EventOrganizer.swift`
- Modify: `Packages/SessionScribeKit/Sources/SSCore/SessionController/TranscriptSummarizer.swift`

- [ ] **Step 1: 改存取層級**

`EventOrganizer.swift`：把 `private static let instructions` 與 `private static let generateInstructions` 的 `private` 移除（改 internal）。
`TranscriptSummarizer.swift`：把 `private static let instructions` 的 `private` 移除（改 internal）。

不改任何文字內容與行為，只放寬同模組可見性。

- [ ] **Step 2: 建置確認**

Run: `swift build --package-path Packages/SessionScribeKit`
Expected: Build complete

- [ ] **Step 3: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/SessionController/EventOrganizer.swift Packages/SessionScribeKit/Sources/SSCore/SessionController/TranscriptSummarizer.swift
git commit -m "refactor: 本機 LLM 指示改 internal 供雲端路徑重用

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7：EventOrganizing / TranscriptSummarizing 協定與本機包裝

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/AssistEngine.swift`

- [ ] **Step 1: 寫協定與本機包裝**

```swift
import Foundation

/// 整理器抽象：本機（FoundationModels）與雲端共用同一介面，供 UI 路由。
public protocol EventOrganizing: Sendable {
    func organize(_ events: [StructuredEvent], locale: Locale,
                  progress: @Sendable (Double) -> Void) async throws -> [StructuredEvent]
    func generateEvents(from segments: [TranscriptSegment], sessionID: String,
                        locale: Locale) async throws -> [StructuredEvent]
}

public protocol TranscriptSummarizing: Sendable {
    func summarize(from segments: [TranscriptSegment], sessionID: String,
                   locale: Locale) async throws -> TranscriptSummary
}

/// 本機包裝：轉呼既有 EventOrganizer 靜態方法。
public struct LocalEventOrganizer: EventOrganizing {
    public init() {}
    public func organize(_ events: [StructuredEvent], locale: Locale,
                         progress: @Sendable (Double) -> Void) async throws -> [StructuredEvent] {
        try await EventOrganizer.organize(events, locale: locale, progress: progress)
    }
    public func generateEvents(from segments: [TranscriptSegment], sessionID: String,
                               locale: Locale) async throws -> [StructuredEvent] {
        try await EventOrganizer.generateEvents(from: segments, sessionID: sessionID, locale: locale)
    }
}

public struct LocalTranscriptSummarizer: TranscriptSummarizing {
    public init() {}
    public func summarize(from segments: [TranscriptSegment], sessionID: String,
                          locale: Locale) async throws -> TranscriptSummary {
        try await TranscriptSummarizer.generateSummary(from: segments, sessionID: sessionID, locale: locale)
    }
}
```

- [ ] **Step 2: 建置確認**

Run: `swift build --package-path Packages/SessionScribeKit`
Expected: Build complete

- [ ] **Step 3: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/AssistEngine.swift
git commit -m "feat: 整理器/摘要器協定與本機包裝

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8：CloudEventOrganizer

組 prompt（重用 `EventOrganizer.instructions` / `generateInstructions`）、要求 JSON、容錯解析，重用 `EventOrganizer.applyOrganized` / `buildEvent` 保留可靠性邏輯。

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudEventOrganizer.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/CloudEventOrganizerTests.swift`

- [ ] **Step 1: 寫失敗測試（用 MockCloudLLMClient）**

```swift
import Foundation
import Testing
@testable import SSCore

private struct MockCloudLLMClient: CloudLLMClient {
    let reply: String
    func complete(system: String, user: String) async throws -> String { reply }
}

struct CloudEventOrganizerTests {
    private func seg(_ id: String, _ s: Double, _ e: Double, _ t: String) -> TranscriptSegment {
        TranscriptSegment(segmentID: id, startSeconds: s, endSeconds: e, text: t, isFinal: true)
    }

    @Test func organize_補語意欄位且強制needsReview() async throws {
        let reply = #"{"topic":"研究貢獻","type":"問題","priority":"high","speakerRole":"口委","responseSummary":"請補實驗","actionItem":"補對照組","tags":["實驗"]}"#
        let event = StructuredEvent(
            eventID: "evt_0001", sessionID: "s1", startSeconds: 0, endSeconds: 10,
            speakerRole: "", type: "event", topic: "", content: "原始逐字稿內容",
            responseSummary: "", actionItem: "", priority: "medium", confidence: "low",
            needsReview: true, sourceSegmentIDs: ["seg1"], sourceMarkerIDs: ["m1"], tags: [],
            createdAt: Date(timeIntervalSince1970: 0))
        let organizer = CloudEventOrganizer(client: MockCloudLLMClient(reply: reply))
        let out = try await organizer.organize([event], locale: Locale(identifier: "zh_TW")) { _ in }
        #expect(out.count == 1)
        #expect(out[0].topic == "研究貢獻")
        #expect(out[0].priority == "high")
        #expect(out[0].content == "原始逐字稿內容")   // 不覆蓋 raw
        #expect(out[0].sourceMarkerIDs == ["m1"])     // 來源保留
        #expect(out[0].needsReview == true)
    }

    @Test func generateEvents_從逐字稿生成且content取原始文字() async throws {
        let reply = #"{"events":[{"topic":"開場","type":"重要","priority":"low","speakerRole":"學生","responseSummary":"自我介紹","actionItem":"","tags":["開場"],"startSeconds":0,"endSeconds":5}]}"#
        let segs = [seg("seg1", 0, 5, "大家好我是報告人")]
        let organizer = CloudEventOrganizer(client: MockCloudLLMClient(reply: reply))
        let out = try await organizer.generateEvents(from: segs, sessionID: "s1",
            locale: Locale(identifier: "zh_TW"))
        #expect(out.count == 1)
        #expect(out[0].content == "大家好我是報告人")
        #expect(out[0].sourceSegmentIDs == ["seg1"])
        #expect(out[0].needsReview == true)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter CloudEventOrganizerTests`
Expected: FAIL（`CloudEventOrganizer` 未定義）

- [ ] **Step 3: 實作**

```swift
import Foundation

/// 雲端事件整理：行為對齊本機 EventOrganizer，差別只在用雲端 LLM 取結構化 JSON。
/// 重用 EventOrganizer 的 instructions 與 applyOrganized/buildEvent，確保可靠性邏輯一致。
public struct CloudEventOrganizer: EventOrganizing {
    let client: CloudLLMClient
    public init(client: CloudLLMClient) { self.client = client }

    private struct OrganizedJSON: Decodable {
        var topic: String?; var type: String?; var priority: String?
        var speakerRole: String?; var responseSummary: String?; var actionItem: String?
        var tags: [String]?
    }
    private struct GeneratedJSON: Decodable { var events: [GeneratedEventJSON] }
    private struct GeneratedEventJSON: Decodable {
        var topic: String?; var type: String?; var priority: String?
        var speakerRole: String?; var responseSummary: String?; var actionItem: String?
        var tags: [String]?; var startSeconds: Double?; var endSeconds: Double?
    }

    private static let organizeSchema = """

        請只輸出 JSON 物件，鍵為：topic、type、priority（high/medium/low）、speakerRole、
        responseSummary、actionItem、tags（字串陣列）。無法判斷的欄位給空字串或空陣列。
        """
    private static let generateSchema = """

        請只輸出 JSON 物件 {"events":[...]}，每個 event 的鍵為：topic、type、
        priority（high/medium/low）、speakerRole、responseSummary、actionItem、
        tags（字串陣列）、startSeconds（整數秒）、endSeconds（整數秒）。
        """

    public func organize(_ events: [StructuredEvent], locale: Locale,
                         progress: @Sendable (Double) -> Void) async throws -> [StructuredEvent] {
        var result: [StructuredEvent] = []
        result.reserveCapacity(events.count)
        for (index, event) in events.enumerated() {
            let prompt = "以下是某個標記前後的逐字稿片段，請依指示整理成結構化欄位：\n\n\(event.content)"
            let reply = try await client.complete(
                system: EventOrganizer.instructions + Self.organizeSchema, user: prompt)
            let json = try JSONExtraction.firstJSONValue(in: reply)
            let fields = try Self.decode(OrganizedJSON.self, from: json)
            result.append(EventOrganizer.applyOrganized(
                topic: fields.topic ?? "", type: fields.type ?? "", priority: fields.priority ?? "",
                speakerRole: fields.speakerRole ?? "", responseSummary: fields.responseSummary ?? "",
                actionItem: fields.actionItem ?? "", tags: fields.tags ?? [], to: event))
            progress(Double(index + 1) / Double(max(events.count, 1)))
        }
        return result
    }

    public func generateEvents(from segments: [TranscriptSegment], sessionID: String,
                               locale: Locale) async throws -> [StructuredEvent] {
        let finals = segments.filter(\.isFinal).sorted { $0.startSeconds < $1.startSeconds }
        guard !finals.isEmpty else { return [] }
        let transcript = finals
            .map { "[\(Int($0.startSeconds))-\(Int($0.endSeconds))] \($0.text)" }
            .joined(separator: "\n")
        let prompt = "以下是一段帶秒數區間的逐字稿，請切分成數個事件並整理：\n\n\(transcript)"
        let reply = try await client.complete(
            system: EventOrganizer.generateInstructions + Self.generateSchema, user: prompt)
        let json = try JSONExtraction.firstJSONValue(in: reply)
        let decoded = try Self.decode(GeneratedJSON.self, from: json)
        let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        return decoded.events.enumerated().map { index, gen in
            EventOrganizer.buildEvent(
                index: index, topic: gen.topic ?? "", type: gen.type ?? "",
                priority: gen.priority ?? "", speakerRole: gen.speakerRole ?? "",
                responseSummary: gen.responseSummary ?? "", actionItem: gen.actionItem ?? "",
                tags: gen.tags ?? [], startSeconds: gen.startSeconds ?? 0,
                endSeconds: gen.endSeconds ?? 0, segments: finals,
                sessionID: sessionID, createdAt: createdAt)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw CloudLLMError.malformedResponse("JSON 欄位無法對應")
        }
        return value
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter CloudEventOrganizerTests`
Expected: PASS（2 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudEventOrganizer.swift Packages/SessionScribeKit/Tests/SSCoreTests/CloudEventOrganizerTests.swift
git commit -m "feat: 雲端事件整理（重用本機可靠性邏輯）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9：CloudTranscriptSummarizer

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudTranscriptSummarizer.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/CloudTranscriptSummarizerTests.swift`

- [ ] **Step 1: 寫失敗測試**

```swift
import Foundation
import Testing
@testable import SSCore

private struct MockSummaryClient: CloudLLMClient {
    let reply: String
    func complete(system: String, user: String) async throws -> String { reply }
}

struct CloudTranscriptSummarizerTests {
    @Test func summarize_組出摘要且來源涵蓋finalized() async throws {
        let reply = #"{"content":"本場討論研究方法與貢獻","keyPoints":["方法","貢獻"],"actionItems":["補實驗"]}"#
        let segs = [
            TranscriptSegment(segmentID: "seg1", startSeconds: 0, endSeconds: 5, text: "方法說明", isFinal: true),
            TranscriptSegment(segmentID: "seg2", startSeconds: 5, endSeconds: 9, text: "貢獻說明", isFinal: true),
        ]
        let s = try await CloudTranscriptSummarizer(client: MockSummaryClient(reply: reply))
            .summarize(from: segs, sessionID: "s1", locale: Locale(identifier: "zh_TW"))
        #expect(s.content == "本場討論研究方法與貢獻")
        #expect(s.keyPoints == ["方法", "貢獻"])
        #expect(s.actionItems == ["補實驗"])
        #expect(s.sourceSegmentIDs == ["seg1", "seg2"])
    }

    @Test func 空逐字稿回傳空摘要() async throws {
        let s = try await CloudTranscriptSummarizer(client: MockSummaryClient(reply: "{}"))
            .summarize(from: [], sessionID: "s1", locale: Locale(identifier: "zh_TW"))
        #expect(s.content.isEmpty)
        #expect(s.sourceSegmentIDs.isEmpty)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter CloudTranscriptSummarizerTests`
Expected: FAIL（`CloudTranscriptSummarizer` 未定義）

- [ ] **Step 3: 實作**

```swift
import Foundation

/// 雲端整份摘要：對齊本機 TranscriptSummarizer，重用 buildSummary 收斂行為。
public struct CloudTranscriptSummarizer: TranscriptSummarizing {
    let client: CloudLLMClient
    public init(client: CloudLLMClient) { self.client = client }

    private struct SummaryJSON: Decodable {
        var content: String?; var keyPoints: [String]?; var actionItems: [String]?
    }

    private static let schema = """

        請只輸出 JSON 物件，鍵為：content（整份摘要字串）、keyPoints（重點字串陣列）、
        actionItems（待辦字串陣列；沒有就空陣列）。全部繁體中文。
        """

    public func summarize(from segments: [TranscriptSegment], sessionID: String,
                          locale: Locale) async throws -> TranscriptSummary {
        let finals = segments.filter(\.isFinal).sorted { $0.startSeconds < $1.startSeconds }
        let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        guard !finals.isEmpty else {
            return TranscriptSummarizer.buildSummary(
                content: "", keyPoints: [], actionItems: [], segments: finals,
                sessionID: sessionID, createdAt: createdAt)
        }
        let transcript = finals
            .map { "[\(Int($0.startSeconds))-\(Int($0.endSeconds))] \($0.text)" }
            .joined(separator: "\n")
        let prompt = """
            以下是 locale \(locale.identifier) 的完整逐字稿，行首為錄音秒數區間。
            請整理整份逐字稿的摘要、重點與待辦：

            \(transcript)
            """
        let reply = try await client.complete(
            system: TranscriptSummarizer.instructions + Self.schema, user: prompt)
        let json = try JSONExtraction.firstJSONValue(in: reply)
        guard let data = json.data(using: .utf8),
              let fields = try? JSONDecoder().decode(SummaryJSON.self, from: data) else {
            throw CloudLLMError.malformedResponse("摘要 JSON 無法對應")
        }
        return TranscriptSummarizer.buildSummary(
            content: fields.content ?? "", keyPoints: fields.keyPoints ?? [],
            actionItems: fields.actionItems ?? [], segments: finals,
            sessionID: sessionID, createdAt: createdAt)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter CloudTranscriptSummarizerTests`
Expected: PASS（2 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudTranscriptSummarizer.swift Packages/SessionScribeKit/Tests/SSCoreTests/CloudTranscriptSummarizerTests.swift
git commit -m "feat: 雲端整份摘要

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10：KeychainStore

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/KeychainStore.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/KeychainStoreTests.swift`

- [ ] **Step 1: 寫失敗測試（針對 InMemory 假實作驗語意）**

```swift
import Testing
@testable import SSCore

struct KeychainStoreTests {
    @Test func 存取與刪除() throws {
        let store = InMemoryKeychainStore()
        try store.setSecret("sk-1", account: "openai")
        #expect(try store.secret(account: "openai") == "sk-1")
        try store.setSecret("sk-2", account: "openai")    // 覆寫
        #expect(try store.secret(account: "openai") == "sk-2")
        try store.deleteSecret(account: "openai")
        #expect(try store.secret(account: "openai") == nil)
    }

    @Test func 未設定回傳nil() throws {
        #expect(try InMemoryKeychainStore().secret(account: "none") == nil)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter KeychainStoreTests`
Expected: FAIL（型別未定義）

- [ ] **Step 3: 實作**

```swift
import Foundation
import Security

/// API key 安全儲存抽象，便於測試注入。account 用供應商設定 id。
public protocol KeychainStore: Sendable {
    func secret(account: String) throws -> String?
    func setSecret(_ value: String, account: String) throws
    func deleteSecret(account: String) throws
}

/// 系統 Keychain 實作（kSecClassGenericPassword）。
public struct SystemKeychainStore: KeychainStore {
    let service: String
    public init(service: String = "com.sessionscribe.cloud-llm") { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func secret(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CloudLLMError.transport("Keychain 讀取失敗（\(status)）")
        }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String, account: String) throws {
        try deleteSecret(account: account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CloudLLMError.transport("Keychain 寫入失敗（\(status)）")
        }
    }

    public func deleteSecret(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CloudLLMError.transport("Keychain 刪除失敗（\(status)）")
        }
    }
}

/// 測試用：行程內保存，不碰系統 Keychain。
public final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    public init() {}
    public func secret(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }; return store[account]
    }
    public func setSecret(_ value: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; store[account] = value
    }
    public func deleteSecret(account: String) throws {
        lock.lock(); defer { lock.unlock() }; store[account] = nil
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter KeychainStoreTests`
Expected: PASS（2 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/KeychainStore.swift Packages/SessionScribeKit/Tests/SSCoreTests/KeychainStoreTests.swift
git commit -m "feat: API key Keychain 儲存抽象

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11：CloudLLMSettings 設定模型

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudLLMSettings.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/CloudLLMSettingsTests.swift`

- [ ] **Step 1: 寫失敗測試**

```swift
import Foundation
import Testing
@testable import SSCore

struct CloudLLMSettingsTests {
    @Test func 預設關閉且引擎為本機() {
        let s = CloudLLMSettings()
        #expect(s.enabled == false)
        #expect(s.engine == .local)
        #expect(s.providers.isEmpty)
        #expect(s.activeProvider == nil)
    }

    @Test func 編碼解碼往返() throws {
        var s = CloudLLMSettings()
        let p = CloudProviderConfig(id: "p1", format: .anthropic, displayName: "Claude",
            baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-6")
        s.providers = [p]
        s.activeProviderID = "p1"
        s.enabled = true
        s.engine = .cloud
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(CloudLLMSettings.self, from: data)
        #expect(back == s)
        #expect(back.activeProvider?.format == .anthropic)
    }

    @Test func 預設供應商樣板齊四家() {
        let defaults = CloudProviderConfig.builtInTemplates
        #expect(defaults.map(\.displayName).contains("OpenAI"))
        #expect(defaults.map(\.displayName).contains("DeepSeek"))
        #expect(defaults.map(\.displayName).contains("Anthropic"))
        #expect(defaults.map(\.displayName).contains("Gemini"))
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter CloudLLMSettingsTests`
Expected: FAIL（型別未定義）

- [ ] **Step 3: 實作**

```swift
import Foundation

public enum AssistEngineKind: String, Codable, Sendable, CaseIterable {
    case local, cloud
}

/// 單一供應商設定（不含 API key；key 存 Keychain，以 id 為 account）。
public struct CloudProviderConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var format: CloudProviderFormat
    public var displayName: String
    public var baseURL: String
    public var model: String

    public init(id: String, format: CloudProviderFormat, displayName: String,
                baseURL: String, model: String) {
        self.id = id; self.format = format; self.displayName = displayName
        self.baseURL = baseURL; self.model = model
    }

    /// 設定頁「新增」用的常見供應商樣板（使用者仍可改 base URL/model）。
    public static let builtInTemplates: [CloudProviderConfig] = [
        .init(id: "openai", format: .openAICompatible, displayName: "OpenAI",
              baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        .init(id: "deepseek", format: .openAICompatible, displayName: "DeepSeek",
              baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        .init(id: "anthropic", format: .anthropic, displayName: "Anthropic",
              baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-6"),
        .init(id: "gemini", format: .gemini, displayName: "Gemini",
              baseURL: "https://generativelanguage.googleapis.com", model: "gemini-2.0-flash"),
    ]
}

public struct CloudLLMSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var engine: AssistEngineKind
    public var providers: [CloudProviderConfig]
    public var activeProviderID: String?

    public init(enabled: Bool = false, engine: AssistEngineKind = .local,
                providers: [CloudProviderConfig] = [], activeProviderID: String? = nil) {
        self.enabled = enabled; self.engine = engine
        self.providers = providers; self.activeProviderID = activeProviderID
    }

    public var activeProvider: CloudProviderConfig? {
        providers.first { $0.id == activeProviderID }
    }

    // MARK: UserDefaults 持久化（key 不在此，存 Keychain）
    public static let defaultsKey = "cloudLLMSettings"

    public static func load(from defaults: UserDefaults = .standard) -> CloudLLMSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(CloudLLMSettings.self, from: data) else {
            return CloudLLMSettings()
        }
        return s
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter CloudLLMSettingsTests`
Expected: PASS（3 測試）

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/CloudLLMSettings.swift Packages/SessionScribeKit/Tests/SSCoreTests/CloudLLMSettingsTests.swift
git commit -m "feat: 雲端設定模型與持久化

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12：AssistResolver 路由與 Local Only 強制

**Files:**
- Modify: `Packages/SessionScribeKit/Sources/SSCore/Cloud/AssistEngine.swift`
- Test: `Packages/SessionScribeKit/Tests/SSCoreTests/AssistResolverTests.swift`

- [ ] **Step 1: 寫失敗測試**

```swift
import Foundation
import Testing
@testable import SSCore

struct AssistResolverTests {
    private func cloudSettings() -> CloudLLMSettings {
        var s = CloudLLMSettings()
        s.providers = [CloudProviderConfig(id: "p1", format: .openAICompatible,
            displayName: "X", baseURL: "https://api.example.com/v1", model: "m")]
        s.activeProviderID = "p1"
        s.enabled = true
        s.engine = .cloud
        return s
    }

    @Test func 引擎雲端且key齊_回雲端() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setSecret("sk", account: "p1")
        let organizer = AssistResolver.eventOrganizer(settings: cloudSettings(), keychain: keychain)
        #expect(organizer is CloudEventOrganizer)
    }

    @Test func 總開關關_強制本機() throws {
        var s = cloudSettings(); s.enabled = false
        let organizer = AssistResolver.eventOrganizer(settings: s, keychain: InMemoryKeychainStore())
        #expect(organizer is LocalEventOrganizer)
    }

    @Test func 引擎本機_強制本機() throws {
        var s = cloudSettings(); s.engine = .local
        let organizer = AssistResolver.eventOrganizer(settings: s, keychain: InMemoryKeychainStore())
        #expect(organizer is LocalEventOrganizer)
    }

    @Test func 缺key_退回本機() throws {
        let organizer = AssistResolver.eventOrganizer(
            settings: cloudSettings(), keychain: InMemoryKeychainStore())
        #expect(organizer is LocalEventOrganizer)
    }

    @Test func 摘要器同樣路由() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setSecret("sk", account: "p1")
        #expect(AssistResolver.summarizer(settings: cloudSettings(), keychain: keychain) is CloudTranscriptSummarizer)
        #expect(AssistResolver.summarizer(settings: CloudLLMSettings(), keychain: keychain) is LocalTranscriptSummarizer)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --package-path Packages/SessionScribeKit --filter AssistResolverTests`
Expected: FAIL（`AssistResolver` 未定義）

- [ ] **Step 3: 實作（附加到 AssistEngine.swift 末端）**

```swift
/// 依設定挑整理器/摘要器；任一條件不滿足都回本機（Local Only 程式層強制）。
/// 只有「總開關開 AND 引擎=雲端 AND 有 active 供應商 AND key 存在」才建構雲端 client。
public enum AssistResolver {
    public static func client(settings: CloudLLMSettings, keychain: KeychainStore) -> CloudLLMClient? {
        guard settings.enabled, settings.engine == .cloud,
              let provider = settings.activeProvider,
              let key = try? keychain.secret(account: provider.id), !key.isEmpty,
              let url = URL(string: provider.baseURL) else {
            return nil
        }
        switch provider.format {
        case .openAICompatible:
            return OpenAICompatibleClient(baseURL: url, apiKey: key, model: provider.model)
        case .anthropic:
            return AnthropicClient(baseURL: url, apiKey: key, model: provider.model)
        case .gemini:
            return GeminiClient(baseURL: url, apiKey: key, model: provider.model)
        }
    }

    public static func eventOrganizer(settings: CloudLLMSettings, keychain: KeychainStore) -> EventOrganizing {
        if let client = client(settings: settings, keychain: keychain) {
            return CloudEventOrganizer(client: client)
        }
        return LocalEventOrganizer()
    }

    public static func summarizer(settings: CloudLLMSettings, keychain: KeychainStore) -> TranscriptSummarizing {
        if let client = client(settings: settings, keychain: keychain) {
            return CloudTranscriptSummarizer(client: client)
        }
        return LocalTranscriptSummarizer()
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --package-path Packages/SessionScribeKit --filter AssistResolverTests`
Expected: PASS（5 測試）

- [ ] **Step 5: 全套回歸**

Run: `swift test --package-path Packages/SessionScribeKit`
Expected: PASS（既有測試不退化＋新增雲端測試）

- [ ] **Step 6: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSCore/Cloud/AssistEngine.swift Packages/SessionScribeKit/Tests/SSCoreTests/AssistResolverTests.swift
git commit -m "feat: 整理器/摘要器路由與 Local Only 程式層強制

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 13：DisplaySettings 雲端鍵 + ViewModel 路由

把 `SessionDetailViewModel` 三個 AI 入口（`organizeEvents`、`generateEventsWithAI`、`generateSummaryWithAI`）從直呼 `EventOrganizer` / `TranscriptSummarizer` 改成經 `AssistResolver` 取實例；可用性判斷在雲端模式時改看「有 active 供應商且 key 存在」。

**Files:**
- Modify: `Packages/SessionScribeKit/Sources/SSUI/DisplaySettings.swift`
- Modify: `Packages/SessionScribeKit/Sources/SSUI/Detail/SessionDetailView.swift:116-198`

- [ ] **Step 1: DisplaySettings 加鍵**

在 `DisplaySettings` enum 內（接在 translation 鍵之後）新增：

```swift
    /// 雲端整理（v0.3 Text Cloud Assist）。設定本體存 CloudLLMSettings.defaultsKey，
    /// 這裡只放 UI 觀察用的旗標鍵，實際讀寫走 CloudLLMSettings.load/save。
    public static let cloudAssistEnabledKey = "cloudAssistEnabledMirror"
```

- [ ] **Step 2: ViewModel 改走 AssistResolver**

在 `SessionDetailViewModel` 加一個解析輔助，並改三個方法。先在型別內加：

```swift
    private var cloudSettings: CloudLLMSettings { CloudLLMSettings.load() }
    private let keychain: KeychainStore = SystemKeychainStore()

    private var resolvedOrganizer: EventOrganizing {
        AssistResolver.eventOrganizer(settings: cloudSettings, keychain: keychain)
    }
    private var resolvedSummarizer: TranscriptSummarizing {
        AssistResolver.summarizer(settings: cloudSettings, keychain: keychain)
    }

    /// 目前生效的引擎（雲端需總開關開、引擎=雲端、供應商與 key 齊備）。
    var usingCloudAssist: Bool {
        AssistResolver.client(settings: cloudSettings, keychain: keychain) != nil
    }
```

把 `organizeEvents()` 內 `EventOrganizer.organize(current, locale: locale) { ... }` 改為：

```swift
                let organizer = resolvedOrganizer
                let organized = try await organizer.organize(current, locale: locale) { progress in
                    Task { @MainActor in self.organizeProgress = progress }
                }
```

把 `generateEventsWithAI()` 內 `EventOrganizer.generateEvents(...)` 改為：

```swift
                events = try await resolvedOrganizer.generateEvents(
                    from: segs, sessionID: sessionID, locale: locale)
```

把 `generateSummaryWithAI()` 內 `TranscriptSummarizer.generateSummary(...)` 改為：

```swift
                summary = try await resolvedSummarizer.summarize(
                    from: segs, sessionID: sessionID, locale: locale)
```

可用性：`canRunAI` / `canGenerateSummary` 在雲端生效時不應被本機模型可用性擋住。改 `canRunAI`：

```swift
    var canRunAI: Bool {
        (usingCloudAssist || organizeAvailabilityMessage == nil)
            && (!segments.isEmpty || !events.isEmpty)
    }
```

`canGenerateSummary`（讀 200 行附近原定義，套同樣 `usingCloudAssist ||` 前綴）比照修改。

- [ ] **Step 3: 跑雲端操作時把 session privacyMode 記為 textCloudAssist**

在 `organizeEvents`、`generateEventsWithAI`、`generateSummaryWithAI` 成功落盤後，若 `usingCloudAssist` 為真且 `session?.privacyMode != .textCloudAssist`，更新 metadata。新增私有方法：

```swift
    private func markTextCloudAssistIfNeeded() async {
        guard usingCloudAssist, var current = session, current.privacyMode != .textCloudAssist else { return }
        current.privacyMode = .textCloudAssist
        do {
            try await store.saveMetadata(current)
            session = current
        } catch {
            errorMessage = "更新隱私模式失敗：\(error.localizedDescription)"
        }
    }
```

在三個方法各自 `persistEvents()` / `persistSummary()` 之後 `await markTextCloudAssistIfNeeded()`。

> 實作註：確認 `SessionStore` 是否已有 `saveMetadata(_:)`。若無，於 `SessionStore` 加一個比照 `saveMarkers` 的原子寫 metadata 方法，並補一條 store 測試。

- [ ] **Step 4: 建置與回歸**

Run: `swift build --package-path Packages/SessionScribeKit && swift test --package-path Packages/SessionScribeKit`
Expected: Build complete；既有測試不退化

- [ ] **Step 5: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSUI/DisplaySettings.swift Packages/SessionScribeKit/Sources/SSUI/Detail/SessionDetailView.swift Packages/SessionScribeKit/Sources/SSCore/Storage
git commit -m "feat: 檢視頁 AI 整理/摘要經 AssistResolver 路由雲端

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 14：設定頁「雲端」分頁（iOS 風格、少文字）

維持既有分頁樣式，乾淨、不堆砌說明文字。

**Files:**
- Modify: `Packages/SessionScribeKit/Sources/SSUI/SettingsView.swift`

- [ ] **Step 1: 加分頁到 TabView**

在 `SettingsView` 的 `TabView` 內、轉寫分頁之後加：

```swift
            CloudSettingsTab()
                .tabItem {
                    Label("雲端", systemImage: "cloud")
                }
```

- [ ] **Step 2: 實作 CloudSettingsTab（檔尾新增 private struct）**

```swift
private struct CloudSettingsTab: View {
    @State private var settings = CloudLLMSettings.load()
    @State private var apiKey = ""
    @State private var showEnableWarning = false
    @State private var testResult: String?
    private let keychain: KeychainStore = SystemKeychainStore()

    private var active: CloudProviderConfig? { settings.activeProvider }

    var body: some View {
        Form {
            Section {
                Toggle("啟用雲端整理", isOn: Binding(
                    get: { settings.enabled },
                    set: { newValue in
                        if newValue { showEnableWarning = true }
                        else { settings.enabled = false; persist() }
                    }))
                Picker("整理引擎", selection: Binding(
                    get: { settings.engine }, set: { settings.engine = $0; persist() })) {
                    Text("本機").tag(AssistEngineKind.local)
                    Text("雲端").tag(AssistEngineKind.cloud)
                }
                .disabled(!settings.enabled)
            }

            Section("供應商") {
                Picker("使用", selection: Binding(
                    get: { settings.activeProviderID ?? "" },
                    set: { settings.activeProviderID = $0; loadKey(); persist() })) {
                    Text("未選擇").tag("")
                    ForEach(settings.providers) { p in Text(p.displayName).tag(p.id) }
                }
                Menu("新增供應商") {
                    ForEach(CloudProviderConfig.builtInTemplates) { tpl in
                        Button(tpl.displayName) { addTemplate(tpl) }
                    }
                }
            }

            if let provider = active, let index = settings.providers.firstIndex(where: { $0.id == provider.id }) {
                Section(provider.displayName) {
                    Picker("格式", selection: $settings.providers[index].format) {
                        ForEach(CloudProviderFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField("Base URL", text: $settings.providers[index].baseURL)
                    TextField("Model", text: $settings.providers[index].model)
                    SecureField("API key", text: $apiKey)
                    HStack {
                        Button("儲存金鑰") { saveKey(account: provider.id) }
                        Button("測試連線") { testConnection() }
                        if let testResult { Text(testResult).appFont(.caption).foregroundStyle(.secondary) }
                    }
                    Button("刪除此供應商", role: .destructive) { removeProvider(provider.id) }
                }
                .onChange(of: settings.providers) { persist() }
            }
        }
        .formStyle(.grouped)
        .alert("啟用雲端整理", isPresented: $showEnableWarning) {
            Button("取消", role: .cancel) {}
            Button("啟用") { settings.enabled = true; persist() }
        } message: {
            Text("選定的逐字稿或事件內容會送往所選供應商，音訊不會送出。AI 產物會標記需複查。")
        }
        .onAppear { loadKey() }
    }

    private func persist() { settings.save() }

    private func addTemplate(_ tpl: CloudProviderConfig) {
        var copy = tpl
        copy.id = "\(tpl.id)-\(UUID().uuidString.prefix(6))"
        settings.providers.append(copy)
        settings.activeProviderID = copy.id
        apiKey = ""
        persist()
    }

    private func removeProvider(_ id: String) {
        settings.providers.removeAll { $0.id == id }
        if settings.activeProviderID == id { settings.activeProviderID = settings.providers.first?.id }
        try? keychain.deleteSecret(account: id)
        loadKey(); persist()
    }

    private func loadKey() {
        apiKey = (try? keychain.secret(account: settings.activeProviderID ?? "")) ?? ""
    }

    private func saveKey(account: String) {
        try? keychain.setSecret(apiKey, account: account)
        testResult = "已儲存"
    }

    private func testConnection() {
        guard let provider = active else { return }
        try? keychain.setSecret(apiKey, account: provider.id)
        var probe = settings; probe.enabled = true; probe.engine = .cloud
        guard let client = AssistResolver.client(settings: probe, keychain: keychain) else {
            testResult = "設定不完整"; return
        }
        testResult = "測試中…"
        Task {
            do {
                _ = try await client.complete(system: "回覆 JSON {\"ok\":true}", user: "ping")
                await MainActor.run { testResult = "連線成功" }
            } catch let error as CloudLLMError {
                await MainActor.run { testResult = error.userMessage }
            } catch {
                await MainActor.run { testResult = "連線失敗" }
            }
        }
    }
}
```

- [ ] **Step 3: 建置 app 並手動驗收**

Run: `swift build --package-path Packages/SessionScribeKit`
然後建置 app：`xcodebuild -scheme SessionScribe -destination 'platform=macOS' build`
手動：開設定 → 雲端分頁 → 新增 OpenAI 樣板 → 填 key → 測試連線（需有效 key）→ 看到「連線成功」；關 app 重開，設定與供應商保留、key 從 Keychain 讀回。

- [ ] **Step 4: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSUI/SettingsView.swift
git commit -m "feat: 設定頁雲端分頁（供應商/金鑰/測試連線）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 15：非 Local Only 狀態標

**Files:**
- Create: `Packages/SessionScribeKit/Sources/SSUI/Components/PrivacyModeBadge.swift`
- Modify: 主錄音畫面（`RootView.swift` 或工具列容器）與 `SessionDetailView` 標頭，置入 badge。

- [ ] **Step 1: 實作 badge（精簡、不干擾）**

```swift
import SSCore
import SwiftUI

/// 非 Local Only 時顯示的精簡狀態標；Local Only 不顯示（回傳 EmptyView）。
struct PrivacyModeBadge: View {
    let mode: PrivacyMode

    var body: some View {
        if mode != .localOnly {
            Label(label, systemImage: "cloud")
                .appFont(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.yellow.opacity(0.18), in: Capsule())
                .foregroundStyle(.secondary)
                .help("此 session 啟用雲端整理，文字會送往雲端供應商。")
        }
    }

    private var label: String {
        switch mode {
        case .localOnly: ""
        case .textCloudAssist: "雲端整理"
        case .audioCloudASR: "雲端 ASR"
        }
    }
}
```

- [ ] **Step 2: 置入畫面**

在 `SessionDetailView` 標頭（session 標題列）插入 `PrivacyModeBadge(mode: model.session?.privacyMode ?? .localOnly)`。
在主錄音畫面工具列，依目前設定顯示：當 `CloudLLMSettings.load()` 的 `enabled && engine == .cloud` 時顯示 `PrivacyModeBadge(mode: .textCloudAssist)`，否則不顯示。

- [ ] **Step 3: 建置 app 並手動驗收**

Run: `xcodebuild -scheme SessionScribe -destination 'platform=macOS' build`
手動：未啟用雲端時無 badge；啟用雲端引擎後主畫面出現「雲端整理」標；對跑過雲端整理的 session 開檢視頁，標頭顯示 badge。

- [ ] **Step 4: Commit**

```bash
git add Packages/SessionScribeKit/Sources/SSUI/Components/PrivacyModeBadge.swift Packages/SessionScribeKit/Sources/SSUI
git commit -m "feat: 非 Local Only 雲端狀態標

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 16：加入 network.client entitlement

**Files:**
- Modify: `SessionScribe/SessionScribe.entitlements`

- [ ] **Step 1: 加 entitlement**

在 `<dict>` 內新增：

```xml
	<key>com.apple.security.network.client</key>
	<true/>
```

- [ ] **Step 2: 建置並實機驗證雲端連線可達**

Run: `xcodebuild -scheme SessionScribe -destination 'platform=macOS' build`
手動：填有效 key、引擎設雲端、對一段逐字稿按「AI 整理」→ 雲端回填語意欄位、事件標 needs_review。關閉雲端（引擎本機）→ 行為回到本機 FoundationModels。

- [ ] **Step 3: Commit**

```bash
git add SessionScribe/SessionScribe.entitlements
git commit -m "feat: 加入 network.client entitlement（雲端整理）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 17：文件

**Files:**
- Modify: `docs/SPEC.md`、`docs/DATA_FORMATS.md`、`docs/TESTING.md`，並把設計 spec 折回 SPEC 成「規格 1.3」。

- [ ] **Step 1: SPEC**

七節隱私模式 Text Cloud Assist 項由 v0.3 規劃改為「已實作」並描述：三格式轉接器、單一 app 帶 network.client、Local Only 程式層強制、API key 存 Keychain。新增「規格 1.3」節摘要本功能與既定決策（比照規格 1.1、1.2）。狀態表把「雲端整理（Text Cloud Assist）」改 v0.3 已實作。

- [ ] **Step 2: DATA_FORMATS**

記錄 `privacy_mode` 在跑雲端整理時會被記為 `text_cloud_assist`；`CloudLLMSettings` 存 UserDefaults（不含 key）、API key 存 Keychain（service `com.sessionscribe.cloud-llm`、account 為供應商 id）。雲端產出的 events/summary 與本機同結構、同 `needs_review` 規則。

- [ ] **Step 3: TESTING**

新增「雲端整理實機驗收」清單：三家各填一把 key 測連線、各跑一次事件整理與摘要、驗證 Local Only（引擎本機時以 Little Snitch/Charles 觀察零外連）、key 重啟保留、錯誤情境（錯 key→401 訊息、拔網路→連線失敗訊息、本機資料不損）。

- [ ] **Step 4: Commit**

```bash
git add docs/SPEC.md docs/DATA_FORMATS.md docs/TESTING.md
git commit -m "docs: 雲端整理（規格 1.3）折回 SPEC 與資料格式/測試清單

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 收尾驗證

- [ ] 全套單元測試：`swift test --package-path Packages/SessionScribeKit` 全綠。
- [ ] app 建置：`xcodebuild -scheme SessionScribe -destination 'platform=macOS' build` 成功。
- [ ] 三家供應商各實機跑一次整理與摘要（需有效 key）。
- [ ] Local Only 驗證：引擎設本機時，以網路監控確認零外連。
- [ ] 更新記憶 [[sessionscribe-project]] 進度段落，分支合 main 並推（待使用者指示）。

## 自我審查結果

- 規格涵蓋：三格式轉接器（Task 3-5）、兩操作雲端化（Task 8-9）、Keychain（Task 10）、設定模型（Task 11）、路由＋Local Only 強制（Task 12）、設定 UI（Task 14）、狀態標（Task 15）、entitlement（Task 16）、隱私警告（Task 14 alert）、文件（Task 17）。spec 各節皆有對應任務。
- 型別一致：`CloudLLMClient.complete(system:user:)`、`EventOrganizing`/`TranscriptSummarizing`、`AssistResolver.client/eventOrganizer/summarizer`、`CloudLLMSettings`/`CloudProviderConfig`/`AssistEngineKind`、`KeychainStore` 全篇一致。
- 重用既有：`EventOrganizer.instructions/generateInstructions/applyOrganized/buildEvent`、`TranscriptSummarizer.instructions/buildSummary`（Task 6 放寬可見性）。
- 待實作期確認項：`SessionStore.saveMetadata` 是否存在（Task 13 Step 3 已標註，缺則補）；Anthropic model id 與 anthropic-version、Gemini 端點細節以 source-driven-development/claude-api 核對（Task 4、5 已標註）；`canGenerateSummary` 原定義在 SessionDetailView 200 行附近，套 `usingCloudAssist ||` 前綴。
