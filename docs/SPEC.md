# SessionScribe 規格書

版本：1.3（2026-06-13；1.1 增補第十五節使用者新增功能，1.2 對齊 v0.2 已合併現況，1.3 增補 v0.3 摘要、雲端整理與驗收狀態）
來源：`aim.md` 原始需求，加上敲定階段的修訂決議。本文件是開發依據，與 aim.md 衝突時以本文件為準。

目前實作狀態：v0.1 的 M0 至 M8 已完成並合併到 `main`；v0.2 驗收通過。v0.3 已開始，包含整份逐字稿摘要（本機 Apple Foundation Models）、右欄摘要／結構化事件／標記排序，以及兩小時級長錄測試改列 v0.3 驗收項目。雲端整理（Text Cloud Assist）已實作並通過實機驗收（2026-06-14）：事件整理與整份摘要兩項操作新增 OpenAI 相容／Anthropic／Gemini 三種雲端後端，本機與雲端並存、由使用者選用，Local Only 由程式層堅守。雲端 ASR（Audio Cloud ASR）尚未開始。

## 一、產品定位

macOS 原生桌面應用程式，核心能力：

1. 建立錄音與轉寫 session。
2. 錄下完整音訊，原始錄音是最高優先級資產。
3. 以 macOS 26 Tahoe 的 SpeechAnalyzer / SpeechTranscriber 作為主要本機 ASR 引擎。
4. 顯示即時轉寫，volatile 與 finalized 結果在 UI 上明確區分。
5. 以極少量操作建立事件標記（問題、必改、建議、重要回答）。
6. 依場景模板將逐字稿與標記整理成結構化筆記（v0.2 已實作）。
7. 以本機 AI 產生整份逐字稿摘要（v0.3）。
8. 匯出 Markdown、JSON、CSV。
9. 本機處理與資料不外流是預設原則；本機 AI 摘要與整理延續 Local Only，雲端功能必須使用者明確啟用（v0.3）。

短期場景是碩士論文口試。長期場景包含課堂講座、會議記錄、訪談、研究討論、讀書會、專案會議、客戶訪談、研討會、個人語音筆記。資料模型、UI 文案與功能設計不得綁死在論文口試，論文口試只是預設模板之一。

## 二、敲定階段的修訂決議

以下十項是 aim.md 之外新增或修改的決議，全部已確認：

1. **時間戳用秒數**：資料模型的 canonical 時間格式是媒體時間秒數（Double，從錄音起點累計，不含暫停）。格式化字串只在 UI 與匯出時產生。每筆資料另存 `created_at` 牆鐘時間（ISO-8601）。
2. **音訊 chunk 用索引不用合併**：新增 `audio/manifest.json` 記錄每個 chunk 的檔名、媒體時間起點、長度。停止錄音時只完成索引，合併為單一檔案是可選的匯出功能。
3. **session_id 加短亂數後綴**：格式 `YYYY-MM-DD_HHmm_xxxx`，避免同分鐘碰撞，保留排序性。
4. **崩潰恢復納入驗收**：App 啟動時偵測 `ended_at == null` 的 session，標記為已恢復，重建 chunk 索引，使用者可看到已保存的逐字稿與 marker。
5. **MVP 的 CSV 匯出對象是 markers**：`markers.csv` 包含時間、類型、備註、鄰近 segment 文字。`events.csv` 隨 structured events 移至 v0.2。
6. **快捷鍵焦點規則**：Q/R/S/A 單鍵快捷只在逐字稿區持有焦點時生效；Cmd+1 至 Cmd+4 為全域替代；大按鈕永遠可點。任何文字輸入框聚焦時單鍵不得觸發標記。
7. **防睡眠**：錄音期間以 `ProcessInfo.processInfo.beginActivity` 持有 assertion 阻止 idle sleep，停止錄音時釋放。
8. **沙盒策略**：啟用 App Sandbox。v0.3 雲端整理出貨後，entitlements 含 `com.apple.security.app-sandbox`、`com.apple.security.device.audio-input`、`com.apple.security.files.user-selected.read-write` 與 `com.apple.security.network.client`。單一 app 帶 network client entitlement，Local Only 的零網路保證自 OS 強制降為程式層保證：唯一的 `URLSession` 只在 `SSCore/Cloud` 層，且只在「總開關開 AND 引擎=雲端 AND 供應商與 key 齊備」時才被建構（`AssistResolver` 集中守門，並有單元測試確保 Local Only 不建構任何 client）。以 in-app guard、持續 UI 狀態標、啟用前警告、README 可驗證性說明補強。Session 存放於 app container 的 Application Support，提供 Reveal in Finder 與標準匯出面板。
9. **文件歸宿**：aim.md 保留原樣作為原始需求書，本 SPEC.md 是正式規格。
10. **音訊格式**：canonical 格式為 PCM CAF chunks（48kHz 單聲道 16-bit 起，依輸入裝置調整）。CAF 容器對中斷寫入容錯最佳。磁碟代價約每兩小時 700MB，錄音前檢查可用空間，匯出時可選轉 m4a。

