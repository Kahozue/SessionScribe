# SessionScribe 架構文件

版本：1.4（2026-07-05；對應規格 1.4，補雲端層〔三格式 LLM、雲端 STT、AssistResolver 路由〕、即時翻譯層、重新轉錄流程與 network entitlement 現況）
對應規格：`docs/SPEC.md` 1.4

## 一、分層架構

```
┌─────────────────────────────────────────────────────┐
│ UI 層（SSUI，SwiftUI）                                │
│ NavigationSplitView 三欄、toolbar、view models        │
│ 只依賴 protocol 與值型別，不碰 AVFoundation / Speech   │
├─────────────────────────────────────────────────────┤
│ 領域層（SSCore）                                      │
│ SessionController（狀態機）、MarkerService、           │
│ EventDraftBuilder、EventOrganizer、                    │
│ TranscriptSummarizer、ExportService、                  │
│ EngineSelector、MediaClock、                          │
│ TranscriptionCoordinator／OfflineTranscriber／        │
│ CloudTranscriber（離線轉寫本地/雲端）、                │
│ TranslationCoordinator（即時翻譯本地/雲端）、          │
│ AssistResolver（各功能引擎路由，Local Only 程式層守門）│
├─────────────────────────────────────────────────────┤
│ 基礎設施層                                            │
│ SSAudio：AudioCaptureService、ChunkedAudioWriter、    │
│          AudioLevelMeter                             │
│ SSTranscription：AppleSpeechEngine、                  │
│          LegacySFSpeechEngine、MockTranscriptionEngine│
│ SSCore.Storage：SessionStore、JSONLWriter、           │
│          SessionLibrary（列表與崩潰恢復掃描）           │
│ SSCore.Cloud：CloudLLMClient 三格式轉接器（OpenAI 相容 │
│          ／Anthropic／Gemini）、CloudSTTClient（OpenAI │
│          相容／Gemini）、KeychainStore；唯一的 URLSession│
│          只在此層，僅在該功能選雲端且 key 齊備時建構    │
└─────────────────────────────────────────────────────┘
```

依賴方向嚴格由上往下。app target（SessionScribe/）只負責組裝與 entitlements。

## 二、並行模型

- 有狀態服務（SessionController、ChunkedAudioWriter、SessionStore）為 actor，狀態存取天然隔離。
- 音訊 buffer 以 `AsyncStream<AVAudioPCMBuffer>` 傳遞；轉寫結果以 `AsyncStream` 自引擎流出。
- View model 為 `@MainActor @Observable`，訂閱領域層的狀態流並更新 UI。
- SpeechAnalyzer 本身是 async API，feed 端用 `AsyncStream<AnalyzerInput>` 銜接。

## 三、核心資料流

### 錄音與轉寫（解耦設計）

```
AVAudioEngine input tap
        │ AsyncStream<AVAudioPCMBuffer>
        ├──→ ChunkedAudioWriter ──→ chunk_NNNN.caf + manifest.json
        │     （最高優先消費者，永不受 ASR 狀態影響）
        └──→ AVAudioConverter（裝置格式 → 引擎 bestAvailableAudioFormat）
              └──→ TranscriptionEngine.feed()
                        ├──→ volatile 流 ──→ 記憶體（僅最新一筆）──→ UI 淡色尾段
                        └──→ finalized 流 ──→ live_segments.jsonl append+flush ──→ UI
```

ASR 引擎拋錯時，EngineSelector 依鏈降級（SpeechTranscriber → DictationTranscriber → SFSpeechRecognizer → 純錄音），狀態列即時更新；音訊寫入分支完全不受影響。

### 標記流程

```
按鍵 / 按鈕 ──→ MarkerService
    ├─ MediaClock.currentSeconds（樣本數計時）
    ├─ 快照當下已 finalized 的鄰近 segment ids
    └─ manual_markers.jsonl append+flush ──→ UI 事件列表
```

讀取與匯出時，marker 與 segment 的關聯由時間戳動態重算，寫入的 ids 只是快照。

```
右欄書籤取消 ──→ RecordingViewModel / SessionDetailModel
    ├─ 從記憶體 markers 移除指定 marker_id
    ├─ SessionStore.saveMarkers(_:) 暫停 append handle
    ├─ manual_markers.jsonl.tmp 寫入剩餘 markers
    └─ 原子改名覆蓋 manual_markers.jsonl ──→ UI 重算 inline markers
```

