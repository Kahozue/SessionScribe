# SessionScribe 架構文件

版本：1.0（2026-06-12）
對應規格：`docs/SPEC.md` 1.0

## 一、分層架構

```
┌─────────────────────────────────────────────────────┐
│ UI 層（SSUI，SwiftUI）                                │
│ NavigationSplitView 三欄、toolbar、view models        │
│ 只依賴 protocol 與值型別，不碰 AVFoundation / Speech   │
├─────────────────────────────────────────────────────┤
│ 領域層（SSCore）                                      │
│ SessionController（狀態機）、MarkerService、           │
│ ExportService、EngineSelector、MediaClock            │
├─────────────────────────────────────────────────────┤
│ 基礎設施層                                            │
│ SSAudio：AudioCaptureService、ChunkedAudioWriter、    │
│          AudioLevelMeter                             │
│ SSTranscription：AppleSpeechEngine、                  │
│          LegacySFSpeechEngine、MockTranscriptionEngine│
│ SSCore.Storage：SessionStore、JSONLWriter、           │
│          SessionLibrary（列表與崩潰恢復掃描）           │
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
| 沙盒無 network entitlement | Local Only 零網路由 OS 強制，entitlements 檔可被任何人驗證 |
| Mock engine 先於 Apple engine | UI 與儲存開發完全不被新 API 可用性卡住；CI 無需 macOS 26 語音模型 |
| 核心邏輯在 Swift Package | swift test 可 headless 執行；pbxproj 改動最小化，利於 GitHub 協作 |
| deployment target macOS 26 | 唯一目標機器即 macOS 26；SFSpeechRecognizer 備援解決的是 locale 缺口，與 OS 版本無關 |

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
├── LICENSE
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
        │   │   ├── Models/        （Session、TranscriptSegment、Marker、...）
        │   │   ├── Storage/       （SessionStore、JSONLWriter、SessionLibrary）
        │   │   ├── Export/        （MarkdownExporter、JSONExporter、CSVExporter）
        │   │   └── SessionController/
        │   ├── SSAudio/
        │   ├── SSTranscription/
        │   └── SSUI/
        │       ├── Sidebar/
        │       ├── Transcript/
        │       ├── Inspector/
        │       └── Components/    （StatusBanner、LevelMeter、MarkerButtons）
        └── Tests/
            ├── SSCoreTests/
            ├── SSAudioTests/
            └── SSTranscriptionTests/
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
四鍵 marker（Q/R/S/A + Cmd+1 至 4、焦點規則）、marker 即時落盤、Inspector 事件列表、MarkdownExporter、JSONExporter、CSVExporter（markers.csv）、匯出面板、第二個 session。
驗證：快速連按壓力測試；匯出檔案格式比對；單元測試。

### M4 Mock 引擎與即時逐字稿 UI
MockTranscriptionEngine、TranscriptionEngine protocol 接線、live transcript 列表（lazy 渲染）、volatile 淡色尾段與 finalized 區分、轉寫狀態指示、ASR 錯誤注入測試。
驗證：無新 API 環境下完整跑 UI；模擬 ASR 失敗錄音不中斷。

### M5 Apple 引擎整合（完成即 v0.1）
AppleSpeechEngine（SpeechAnalyzer / SpeechTranscriber）、AssetInventory 模型檢查與下載引導、locale 執行期檢查、EngineSelector 降級鏈、LegacySFSpeechEngine、引擎狀態 UI。
驗證：實機 zh-TW 轉寫；v0.1 全部 21 條驗收標準逐條檢核。

### v0.2 與 v0.3
v0.2：模板系統、自定義 marker type、EventDraftBuilder、設定頁、segment 播放、名詞表校正。
v0.3：雲端整理與雲端 ASR（opt-in、加回 network entitlement）。

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
2. SpeechTranscriber 是否有 `contextualStrings` 等價的詞彙提示機制。
3. volatile results 的更新頻率與 finalization 延遲特性（影響 UI 節流策略）。
4. AssetInventory 的下載進度回報方式（影響下載引導 UI）。
5. SpeechAnalyzer 對 pause 後重新 feed 的行為（決定 pause 時 keep-alive 還是 finalize 重啟）。