## 三、目標平台與技術棧

- macOS 26 Tahoe，deployment target 為 macOS 26（不向下相容）。
- 開發機：MacBook Air M3、24GB RAM、最新版 Xcode。
- Swift / SwiftUI 為主，必要時 AppKit interop（視窗、快捷鍵、menu bar、檔案操作）。
- AVFoundation：錄音、音訊檔案寫入、播放。
- Speech framework：SpeechAnalyzer / SpeechTranscriber / DictationTranscriber / SFSpeechRecognizer。
- AssetInventory：語音模型可用性檢查與下載引導。
- Swift Concurrency：actor、async/await、AsyncStream。
- 儲存：MVP 用檔案式（JSON / JSONL），後續可加 SwiftData 或 SQLite 做 session 索引。
- 禁用 Electron / Tauri。
- 核心邏輯放在本地 Swift Package（SessionScribeKit），app target 為薄殼，`swift test` 可離開 Xcode GUI 執行。

## 四、核心可靠性原則

1. 原始錄音是最高優先級。
2. ASR 失敗時錄音必須繼續。
3. 摘要或結構化整理失敗時，錄音與逐字稿仍要保存。
4. 原始逐字稿不得被摘要覆蓋。
5. volatile transcript 不得覆蓋 finalized transcript。
6. 所有 finalized segment 增量寫入磁碟並 flush。
7. 所有 manual marker 建立時增量寫入磁碟並 flush；取消標記時以原子重寫保存剩餘 markers。
8. 所有 AI 產生的結構化事件標記 `needs_review: true`；整份摘要不在 UI 顯示需複查標籤。
9. 結構化結果必須能追溯到原始 transcript segment。
10. 雲端功能預設關閉；Local Only 模式由 entitlements 層級保證零網路。
11. API key 不得寫入程式碼，只從本機設定或環境變數讀取。
12. App 崩潰後至少保留已錄音 chunk、已完成轉寫 segment、已建立 marker，且重啟後可恢復檢視。
13. 錄音期間阻止系統 idle sleep。
14. UI 持續明示目前狀態：未錄音、錄音中、暫停、轉寫中、ASR 錯誤、儲存中、匯出完成。

## 五、ASR 需求與 fallback 鏈

主引擎與備援順序：

1. SpeechAnalyzer + SpeechTranscriber（on-device，volatile + finalized + timing metadata）。
2. DictationTranscriber。
3. SFSpeechRecognizer（確定支援 zh-TW）。
4. 純錄音模式：保留完整音訊，口試後離線轉寫。

要求：

- zh-TW 優先。SpeechTranscriber 對 zh-TW 的支援必須於執行期以 `supportedLocales` 檢查，不得假設可用。建立 session 時做 locale 可用性檢查，UI 明示本場實際使用的引擎。
- 開發第一週執行 spike，在目標機器上實測 zh-TW 可用性，結果決定主引擎人選。
- ASR API 不可用不得導致錄音功能失效。
- UI 不得直接依賴 SpeechAnalyzer 具體類別，必須透過 `TranscriptionEngine` protocol 抽象，方便未來加入 WhisperKit、whisper.cpp、雲端 ASR。
- 實作三個引擎：`AppleSpeechEngine`、`LegacySFSpeechEngine`、`MockTranscriptionEngine`（UI 測試與無新 API 環境用）。