Cmd+1 至 Cmd+4 的視覺色票由 `MarkerVisualStyle` 依模板 slot 固定映射；中欄 `MarkerTimeline.inlineMarkers` 與右欄 `MarkerInspectorRow` 共用同一套樣式，避免事件整理後色票退回單色。

### 整份逐字稿摘要

```
AI 產生摘要
    └─ TranscriptSummarizer（FoundationModels）
        ├─ finalized segments 全量輸入
        ├─ 產生 content / key_points / action_items
        ├─ 保留來源資訊，UI 不顯示需複查標籤
        ├─ source_segment_ids 包含所有 finalized segments
        └─ transcript_summary.json 原子寫入
```

右欄載入順序固定為「逐字稿摘要 → 結構化事件 → 事件標記」。摘要是衍生資料，不會覆蓋 `live_segments.jsonl`，也不會改動 events 或 markers。

### 結構化事件與本機 AI 整理

```
依標記彙整
    └─ EventDraftBuilder
        ├─ marker 時間窗前後 finalized segments
        ├─ source_marker_ids / source_segment_ids
        └─ events.json 原子寫入

AI 產生草稿 / AI 整理
    └─ EventOrganizer（FoundationModels）
        ├─ 無 events：從 finalized segments 生成 events
        ├─ 有 events：補齊 topic / summary / action item 等欄位
        ├─ needs_review 強制 true
        └─ 保留原始 content、時間軸與來源 segment
```

`EventOrganizer` 只在本機 Foundation Models 可用時啟用；不可用時 UI 顯示原因並保留 `EventDraftBuilder` 的機械路徑。整理流程不得修改原始逐字稿或移除已建立 markers。

### 各功能引擎路由（規格 1.4）

```
UI 動作（轉寫／摘要／整理／翻譯）
    └─ AssistResolver
        ├─ 讀 CloudLLMSettings：總開關、featureEngines[feature]、
        │  依 feature.capability 取 textProviderID 或 audioProviderID
        ├─ 「總開關開 AND 該功能=雲端 AND 供應商存在 AND key 非空」
        │      └─ 成立：建構對應 client（sttClient 額外要求 supportsSTT）
        └─ 任一不成立：回 nil，呼叫端一律退回本機路徑
```

Local Only 的零網路保證自 v0.3 起由此路由層堅守：唯一的 `URLSession` 只在 `SSCore/Cloud`，未通過守門即不存在網路物件（`AssistResolverTests` 佐證）。

### 雲端離線轉錄稿（Audio Cloud ASR，規格 1.4）

```
離線轉寫入口（匯入後轉寫／檢視頁轉寫／重新轉錄）
    └─ CloudTranscriber
        ├─ AudioExporter：manifest 順序串接 CAF chunks 轉單一 .m4a
        ├─ CloudSTTClient 上傳（OpenAISTTClient /audio/transcriptions、
        │  GeminiSTTClient generateContent inline audio）
        ├─ 回應套名詞表 → TranscriptSegment 落盤（engine: "cloud"；
        │  無 segment 時間者以音訊總長補單段 end time）
        └─ 成功後 privacyMode 併入 audio_cloud_asr
```

### 即時字幕翻譯（規格 1.2 Phase 3／1.4 雲端）

```
finalized segment ──→ TranslationCoordinator（獨立 Task，不卡逐字稿）
    ├─ 本地：AppleTranslator（macOS 26.4 以上；prepare 失敗只顯示原文）
    └─ 雲端：CloudTranslator（AssistResolver 取 chat client，逐句只送文字）
        └─ 譯文以 segmentID 回填 UI，僅存記憶體、不持久化
```

### 重新轉錄（規格 1.4）

```
檢視頁「重新轉錄」──→ 二次確認（confirmationDialog）
    ├─ 於暫存目錄建立 temp SessionStore，先轉寫到暫存
    ├─ 成功才 SessionStore.replaceSegments 原子覆蓋 live_segments.jsonl
    │  （中途失敗既有逐字稿不動）
    └─ 摘要、events、譯文不自動更新，由確認文案提示使用者自行重生
```

### 崩潰恢復流程

```
App 啟動 ──→ SessionLibrary 掃描
    └─ metadata.json 中 ended_at == null 且非進行中
        ├─ 重建 audio manifest（掃描 audio/ 目錄補孤兒 chunk）
        ├─ 載入 live_segments.jsonl 與 manual_markers.jsonl
        └─ metadata 設 recovered: true，UI 標示「已恢復」
```

## 四、關鍵設計決策

