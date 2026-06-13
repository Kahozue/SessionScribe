# 雲端 LLM 整理（Text Cloud Assist）設計

日期：2026-06-13
狀態：已確認，待寫實作計畫
對應版本：v0.3（SPEC 七節隱私模式第 2 項 Text Cloud Assist）
落地後折回 `docs/SPEC.md` 成「規格 1.3」新節（比照規格 1.1、1.2 的作法）。

## 背景與定位

本機 LLM 整理事件（`EventOrganizer`）與整份逐字稿摘要（`TranscriptSummarizer`）已用 macOS 26
FoundationModels 完成並在 main。本案為這兩項操作新增「雲端」可選後端，支援 OpenAI 相容、Anthropic、
Gemini 三種線路格式，每個供應商可設 base URL、API key、model 字串。本機與雲端並存，使用者每次選用哪個。

`PrivacyMode` enum（`localOnly` / `textCloudAssist` / `audioCloudASR`）已在 `Session.swift`，且
SessionInfoView 已顯示，資料模型與 UI 顯示的 MVP 已完成。本案補的是 Text Cloud Assist 的實際功能。

範圍限 Text Cloud Assist：音訊永遠留本機，只把使用者選定的逐字稿或結構化請求送雲端。不含 Audio
Cloud ASR。

## 既定決策

- 雲端作為事件整理與整份摘要兩項操作的可選後端（本機路徑保留不動）。
- 單一 app 出貨即帶 `com.apple.security.network.client` entitlement。Local Only 由程式層堅守：
  Local Only 路徑完全不建立連線。OS 強制零網路的保證由此降為程式層保證，以 in-app guard、持續
  UI 提示、啟用前警告、README 可驗證性說明補強。
- 三格式轉接器（OpenAI 相容 / Anthropic / Gemini）＋ 每供應商可設 base URL、API key、model。
  OpenAI 相容一條涵蓋 DeepSeek、OpenAI 及任何相容端點。
- API key 存 Keychain，不進 UserDefaults、不寫任何檔案。不支援環境變數 fallback（YAGNI）。
- 結構化輸出統一採「prompt 要求 JSON ＋ 容錯解析」，不為三家各接一套 schema 機制。
- 雲端產物一律 `needsReview: true`，沿用既有 `StructuredEvent` / `TranscriptSummary` 型別與落盤路徑。
- UI 維持現有 iOS 風格：設定頁雲端分頁與非 Local Only 狀態標走既有元件樣式，乾淨、少文字、不花俏，
  不新增大段說明文字或裝飾性版面。啟用前警告與錯誤訊息精簡到位即可。

## 分層與抽象

新增 `Packages/SessionScribeKit/Sources/SSCore/Cloud/`，networking 留在 SSCore（純 Foundation
URLSession，不新增 target）：

```
SSCore/Cloud/
├── CloudLLMClient.swift          協定：給 system + user prompt → 回 assistant 純文字
├── OpenAICompatibleClient.swift  POST {baseURL}/chat/completions、Authorization: Bearer
├── AnthropicClient.swift         POST {baseURL}/v1/messages、x-api-key + anthropic-version
├── GeminiClient.swift            POST {baseURL}/v1beta/models/{model}:generateContent
├── CloudEventOrganizer.swift     組 prompt（沿用 EventOrganizer.instructions）→ 解析 → StructuredEvent
└── CloudTranscriptSummarizer.swift  組 prompt（沿用 Summarizer prompt）→ 解析 → TranscriptSummary
```