已知限制（明示給使用者）：

- 中英夾雜語音的英文術語辨識會劣化，這是單一 locale 引擎的能力限制。緩解手段是專有名詞表後處理校正（v0.2）。
- 專有名詞表分兩層：第一層是轉寫後的文字替換校正規則（保證可行）；第二層是引擎層詞彙提示（SFSpeechRecognizer 有 `contextualStrings`，SpeechTranscriber 的對應能力需對官方文件驗證後盡力支援）。

## 六、音訊錄製需求

1. 支援選擇輸入裝置。
2. 顯示音量 level meter。
3. 以 AVAudioEngine input tap 取得 buffer，PCM CAF 增量寫入。
4. 每 1 至 5 分鐘切一個 chunk（預設 5 分鐘，可設定），崩潰最多損失當前 chunk 的緩衝區間。
5. `audio/manifest.json` 記錄 chunk 索引；停止時完成索引，不做破壞性合併。
6. pause / resume 正確記錄時間軸：媒體時間由累計音訊 frame 數除以取樣率得出，暫停期間自然停止。
7. 轉寫時間戳與音訊時間軸一致（同一個 MediaClock）。
8. ASR 與錄音寫入解耦：同一個 buffer 流分發給兩個獨立消費者，任一方失敗不影響另一方。
9. 麥克風權限錯誤清楚提示，未授權時提供引導（含開啟系統設定的連結）。
10. 錄音前檢查磁碟可用空間，不足時警告。

## 七、隱私模式

1. **Local Only**（預設）：音訊與逐字稿留本機，使用 Apple 本機 ASR，零網路請求（entitlements 強制）。
2. **Text Cloud Assist**（v0.3 已實作）：音訊永遠留本機，只把使用者選定的逐字稿或結構化請求傳給雲端 LLM；事件整理與整份摘要兩項操作可選雲端後端，支援 OpenAI 相容／Anthropic／Gemini 三種線路格式，每供應商可設 base URL／model，API key 存 Keychain（不進 UserDefaults、不寫檔）。首次開啟總開關跳警告，產物一律 `needs_review`。詳見規格 1.3。
3. **Audio Cloud ASR**（v0.3，未實作）：允許音訊片段傳雲端 ASR，啟用前明確提醒，預設關閉，API key 只從本機設定讀取，提供安全輸入介面。

UI 持續顯示目前模式；非 Local Only 時有明顯但不干擾的提示。

## 八、資料模型與檔案格式

所有檔案含 `schema_version` 欄位。Session 資料夾結構：

```
<session_id>/
├── metadata.json
├── audio/
│   ├── manifest.json
│   └── chunk_0001.caf ...
├── live_segments.jsonl
├── manual_markers.jsonl
├── volatile_debug.jsonl      （可選，預設關閉）
├── events.json               （v0.2，可選）
├── transcript_summary.json   （v0.3，可選）
└── exports/
```

### metadata.json

```json
{
  "schema_version": 1,
  "session_id": "2026-06-15_1000_a3f2",
  "title": "碩士論文口試 - 第一場",
  "template_id": "thesis_defense",
  "created_at": "2026-06-15T10:00:00+08:00",
  "started_at": "2026-06-15T10:01:12+08:00",
  "ended_at": null,
  "locale": "zh-TW",
  "asr_engine": "SpeechAnalyzer",
  "privacy_mode": "local_only",
  "audio_input": "MacBook Air Microphone",
  "recovered": false,
  "notes": "",
  "app_version": "0.2.0"
}
```

`ended_at == null` 且非進行中即視為崩潰殘留，啟動時進入恢復流程並設 `recovered: true`。

### audio/manifest.json