| 決策 | 理由 |
|---|---|
| MediaClock 用累計 frame 數計時 | pause 期間無 buffer 流入，媒體時間自然停止；轉寫時間戳與音訊時間軸用同一時鐘，天然一致 |
| PCM CAF chunks，索引不合併 | CAF 對中斷寫入容錯最佳；索引是 append-only，恢復簡單；合併是可選匯出 |
| marker 關聯動態重算 | 按標記時附近語音常在 volatile 狀態，segment 未定稿；時間戳是唯一真相 |
| marker 取消採原子重寫 | 建立 marker 仍保留 append+flush 的現場可靠性；取消屬於事後編輯，以完整檔案原子替換避免 tombstone 規則複雜化 |
| network client entitlement（v0.3 起）＋程式層守門 | 雲端功能需要網路；Local Only 保證改由 AssistResolver 逐功能守門（唯一 URLSession 只在 SSCore/Cloud，未選雲端不建構），輔以 UI 狀態標與單元測試 |
| 文字類與語音類兩個供應商槽 | 摘要／事件／翻譯共用文字槽，轉錄稿／即時 ASR 共用語音槽；語音槽只列支援 STT 的格式，避免把 chat model 送到語音端點 |
| 重新轉錄先寫暫存再原子替換 | 轉寫中途失敗（網路、引擎）不得毀掉既有逐字稿；成功才 replaceSegments 覆蓋 |
| Mock engine 先於 Apple engine | UI 與儲存開發完全不被新 API 可用性卡住；CI 無需 macOS 26 語音模型 |
| 核心邏輯在 Swift Package | swift test 可 headless 執行；pbxproj 改動最小化，利於 GitHub 協作 |
| deployment target macOS 26 | 唯一目標機器即 macOS 26；SFSpeechRecognizer 備援解決的是 locale 缺口，與 OS 版本無關 |
| 本機 AI 整理與標記解耦 | 使用者可能沒有即時標記；v0.2 允許從 finalized segments 直接生成事件，標記仍作為高可信提示而不是唯一入口 |
| 摘要與事件分檔 | 整份摘要與結構化事件的使用情境不同；`transcript_summary.json` 與 `events.json` 分開保存，避免摘要重新生成時影響事件編輯結果 |

## 五、TranscriptionEngine 抽象

```swift
public protocol TranscriptionEngine: Sendable {
    var info: EngineInfo { get }                     // 名稱、是否本機、支援能力
    func availability(for locale: Locale) async -> EngineAvailability
    func prepare(locale: Locale) async throws        // 含模型下載引導（AssetInventory）
    func start() async throws
    func feed(_ buffer: AVAudioPCMBuffer, at mediaSeconds: Double)
    func finish() async throws
    var finalizedSegments: AsyncStream<TranscriptSegment> { get }
    var volatileText: AsyncStream<VolatileUpdate> { get }
}
```

實作：

- `AppleSpeechEngine`：SpeechAnalyzer + SpeechTranscriber，volatile + finalized + timing metadata，AssetInventory 檢查與下載。
- `LegacySFSpeechEngine`：SFSpeechRecognizer，zh-TW 確定支援，作 locale 缺口備援。
- `MockTranscriptionEngine`：依腳本定時吐出 volatile 與 finalized 結果，可注入錯誤，供 UI 開發與測試。

`EngineSelector` 負責依 locale 與執行期可用性挑選引擎並處理降級。

## 六、專案檔案結構

