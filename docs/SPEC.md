# SessionScribe 規格書

版本：1.1（2026-06-12；1.0 同日敲定，1.1 增補第十五節使用者新增功能）
來源：`aim.md` 原始需求，加上敲定階段的修訂決議。本文件是開發依據，與 aim.md 衝突時以本文件為準。

## 一、產品定位

macOS 原生桌面應用程式，核心能力：

1. 建立錄音與轉寫 session。
2. 錄下完整音訊，原始錄音是最高優先級資產。
3. 以 macOS 26 Tahoe 的 SpeechAnalyzer / SpeechTranscriber 作為主要本機 ASR 引擎。
4. 顯示即時轉寫，volatile 與 finalized 結果在 UI 上明確區分。
5. 以極少量操作建立事件標記（問題、必改、建議、重要回答）。
6. 依場景模板將逐字稿與標記整理成結構化筆記（v0.2）。
7. 匯出 Markdown、JSON、CSV。
8. 本機處理與資料不外流是預設原則，雲端功能必須使用者明確啟用（v0.3）。

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
8. **沙盒策略**：啟用 App Sandbox，entitlements 只含 `com.apple.security.app-sandbox` 與 `com.apple.security.device.audio-input`，不含任何 network entitlement。Local Only 的零網路由作業系統強制保證。Session 存放於 app container 的 Application Support，提供 Reveal in Finder 與標準匯出面板。v0.3 加入雲端功能時才加回 network client entitlement，並於 README 說明驗證方式。
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
7. 所有 manual marker 增量寫入磁碟並 flush。
8. 所有 AI 產生的結構化結果標記 `needs_review: true`。
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
2. **Text Cloud Assist**（v0.3）：音訊留本機，只把使用者選定的逐字稿或結構化請求傳給雲端 LLM，啟用前明確提醒。
3. **Audio Cloud ASR**（v0.3）：允許音訊片段傳雲端 ASR，啟用前明確提醒，預設關閉，API key 只從本機設定或環境變數讀取，提供安全輸入介面。

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
├── events.json               （v0.2）
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
  "app_version": "0.1.0"
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

### manual_markers.jsonl（append-only）

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

### events.json（v0.2，structured events）

沿用 aim.md 第八節欄位，時間欄位改為 `start_seconds` / `end_seconds`，必含 `needs_review`、`source_segment_ids`、`source_marker_ids`。以暫存檔加原子改名方式寫入。

## 九、UI 與 HCI 需求

### 佈局

三欄式 macOS 佈局（`NavigationSplitView`）：

1. Sidebar：session 列表、模板（v0.2）、設定入口。
2. Main content：即時逐字稿。
3. Inspector：事件標記列表、結構化筆記（v0.2）、匯出、狀態。

頂部 toolbar：New Session、Start、Pause、Resume、Stop、Export、隱私模式指示、ASR 引擎狀態、錄音時長、音量指示。

### 即時轉寫區

- finalized：正常字重、穩定、可引用。
- volatile：較淡或半透明，視覺上明確表達未定稿，更新時就地替換。
- segment hover 顯示時間範圍；點擊 segment 播放對應音訊（v0.2）。

### 事件標記區

- 四個大按鈕加快捷鍵：Q 問題、R 必改、S 建議、A 重要回答。
- 按下立即建立 marker，對齊當前媒體時間，零確認步驟。
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

v0.2 增加：模板化 `structured_notes.md`（論文口試格式照 aim.md 十五節範例）、`events.json`、`events.csv`。Markdown 格式依模板而不同。

## 十一、自定義能力與版本歸屬

資料模型自始預留，UI 分版實作：

| 能力 | 版本 |
|---|---|
| 自定義 marker type | v0.2 |
| 自定義模板、event type、topic taxonomy | v0.2 |
| 自定義匯出欄位、Markdown 輸出格式 | v0.2 |
| 自定義專有名詞表（後處理校正層） | v0.2 |
| 自定義 speaker role | v0.2 |
| 自定義快捷鍵 | v0.2 |
| 自定義 AI 整理 prompt | v0.3 |
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