```json
{
  "schema_version": 1,
  "sample_rate": 48000,
  "channels": 1,
  "chunks": [
    { "file": "chunk_0001.caf", "start_seconds": 0.0, "duration_seconds": 300.0, "created_at": "..." }
  ]
}
```

### live_segments.jsonl（每行一筆，append-only）

```json
{
  "schema_version": 1,
  "segment_id": "seg_0001",
  "session_id": "2026-06-15_1000_a3f2",
  "start_seconds": 12.3,
  "end_seconds": 18.7,
  "text": "請問你為什麼選擇這個資料集？",
  "is_final": true,
  "language": "zh-TW",
  "engine": "SpeechAnalyzer",
  "model": "system",
  "confidence": null,
  "created_at": "..."
}
```

volatile 結果只存在記憶體；debug 模式可另寫 `volatile_debug.jsonl`，永不混入 live_segments。

### manual_markers.jsonl

```json
{
  "schema_version": 1,
  "marker_id": "m_0001",
  "session_id": "2026-06-15_1000_a3f2",
  "media_seconds": 2538.0,
  "type": "question",
  "label": "問題",
  "note": "",
  "nearest_segment_ids": ["seg_0132"],
  "created_at": "..."
}
```

marker 與 segment 的關聯以 `media_seconds` 時間戳為唯一真相：按下標記時附近語音可能尚未定稿，`nearest_segment_ids` 只是寫入當下的快照，讀取與匯出時一律由時間戳動態重算（取 marker 時間點前後視窗內重疊的 finalized segments）。

預設 marker types：`question`（問題）、`required_revision`（必改）、`suggestion`（建議）、`important_answer`（重要回答）。使用者可自定義（v0.2 提供 UI，資料模型自始即支援）。

建立 marker 時採 append+flush，確保現場操作即時落盤。使用者在右欄點擊書籤圖示取消 marker 時，`SessionStore.saveMarkers(_:)` 會以暫存檔加原子改名重寫剩餘 markers，再重新開啟 append handle。

### events.json（v0.2，structured events）

沿用 aim.md 第八節欄位，時間欄位改為 `start_seconds` / `end_seconds`，必含 `needs_review`、`source_segment_ids`、`source_marker_ids`。以暫存檔加原子改名方式寫入。v0.2 目前支援兩條來源：`EventDraftBuilder` 依 marker 時間窗生成草稿；`EventOrganizer` 在本機 Apple Foundation Models 可用時，可從 finalized segments 直接生成草稿，或補齊既有 events 的 topic、summary、action item 等語意欄位。AI 產物一律 `needs_review: true`，且必須保留可追溯的原始逐字稿內容與來源 segment。

### transcript_summary.json（v0.3，整份逐字稿摘要）

存放整份 finalized transcript 的摘要、重點、待辦與來源 segment ids。由 `TranscriptSummarizer` 透過本機 Apple Foundation Models 產生，寫入採暫存檔加原子改名。摘要不得覆蓋 `live_segments.jsonl`，也不得把摘要內容回寫到原始逐字稿；右欄摘要區不顯示需複查標籤。

## 九、UI 與 HCI 需求

### 佈局

三欄式 macOS 佈局（`NavigationSplitView`）：

1. Sidebar：session 列表、模板（v0.2）、設定入口。
2. Main content：即時逐字稿。
3. Inspector：整份逐字稿摘要（v0.3）、結構化事件（v0.2）、事件標記、匯出、狀態。右欄順序固定為摘要、結構化事件、標記。

頂部 toolbar：New Session、Start、Pause、Resume、Stop、Export、隱私模式指示、ASR 引擎狀態、錄音時長、音量指示。

### 即時轉寫區

- finalized：正常字重、穩定、可引用。
- volatile：較淡或半透明，視覺上明確表達未定稿，更新時就地替換。
- segment hover 顯示時間範圍；點擊 segment 播放對應音訊（v0.2）。

### 摘要區（v0.3）

- 位於右欄最上方，標題為「逐字稿摘要」，可用 chevron 摺疊。
- 按「AI 產生摘要」以本機 AI 對整份 finalized transcript 生成摘要、重點與待辦；已有摘要時同一按鈕可重新產生。
- 沒有逐字稿、AI 正在處理、或本機模型不可用時，按鈕停用並顯示原因。
- 摘要產物顯示來源 segment 數，不取代原始逐字稿，不顯示需複查標籤。