`CloudLLMClient` 協定捕捉三家共同的最小能力：送一段 system 指示 + user 內容，回傳 assistant 文字。
三個轉接器只差線路格式（端點路徑、auth header 名、request/response JSON 形狀）。`CloudEventOrganizer`
與 `CloudTranscriptSummarizer` 持有一個 `CloudLLMClient`，負責組 prompt（重用本機路徑的同一份
instructions 與時間區間 prompt 格式）、要求 JSON 輸出、容錯解析（剝 ```json 圍欄、取第一個 JSON
物件或陣列），再解碼回既有型別。`buildEvent` 的時間重疊回推、`source_segment_ids`、`needsReview`
強制 true 等可靠性邏輯與本機共用，避免兩套行為分歧。

## 供應商設定與金鑰

- 新增 `CloudLLMSettings`（持久化於 UserDefaults，不含 key）：供應商設定清單（id、format、顯示名、
  baseURL、model 字串）＋ 哪個為 active ＋ 總開關 `cloudAssistEnabledKey`（預設 false）。
- API key 存 Keychain（`kSecClassGenericPassword`），以供應商 id 為帳號鍵。包一層 `KeychainStore`
  協定以便測試注入假實作。
- 設定頁新增「雲端」分頁：選格式、填 base URL / model、API key 用 `SecureField`、「測試連線」鈕
  （送一則極短 ping prompt 驗 key 與端點）。

## 觸發 UX（本機 vs 雲端）

- 設定頁加全域「整理／摘要引擎：本機 / 雲端」選項（`assistEngineKey`，預設本機）。
- 雲端被選且總開關開時，`SessionDetailView` 既有的「AI 產生草稿／AI 整理」「AI 摘要」鈕改走雲端，
  否則走本機（現狀）。按鈕標籤與 help 反映當前引擎。
- 跑雲端操作時把該 session 的 `privacyMode` 記為 `textCloudAssist`（資料模型已有此欄位，如實記錄）。

## 隱私強制與提示

- 唯一的 `URLSession` 只在 `SSCore/Cloud` 層，且只在「總開關開 AND 引擎=雲端」時才會被建構與呼叫。
  Local Only 路徑不碰網路。以 guard 集中於一處決定是否進雲端，並加單元測試確保 Local Only 不建構
  任何 client。
- 持續顯示模式（SPEC 七節）：非 Local Only 時，主視窗與檢視頁有明顯但不干擾的標記（沿用 SessionInfoView
  既有 privacyMode 顯示，另在主錄音畫面加一枚狀態標）。
- 啟用前明確警告：首次開總開關跳 alert，說明文字（選定逐字稿／事件內容）會送往所選供應商、音訊永遠
  不送、產物標需複查。
- 只送選定文字：摘要送 finalized 逐字稿文字、整理送事件 content 或逐字稿片段，絕不送音訊或原始 chunk。

## 錯誤處理

- 雲端結果一律 `needsReview: true`。
- 網路錯誤、401 認證、429 限流、逾時、JSON 解析失敗都轉成清楚的中文錯誤訊息，顯示於既有 errorMessage
  路徑。本機資料絕不遺失，使用者可重試或改用本機。
- 雲端失敗不影響錄音與逐字稿（比照核心原則：整理或摘要失敗，錄音與逐字稿仍保存）。
- 逾時設合理上限（如 60s）；429 訊息提示稍後重試。

## 測試

- 每個轉接器的 request 組裝（body JSON 形狀、headers、端點路徑）與 response 解析，用錄製樣本字串，
  不打真網路（以注入的 URLProtocol stub 或把「組 request / 解析 response」抽成純函式測）。
- 容錯 JSON 解析：```json 圍欄、前後雜訊、陣列 vs 物件。
- `CloudEventOrganizer` / `CloudTranscriptSummarizer` 以 `MockCloudLLMClient` 測：產物型別正確、
  needsReview 強制 true、source 追溯保留。
- 引擎選擇路由：本機/雲端依設定走對路徑。
- Local Only 強制：總開關關或引擎=本機時不建構任何 client。
- `KeychainStore` 以假實作測存取。
- 三家真實連線手動實機驗收（各填一把 key）。

## 不在範圍（YAGNI）

- 串流回應。
- 自定義整理 prompt（另列 v0.3 或後續）。
- Audio Cloud ASR、雲端 ASR API key 的環境變數讀取。
- 多供應商備援、負載平衡。
- token 用量計費 UI。
- 雙建構版本（Local-Only 無 entitlement 版）。

## 實作前置

三家線路格式於實作時以官方文件查證（source-driven-development）：

- OpenAI 相容：Chat Completions、`response_format`。
- Anthropic：走 claude-api 技能核對 Messages API、`anthropic-version` header、`max_tokens` 必填、
  目前 model id。
- Gemini：`generateContent`、`responseMimeType: application/json`、key 帶法。