模板系統（論文口試、會議、訪談、講座）、自定義 marker type、EventDraftBuilder（依 marker 時間戳取前後 30 至 90 秒 segments 生成 event draft，`needs_review: true`，可手動編輯）、設定頁、segment 點擊播放、專有名詞表校正、匯出 m4a 轉檔。

### v0.3

雲端整理（Text Cloud Assist）、雲端 ASR（Audio Cloud ASR）、API key 安全輸入、自定義 AI prompt。加回 network entitlement 並於 README 說明 Local Only 的驗證方式。

## 十三、測試策略

單元測試（swift test）：

- SessionStore 與 JSONL 寫入、原子性。
- MediaClock 跨 pause/resume 的時間計算。
- marker 與 segment 的時間戳關聯計算。
- 各 Exporter 的輸出格式。
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
9. 長時間錄音（2 小時級）留待現場前驗證。

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

## 十五、規格 1.1 新增功能（2026-06-12 使用者提出）

以下八項已確認納入，版本歸屬與設計決議如下：

1. **浮動即時逐字稿視窗**（M4）：獨立的 always-on-top 視窗顯示即時逐字稿，可自由調整大小，字級與主畫面共用設定，顯示完整捲動歷史而非只有最新一句。實作以 SwiftUI 第二個 Window scene 加 `.windowLevel(.floating)`；macOS 26 的 Liquid Glass 半透明特化列入待驗證清單，不阻塞功能。
2. **字體大小與外觀模式調整**（M4）：逐字稿字級可調（預設 14pt，範圍 11 至 28），外觀模式三選（跟隨系統、淺色、深色），設定持久化（AppStorage），主畫面與浮動視窗共用。
3. **逐字稿格式化顯示與時間軸跳轉**（M4 顯示、M6 播放跳轉）：segment 以卡片式排版呈現（時間戳徽章、內文、時間窗內 marker 內嵌徽章），可讀性優先於純文字流。格式化只在顯示層與匯出層進行，原始 transcript 文字不改（核心可靠性原則 4）。點擊 segment 依時間軸跳轉：即時畫面為捲動定位，錄音檢視頁為播放跳轉。
4. **選取匯出**（M3 匯出層、M4 介面）：逐字稿列表支援多選，將選取範圍匯出為排版良好的 Markdown；匯出器一律接受 segment 子集，全量匯出是子集的特例。
5. **錄音檢視頁面**（M6）：sidebar 點選 session 進入檢視頁，顯示 metadata、音訊播放控制（依 manifest 串接 chunk 播放、進度條）、逐字稿全文與 marker 列表，點 segment 跳轉播放位置。
6. **匯入音檔**（M6）：可開啟音訊檔（caf、wav、m4a、mp3、aiff）建立 `source: "imported"` 的 session，音檔複製進 `audio/` 並重建 manifest；匯入時可選擇是否立即離線轉寫（走同一套 TranscriptionEngine，自檔案讀 buffer 餵入）。匯入歷史即 session 列表，imported session 有標示。metadata 新增 `source` 欄位（`recorded` 或 `imported`），舊檔缺欄位視為 `recorded`，schema_version 不變。
7. **分類與批次管理**（M7）：session 列表支援多選、批次刪除（需確認）、批次移動分類。分類可自訂名稱、可隱藏、可排序，定義存於 sessions 根目錄的 `library.json`；metadata 新增可空欄位 `category_id`，舊檔缺欄位視為未分類。
8. **App icon**（M8，最後執行）：以 SVG 繪製後轉出 icns。
9. **跨逐字稿搜尋**（M7）：搜尋列輸入文字，跨所有 session 的 segments 與 marker note 搜尋（不分大小寫），結果依 session 分組、顯示時間戳與命中片段，點擊跳轉到該 session 檢視頁並定位該 segment。實作為 SSCore 的 TranscriptSearchService，檔案式線性掃描（session 數量級在百以內無需索引，之後需要再加 SQLite FTS）。
10. **歌詞式定位效果**（M6 檢視頁）：播放與定位採 Apple Music 歌詞風格：當前 segment 放大、全不透明、加粗，其餘 segment 縮小且降不透明度，切換帶 spring 動畫並自動置中；點擊任一 segment 跳轉播放位置。即時轉寫畫面的 volatile 尾段沿用同一視覺語言（淡色、就地替換）。