### 結構化事件區（v0.2）

- 位於摘要區下方，標題為「結構化事件」，可用 chevron 摺疊。
- 「依標記彙整」依 marker 前後文生成事件草稿；「AI 產生草稿／AI 整理」以本機 AI 從整份 finalized transcript 生成或補齊事件欄位。
- 按「依標記彙整」或「AI 產生草稿／AI 整理」後，中欄已標記位置不得消失，右欄 marker 色票不得退回單色。

### 事件標記區

- 位於結構化事件區下方，標題為「事件標記」（有標記時顯示數量），可用 chevron 摺疊；右欄三區（摘要、結構化事件、事件標記）皆可分別摺疊。
- 四個大按鈕加快捷鍵：Q 問題、R 必改、S 建議、A 重要回答。
- Cmd+1 至 Cmd+4 對應目前模板的四個主要 marker type，視覺色票固定為藍、紅、綠、紫；中欄 inline marker 與右欄事件列表使用同一套色票。
- 按下立即建立 marker，對齊當前媒體時間，零確認步驟。
- 右欄事件列表中的書籤提示可點擊，用於取消既有 marker；取消後中欄 inline marker、右欄事件列表與下次載入的 `manual_markers.jsonl` 都必須同步移除。
- 可選 note 欄位，不阻塞錄音與標記流程。
- 快捷鍵焦點規則見第二節第 6 條。

### 設計原則

1. 低認知負荷：使用者正在旁聽與手寫，介面不得干擾。
2. 高狀態可見性：錄音中、暫停、錯誤、匯出完成一眼可辨；不得只用顏色傳達狀態，需搭配文字、圖示或形狀。
3. 快速可逆：標記可事後修改，不要求當下精準。
4. 漸進揭露：主畫面簡潔，進階設定收進設定頁。
5. 資料安全感：持續顯示本機或雲端模式。
6. 長時間閱讀舒適：行距、字重、對比度適合 1 至 3 小時使用。
7. 尊重 macOS 原生行為：Command 快捷鍵、系統字體、深色模式、視窗 resize、sidebar、toolbar，符合 macOS 26 Liquid Glass 設計方向。
8. 動畫只用於狀態轉換與回饋。

## 十、匯出需求

v0.1 每個 session 可匯出：

1. raw audio（CAF chunks 原樣，或可選合併轉 m4a）
2. `transcript.md`（含 metadata 區塊與依時間排序的 finalized segments、markers 內嵌標示）
3. `live_segments.jsonl`
4. `manual_markers.jsonl`
5. `markers.csv`

v0.2 已增加：模板化 `structured_notes.md`（論文口試格式照 aim.md 十五節範例，其餘模板用通用版）、`events.json`、`events.csv`、單一 `<session_id>.m4a`。events 可來自既有 `events.json`，或匯出時由 markers 即時生成草稿。

## 十一、自定義能力與版本歸屬

資料模型自始預留，UI 分版實作。以下為 2026-06-13 現況：

| 能力 | 現況 |
|---|---|
| 內建模板選擇（論文口試、會議、訪談、講座） | v0.2 已實作 |
| 自定義 marker type | v0.2 已實作 |
| 自定義專有名詞表（後處理校正層） | v0.2 已實作 |
| 結構化事件草稿、編輯、events/structured notes 匯出 | v0.2 已實作 |
| 本機 AI 事件生成與欄位整理 | v0.2 已實作，依 Apple Foundation Models 可用性啟用 |
| 本機 AI 整份逐字稿摘要 | v0.3 已實作，依 Apple Foundation Models 可用性啟用 |
| 雲端整理（Text Cloud Assist，事件整理＋整份摘要） | v0.3 已實作並驗收通過，OpenAI 相容／Anthropic／Gemini，使用者明確啟用 |
| 雲端 ASR（Audio Cloud ASR） | 未實作，保留後續版本 |
| 自定義模板、event type、topic taxonomy | 未實作，保留後續版本 |
| 自定義匯出欄位、Markdown 輸出格式 | 未實作，保留後續版本 |
| 自定義 speaker role presets | 未實作，保留後續版本 |
| 自定義快捷鍵 | 未實作，保留後續版本 |
| 自定義 AI 整理 prompt | v0.3 或後續版本 |
| 引擎層詞彙提示 | 視 API 驗證結果 |