```
SessionScribe/
├── README.md
├── .gitignore
├── docs/
│   ├── SPEC.md
│   ├── ARCHITECTURE.md
│   ├── DATA_FORMATS.md          （schema 細節，M1 產出）
│   └── TESTING.md               （測試方法，M2 起累積）
├── SessionScribe.xcodeproj
├── SessionScribe/                 （app target 薄殼）
│   ├── SessionScribeApp.swift
│   ├── SessionScribe.entitlements
│   ├── Info.plist                 （NSMicrophoneUsageDescription）
│   └── Resources/Assets.xcassets
└── Packages/
    └── SessionScribeKit/
        ├── Package.swift
        ├── Sources/
        │   ├── SSCore/
        │   │   ├── Models/          （Session、TranscriptSegment、Marker、StructuredEvent、TranscriptSummary、Lexicon、SessionTemplate、...）
        │   │   ├── Storage/         （SessionStore、JSONLWriter、SessionLibrary、LibraryConfig、TranscriptSearchService）
        │   │   ├── Export/          （MarkdownExporter、JSONExporter、CSVExporter、AudioExporter、ExportService）
        │   │   ├── SessionController/（SessionController、MarkerService、EventDraftBuilder、EventOrganizer、TranscriptSummarizer）
        │   │   ├── Transcription/   （TranscriptionEngine、TranscriptionCoordinator、OfflineTranscriber、CloudTranscriber）
        │   │   ├── Translation/     （LiveTranslator、TranslationCoordinator、CloudTranslator）
        │   │   └── Cloud/           （CloudLLMClient 三格式轉接器、CloudSTTClient〔OpenAI 相容／Gemini〕、AssistResolver、CloudLLMSettings、KeychainStore、JSONExtraction）
        │   ├── SSAudio/
        │   ├── SSTranscription/     （AppleSpeechEngine、LegacySFSpeechEngine、MockTranscriptionEngine、EngineSelector、AppleTranslator）
        │   └── SSUI/
        │       ├── Transcript/      （TranscriptListView）
        │       ├── Detail/          （SessionDetailView）
        │       ├── Components/      （LevelMeter、MarkerButtons、MarkerVisualStyle、ExportOptions、...）
        │       └── （RootView、RecordingViewModel、SettingsView、CaptionOverlayView 等置於根層）
        └── Tests/
            ├── SSCoreTests/
            ├── SSAudioTests/
            ├── SSTranscriptionTests/
            └── SSUITests/
```

## 七、里程碑

每個里程碑完成時說明：新增檔案、修改檔案、如何執行、如何測試、目前限制。

### M0 專案骨架
git init、Xcode 專案、SessionScribeKit package、entitlements（sandbox + audio-input、無 network）、app 可啟動顯示空殼三欄佈局、README 初版。
附帶 spike：實測 `SpeechTranscriber.supportedLocales` 是否含 zh-TW，記錄於 docs。
驗證：建置通過、app 啟動、entitlements 檢查。

### M1 資料模型與儲存
SSCore Models、SessionStore、JSONLWriter（append + flush）、SessionLibrary、MediaClock、session 資料夾建立、metadata 原子寫入。
驗證：swift test 全綠。

### M2 錄音管線
麥克風權限流程、輸入裝置選擇、AudioCaptureService、ChunkedAudioWriter（CAF 分塊 + manifest）、level meter、Start/Pause/Resume/Stop 狀態機、防睡眠 assertion、磁碟空間檢查、崩潰恢復掃描。
驗證：實機錄音；錄音中 `kill -9` 後重啟，chunks 與 manifest 可恢復；pause/resume 多次後時間軸正確。

### M3 標記與匯出
四鍵 marker（Q/R/S/A + Cmd+1 至 4、焦點規則）、MarkerService 即時落盤、marker 與 segment 時間窗動態關聯、Inspector 事件列表、MarkdownExporter、JSONExporter、CSVExporter（markers.csv）、匯出面板。所有匯出器接受 segment 子集（規格 1.1 第 4 項選取匯出的基礎）。
驗證：快速連按壓力測試；匯出檔案格式比對；單元測試。

### M4 Mock 引擎與即時逐字稿 UI（含規格 1.1 第 1 至 4 項）
MockTranscriptionEngine、TranscriptionEngine protocol 接線、live transcript 卡片式列表（lazy 渲染、時間戳徽章、marker 內嵌）、volatile 淡色尾段與 finalized 區分、轉寫狀態指示、ASR 錯誤注入測試、浮動即時逐字稿視窗（always-on-top、可調大小）、字級與外觀模式設定、逐字稿多選與選取匯出 UI、點擊 segment 捲動定位。
驗證：無新 API 環境下完整跑 UI；模擬 ASR 失敗錄音不中斷。

### M5 Apple 引擎整合（完成即 v0.1）
AppleSpeechEngine（SpeechAnalyzer / SpeechTranscriber）、AssetInventory 模型檢查與下載引導、locale 執行期檢查、EngineSelector 降級鏈、LegacySFSpeechEngine、引擎狀態 UI。
驗證：實機 zh-TW 轉寫；v0.1 全部 21 條驗收標準逐條檢核。

### M6 匯入與錄音檢視（規格 1.1 第 5、6、10 項）
匯入音檔（caf/wav/m4a/mp3/aiff 建立 imported session、可選離線轉寫）、metadata `source` 欄位、錄音檢視頁（metadata、chunk 串接播放、進度條、逐字稿全文、marker 列表）、歌詞式定位效果（當前 segment 放大置中、spring 動畫、點擊跳轉播放）。
驗證：匯入後轉寫結果與錄音路徑一致；播放跳轉時間正確；單元測試（匯入建檔、離線轉寫管線、播放時間軸對應）。