## 十二、版本切分

### v0.1（MVP）驗收標準

1. App 可在 macOS 啟動。
2. 可建立新 session。
3. 可開始錄音。
4. 可暫停與繼續。
5. 可停止並保存 session。
6. 錄音資料增量保存（CAF chunks + manifest）。
7. ASR 失敗時錄音不中斷。
8. 可用 SpeechAnalyzer / SpeechTranscriber 本機轉寫，API 不可用時自動退至 fallback 或 mock。
9. 可顯示 live transcript。
10. volatile 與 finalized 在 UI 上有區分。
11. 可按 Q/R/S/A（及 Cmd+1 至 4）建立 marker。
12. marker 立即寫入磁碟。
13. finalized segment 立即寫入磁碟。
14. 可匯出 Markdown、JSON、CSV（markers.csv）。
15. 可建立第二個 session。
16. Local Only 模式零網路（entitlements 層級驗證）。
17. App 強制終止後重啟，可恢復檢視已保存的 chunks、segments、markers。
18. README 說明安裝、執行、麥克風授權、建立 session、匯出。
19. 專案不含 API key 或敏感資料。
20. UI 具備基本 HCI 品質。
21. 提供 mock transcription mode。

### v0.2

已合併到 main 並驗收通過的功能：模板系統（論文口試、會議、訪談、講座）、自定義 marker type、EventDraftBuilder（依 marker 時間戳取前後 30 至 90 秒 segments 生成 event draft，`needs_review: true`，可手動編輯）、本機 EventOrganizer（Apple Foundation Models 可用時，從 finalized segments 生成 events 或整理既有 events）、設定頁、segment 點擊播放、專有名詞表校正、`structured_notes.md` / `events.json` / `events.csv` / m4a 匯出、Cmd+1 至 4 色票、中欄 inline marker 保留、右欄 marker 書籤取消。

仍待補足或另排版本：自訂模板、自訂匯出版型、自訂快捷鍵、自訂 speaker role presets、自訂 AI prompt。

### v0.3

已開始：右欄最上方整份逐字稿摘要（本機 AI 生成，`transcript_summary.json` 原子保存，可折疊，不顯示需複查標籤）、兩小時級長錄測試。已實作：雲端整理（Text Cloud Assist，三格式轉接器、API key 存 Keychain、設定頁雲端分頁、非 Local Only 狀態標、network client entitlement，詳見規格 1.3）。後續：雲端 ASR（Audio Cloud ASR）、自定義 AI prompt。

## 十三、測試策略

單元測試（swift test）：

- SessionStore 與 JSONL 寫入、原子性。
- MediaClock 跨 pause/resume 的時間計算。
- marker 與 segment 的時間戳關聯計算。
- 各 Exporter 的輸出格式。
- EventDraftBuilder、EventOrganizer、marker 色票與取消標記的回歸測試。
- TranscriptSummary 與 TranscriptSummarizer 的資料格式、來源追溯與摘要區無需複查標籤。
- 崩潰恢復掃描邏輯。

整合與手動測試（照 aim.md 十八節）：

1. 錄音中模擬 ASR 失敗（MockEngine 注入錯誤）。
2. 錄音中 `kill -9` 後檢查已保存 chunks 並驗證恢復流程。
3. 快速連按 marker 按鈕。
4. pause / resume 多次後驗證時間軸。
5. 建立兩個 session。
6. 匯出空 transcript 與含多個 marker 的 transcript。
7. Local Only 模式以 entitlements 檢查驗證零網路。
8. 深色與淺色模式可讀性。
9. v0.2 標記色票、右欄書籤取消、結構化事件草稿、AI 整理後中欄 inline marker 保留。
10. v0.3 兩小時級長錄測試另列驗收。

## 十四、禁止事項

1. 第一版不做 speaker diarization。
2. 第一版不做 iPhone / iPad companion app（iPad 需求以螢幕鏡像處理）。
3. 第一版不依賴雲端 API。
4. 摘要不得覆蓋原始逐字稿。
5. 不得只把資料存在記憶體。
6. API key 不得寫進程式碼。
7. 不得預設上傳音訊。
8. 不得把論文口試寫死成唯一場景。
9. 不得忽略深色模式。
10. 不得忽略麥克風權限。
11. 不得忽略錄音中斷與 ASR 失敗。
12. 不得用裝飾性動畫干擾記錄。
13. marker 建立不得有多步驟確認。
14. 不得用顏色作為唯一狀態提示。
15. 不得假設使用者有網路。
16. 不得假設 SpeechAnalyzer 支援所有 locale。
17. 不得硬綁單一 ASR 引擎。
18. 不得犧牲錄音穩定性換取功能。

## 十五、規格 1.1 已納入功能（2026-06-12 使用者提出）

以下項目已確認納入，版本歸屬與設計決議如下：

1. **浮動即時逐字稿視窗**（M4）：獨立的 always-on-top 視窗顯示即時逐字稿，可自由調整大小，字級與主畫面共用設定，顯示完整捲動歷史而非只有最新一句。實作以 SwiftUI 第二個 Window scene 加 `.windowLevel(.floating)`；macOS 26 的 Liquid Glass 半透明特化列入待驗證清單，不阻塞功能。
2. **字體大小與外觀模式調整**（M4）：介面字級可調（預設 16pt，範圍 11 至 28），同時覆蓋側欄、工具列、右欄、設定、浮動視窗與逐字稿內文；外觀模式三選（跟隨系統、淺色、深色），設定持久化（AppStorage），主畫面與浮動視窗共用。
3. **逐字稿格式化顯示與時間軸跳轉**（M4 顯示、M6 播放跳轉）：segment 以卡片式排版呈現（時間戳徽章、內文、時間窗內 marker 內嵌徽章），可讀性優先於純文字流。格式化只在顯示層與匯出層進行，原始 transcript 文字不改（核心可靠性原則 4）。點擊 segment 依時間軸跳轉：即時畫面為捲動定位，錄音檢視頁為播放跳轉。
4. **選取匯出**（M3 匯出層、M4 介面）：逐字稿列表支援多選，將選取範圍匯出為排版良好的 Markdown；匯出器一律接受 segment 子集，全量匯出是子集的特例。
5. **錄音檢視頁面**（M6）：sidebar 點選 session 進入檢視頁，顯示 metadata、音訊播放控制（依 manifest 串接 chunk 播放、進度條）、逐字稿全文與 marker 列表，點 segment 跳轉播放位置。
6. **匯入音檔**（M6）：可開啟音訊檔（caf、wav、m4a、mp3、aiff）建立 `source: "imported"` 的 session，音檔複製進 `audio/` 並重建 manifest；匯入時可選擇是否立即離線轉寫（走同一套 TranscriptionEngine，自檔案讀 buffer 餵入）。匯入歷史即 session 列表，imported session 有標示。metadata 新增 `source` 欄位（`recorded` 或 `imported`），舊檔缺欄位視為 `recorded`，schema_version 不變。
7. **分類與批次管理**（M7）：session 列表支援多選、批次刪除（需確認）、批次移動分類。分類可自訂名稱、可隱藏、可排序，定義存於 sessions 根目錄的 `library.json`；metadata 新增可空欄位 `category_id`，舊檔缺欄位視為未分類。
8. **App icon**（M8，最後執行）：以 SVG 繪製後轉出 icns。
9. **跨逐字稿搜尋**（M7）：搜尋列輸入文字，跨所有 session 的 segments 與 marker note 搜尋（不分大小寫），結果依 session 分組、顯示時間戳與命中片段，點擊跳轉到該 session 檢視頁並定位該 segment。實作為 SSCore 的 TranscriptSearchService，檔案式線性掃描（session 數量級在百以內無需索引，之後需要再加 SQLite FTS）。
10. **歌詞式定位效果**（M6 檢視頁）：播放與定位採 Apple Music 歌詞風格：當前 segment 放大、全不透明、加粗，其餘 segment 縮小且降不透明度，切換帶 spring 動畫並自動置中；點擊任一 segment 跳轉播放位置。即時轉寫畫面的 volatile 尾段沿用同一視覺語言（淡色、就地替換）。