### M7 分類、批次與搜尋（規格 1.1 第 7、9 項）
library.json（分類定義：自訂、隱藏、排序）、metadata `category_id`、sidebar 分類區段、session 多選、批次刪除（確認對話框）與批次移動分類、TranscriptSearchService 跨逐字稿搜尋與結果跳轉。
驗證：分類 CRUD 與隱藏；批次操作單元測試；搜尋命中與跳轉；舊 metadata 無欄位相容。

### M8 收尾與 icon（規格 1.1 第 8 項）
SVG 繪製 app icon 轉 icns、README 補齊（安裝、執行、權限、匯入、匯出）、v0.1.1 整體回歸。

### v0.2 與 v0.3
v0.2 已合併且驗收通過：模板系統、自定義 marker type、專有名詞表校正、EventDraftBuilder、結構化事件檢視與編輯、EventOrganizer 本機 AI 整理、設定頁、segment 播放、`structured_notes.md` / `events.json` / `events.csv` / m4a 匯出、Cmd+1 至 4 色票、右欄 marker 書籤取消。
v0.3 已實作：TranscriptSummarizer 整份逐字稿摘要（`transcript_summary.json`）、右欄三區折疊排序、雲端整理（Text Cloud Assist，實機驗收通過）、五項功能引擎個別選擇、雲端離線轉錄稿（Audio Cloud ASR）、雲端字幕翻譯、重新轉錄入口、API key 存 Keychain、network client entitlement。
v0.3 後續：即時 ASR 雲端串流、自訂 AI prompt、兩小時級長錄驗收。

## 八、風險清單與對策

| # | 風險 | 影響 | 對策 |
|---|---|---|---|
| 1 | SpeechTranscriber 不支援 zh-TW | 主引擎不可用 | M0 spike 提早實測；SFSpeechRecognizer 備援；UI 明示當前引擎 |
| 2 | 中英夾雜辨識劣化 | 術語錯字 | 名詞表後處理校正（v0.2）；SPEC 列為已知限制 |
| 3 | 新 API 文件與行為落差 | M5 延期 | Mock 先行使 UI 與儲存零依賴；M5 對官方文件逐項驗證（source-driven） |
| 4 | 長 session 記憶體成長 | 三小時卡頓 | volatile 只留最新一筆；列表 lazy 渲染；segment 落盤後可釋放 |
| 5 | 系統睡眠中斷錄音 | 現場資料損失 | ProcessInfo.beginActivity 持有至停止 |
| 6 | PCM 磁碟用量（約 350MB/小時） | 空間不足 | 錄前檢查空間並警告；匯出可轉 m4a |
| 7 | 單鍵快捷與文字輸入衝突 | 誤觸/失效 | 焦點規則 + Cmd+1 至 4 全域替代 |
| 8 | 音訊格式不符引擎需求 | 轉寫無輸出 | AVAudioConverter 統一轉至引擎 bestAvailableAudioFormat |
| 9 | 沙盒 container 內檔案使用者不易找 | 體驗困惑 | Reveal in Finder 按鈕 + 標準匯出面板 |
| 10 | JSONL 寫入在斷電瞬間截斷 | 末行損毀 | 讀取時容忍尾行不完整；每筆 flush |

## 九、待驗證事項（實作時對官方文件確認）

1. ~~`SpeechTranscriber.supportedLocales` 是否含 zh-TW（M0 spike）~~：已驗證，支援且目標機器已安裝模型，見 `docs/spikes/2026-06-12-speech-zh-tw.md`。
2. ~~SpeechTranscriber 是否有 `contextualStrings` 等價的詞彙提示機制~~：已實作，`TranscriptionCoordinator` 取名詞表校正目標去重後經 `setContextualStrings` 餵入；`AppleSpeechEngine` 於 start 套進 analyzer 的 AnalysisContext，`LegacySFSpeechEngine` 用 `contextualStrings`。
3. volatile results 的更新頻率與 finalization 延遲特性（影響 UI 節流策略）。
4. AssetInventory 的下載進度回報方式（影響下載引導 UI）。
5. SpeechAnalyzer 對 pause 後重新 feed 的行為（決定 pause 時 keep-alive 還是 finalize 重啟）。