## 十六、規格 1.3 雲端整理（Text Cloud Assist，2026-06-13）

第七節隱私模式第 2 項 Text Cloud Assist 的實際功能。為既有的事件整理（`EventOrganizer`）與整份摘要（`TranscriptSummarizer`）兩項操作新增雲端 LLM 可選後端，本機與雲端並存、由使用者選用。

1. **三格式轉接器**：`SSCore/Cloud/` 新增 `CloudLLMClient` 協定與三個格式轉接器——OpenAI 相容（Chat Completions，涵蓋 OpenAI、DeepSeek 及任何相容端點）、Anthropic（Messages API，`x-api-key` + `anthropic-version`）、Gemini（`generateContent`）。每供應商可設 base URL、API key、model 字串。transport 以可注入的 `HTTPTransport`（預設 `URLSession`）封裝，測試以 stub 注入不打真網路。
2. **重用本機可靠性邏輯**：`CloudEventOrganizer` / `CloudTranscriptSummarizer` 組 prompt（重用本機 `EventOrganizer.instructions` / `generateInstructions` 與 `TranscriptSummarizer.instructions`）、要求 JSON 輸出、容錯解析（剝 ```json 圍欄、括號配對掃描取第一個 JSON 物件或陣列），再重用 `applyOrganized` / `buildEvent` / `buildSummary`，確保時間重疊回推、`source_*` 追溯、`needsReview` 強制 true 等行為與本機一致。
3. **引擎路由與 Local Only 程式層強制**：`EventOrganizing` / `TranscriptSummarizing` 協定統一本機與雲端；`AssistResolver` 依 `CloudLLMSettings` 決定走本機或雲端，只有「總開關開 AND 引擎=雲端 AND 有 active 供應商 AND key 存在」才建構雲端 client，否則一律回本機。檢視頁三個 AI 入口（產生草稿、整理、摘要）經 `AssistResolver` 取實例。
4. **金鑰與設定**：供應商設定（id、format、顯示名、base URL、model）、active 供應商、總開關、引擎選擇存 UserDefaults（`CloudLLMSettings`，不含 key）；API key 存 Keychain（`kSecClassGenericPassword`，service `com.sessionscribe.cloud-llm`，account 為供應商 id），不進 UserDefaults、不寫檔。`KeychainStore` 協定便於測試注入假實作。設定頁新增「雲端」分頁：選格式、填 base URL／model、`SecureField` 輸入 key、測試連線（送極短 ping）。
5. **隱私強制與提示**：唯一的 `URLSession` 只在 `SSCore/Cloud` 層；首次開總開關跳警告（說明選定文字會送往供應商、音訊永遠不送、產物標需複查）；跑雲端操作時把該 session 的 `privacyMode` 記為 `text_cloud_assist`；非 Local Only 時主錄音畫面與檢視頁標頭顯示狀態標。只送選定文字（摘要送 finalized 逐字稿、整理送事件 content 或逐字稿片段），絕不送音訊或原始 chunk。
6. **錯誤處理**：雲端結果一律 `needsReview: true`；網路錯誤、401、429、逾時、JSON 解析失敗轉成清楚的中文錯誤訊息走既有 `errorMessage` 路徑；雲端失敗不影響錄音與逐字稿，可重試或改用本機。
7. **不在範圍（YAGNI）**：串流回應、自定義整理 prompt、Audio Cloud ASR、環境變數讀 key、多供應商備援、token 計費 UI、雙建構版本（Local-Only 無 entitlement 版）。
