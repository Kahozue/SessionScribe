# SessionScribe 資料格式

版本：1.3（2026-06-13，對齊 v0.3 摘要與驗收現況）
對應規格：`docs/SPEC.md` 1.3 第八節
實作位置：`Packages/SessionScribeKit/Sources/SSCore/`（Models 與 Storage）

## 一、通用編碼規則

由 `SSJSON` 統一提供編解碼器，所有持久化檔案遵守：

1. 所有檔案含 `schema_version` 欄位（目前為 1，見 `SchemaVersion.current`）。格式變更時遞增，讀取端據此遷移。
2. 鍵名一律 snake_case，以明確的 `CodingKeys` 對應，不依賴編碼器的自動轉換。
3. 牆鐘時間（`created_at`、`started_at`、`ended_at`）為 ISO-8601 字串，秒級精度。編碼輸出 UTC（`Z` 結尾），解碼接受任意時區偏移（如 `+08:00`）。
4. 媒體時間為秒數（Double），從錄音起點累計，不含暫停，由 MediaClock 以累計 frame 數除以取樣率得出。
5. optional 欄位（`started_at`、`ended_at`、`confidence`）編碼輸出明確 `null`，不省略鍵。
6. 鍵排序輸出，同一筆資料的編碼結果位元組層級穩定，利於測試比對與 diff。
7. JSONL 檔案一筆一行；字串內的換行由 JSON 跳脫保證不破壞行結構。

## 二、Session 資料夾結構

```
<session_id>/
├── metadata.json            原子寫入（暫存檔加改名）
├── audio/                   M2 起寫入 CAF chunks 與 manifest.json
├── live_segments.jsonl      append-only，每筆 append 後 fsync
├── manual_markers.jsonl     建立 marker 時 append+fsync；取消 marker 時原子重寫
├── events.json              v0.2 結構化事件，可選，存在時原子寫入
├── transcript_summary.json  v0.3 整份逐字稿摘要，可選，存在時原子寫入
└── exports/                 匯出產物（M3）
```

`SessionStore.create` 建立上述結構；同名目錄已存在視為錯誤（session id 的亂數後綴已避免正常碰撞）。

### session_id

格式 `YYYY-MM-DD_HHmm_xxxx`（`Session.makeID`）：本地時區的日期時間前綴保留排序性，4 字元十六進位亂數後綴避免同分鐘碰撞。

## 三、metadata.json

對應型別 `Session`。欄位與規格書第八節範例一致：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `schema_version` | Int | 目前為 1 |
| `session_id` | String | 同資料夾名稱 |
| `title` | String | 顯示標題 |
| `template_id` | String | 場景模板，如 `thesis_defense` |
| `created_at` | ISO-8601 | session 建立時刻 |
| `started_at` | ISO-8601 或 null | 首次開始錄音時刻 |
| `ended_at` | ISO-8601 或 null | 正常停止時刻；null 即崩潰殘留候選 |
| `locale` | String | 如 `zh-TW` |
| `asr_engine` | String | 本場實際使用的引擎名稱 |
| `privacy_mode` | String | `local_only`、`text_cloud_assist`、`audio_cloud_asr`；目前仍僅寫入 `local_only`，雲端模式保留給 v0.3 |
| `audio_input` | String | 輸入裝置名稱 |
| `recovered` | Bool | 曾經崩潰恢復 |
| `notes` | String | 使用者備註 |
| `app_version` | String | 寫入時的 app 版本 |
| `source` | String | `recorded` 或 `imported`（規格 1.1 第 6 項）；舊檔缺欄位視為 `recorded` |
| `category_id` | String 或 null | 分類 id（規格 1.1 第 7 項）；null 或缺欄位即未分類 |

寫入一律經 `Data.write(options: .atomic)`，崩潰瞬間不會留下半截 metadata。

## 四、live_segments.jsonl

對應型別 `TranscriptSegment`，一行一筆 finalized 結果。volatile 結果只存在記憶體，永不寫入本檔。欄位：`schema_version`、`segment_id`、`session_id`、`start_seconds`、`end_seconds`、`text`、`is_final`、`language`、`engine`、`model`、`confidence`（可 null）、`created_at`。

## 五、manual_markers.jsonl

對應型別 `Marker`，一行一筆。欄位：`schema_version`、`marker_id`、`session_id`、`media_seconds`、`type`、`label`、`note`、`nearest_segment_ids`、`created_at`。

`type` 是開放字串。內建四種由 `MarkerType.defaults` 提供：`question`（問題）、`required_revision`（必改）、`suggestion`（建議）、`important_answer`（重要回答）。自定義 type 自始即可寫入與讀回，v0.2 才提供管理 UI。

`nearest_segment_ids` 只是寫入當下的快照。marker 與 segment 的關聯以 `media_seconds` 為唯一真相，讀取與匯出時由時間戳動態重算。

建立 marker 時，`SessionStore.appendMarker(_:)` 走 JSONL append+fsync，確保現場按鍵後立即落盤。取消 marker 時，`SessionStore.saveMarkers(_:)` 會先關閉 append writer，將剩餘 markers 寫入暫存檔後原子改名覆蓋 `manual_markers.jsonl`，再重新開啟 append writer。這讓 UI 可真的移除右欄書籤與中欄 inline marker，而不是留下 tombstone。

## 六、JSONL 寫入與讀取語義

寫入（`JSONLWriter`）：

1. 開啟時定位到檔案尾端，append-only，不改寫既有內容。
2. 每筆 append 寫入單行 JSON 加換行，隨即 `synchronize()`（fsync），App 崩潰或斷電最多損失正在寫入的那一行。

例外：`manual_markers.jsonl` 的取消標記屬於事後編輯，不走 append tombstone；由 `SessionStore.saveMarkers(_:)` 以完整檔案原子重寫保存目前 marker 集合。

讀取（`JSONLReader`）：

1. 檔案不存在或為空回傳空陣列。
2. 最後一行解碼失敗視為截斷殘留並忽略（風險清單第 10 條：斷電瞬間的不完整尾行）。
3. 中段任何一行解碼失敗拋出 `ReadError.corruptedLine`，這代表資料損毀而非正常截斷，需要人工介入。

## 七、崩潰恢復掃描

`SessionLibrary.recoverCrashedSessions(activeSessionIDs:)` 於 App 啟動時執行：

1. 掃描 root 目錄下所有含可解析 metadata.json 的子目錄；散落檔案、缺 metadata 或 metadata 損毀的項目略過，不阻斷列表。
2. `ended_at == null`、不在 `activeSessionIDs`、且 `recovered == false` 的 session 視為崩潰殘留：標記 `recovered: true` 原子落盤，並回傳本次新標記的清單。
3. `ended_at` 保持 null（真實結束時間未知，不偽造）；`recovered` 旗標保證掃描冪等，重啟不重複回報。
4. 已保存的 segments 與 markers 經 `SessionStore` 照常載入；audio manifest 重建（掃描 audio/ 目錄補孤兒 chunk）於 M2 隨 ChunkedAudioWriter 實作。

## 八、audio/manifest.json 與 chunk 檔（M2 實作）

對應型別 `AudioManifest` 與 `AudioChunk`。欄位：`schema_version`、`sample_rate`、`channels`、`chunks[]`（每個 chunk 的 `file`、`start_seconds`、`duration_seconds`、`created_at`）。

寫入語義（`ChunkedAudioWriter`）：

1. chunk 檔名 `chunk_0001.caf` 起依序遞增，16-bit 整數 PCM CAF。
2. buffer 不跨檔切割：寫滿目標長度（預設 300 秒，`AudioDefaults.chunkDuration`）後輪替，chunk 實際長度可能略超過設定值。
3. manifest 只記錄已完成的 chunk，每次輪替即原子落盤；寫入中的 chunk 是孤兒檔。
4. 停止錄音時收尾當前 chunk 並完成索引，不做破壞性合併。

重建語義（`AudioManifestRecovery.rebuild`）：

1. 依檔名順序掃描 `chunk_*.caf`，以 `AVAudioFile` 讀出 frame 數推得長度，`start_seconds` 為前序 chunk 長度的累計。
2. 孤兒 chunk 由此補回索引；完全無法讀取的損毀 chunk 跳過，不阻斷恢復。
3. `created_at` 取檔案建立時間（整秒）。重建結果原子落盤。

App 啟動的崩潰恢復流程：`SessionLibrary.recoverCrashedSessions` 標記 metadata 後，對每個被恢復的 session 執行 manifest 重建。

匯入音檔（`AudioImporter`）走同一套格式：來源音檔解碼後轉成 canonical PCM CAF chunks 與 manifest，讀取量對齊 chunk 邊界使塊長與設定值精確一致；metadata 的 `source` 為 `imported` 且 `ended_at` 於匯入完成時落盤。

## 九、library.json（sessions 根目錄，M7／v0.2）

對應型別 `LibraryConfig`、`SessionCategory`、`MarkerType` 與 `LexiconRule`。分類定義存於程式庫層，session 只持有 `category_id` 參照。v0.2 在同檔加入自訂標記類型 `marker_types` 與名詞表 `lexicon`：

```json
{
  "schema_version": 1,
  "categories": [
    { "id": "BC59…", "name": "口試", "hidden": false, "order": 0 }
  ],
  "marker_types": [
    { "type": "decision", "label": "決議" }
  ],
  "lexicon": [
    { "from": "博特", "to": "BERT" }
  ]
}
```

讀取時依 `order` 排序；檔案不存在回傳空設定。`marker_types` 與 `lexicon` 是 v0.2 新增欄位，舊檔缺欄位時以空陣列解析、`schema_version` 不變（向下相容）。刪除分類時其下 session 的 `category_id` 改回 null；session 引用了已不存在的分類視為未分類，不會憑空消失。批次刪除 session 優先移到垃圾桶（可復原），失敗才直接移除。

`marker_types` 是模板四鍵之外的使用者自訂標記，錄音時自即時右欄「更多標記」選用。`lexicon` 是轉寫後的字面替換校正規則，套用點在 `TranscriptionCoordinator` 的 finalized 落盤前與 volatile 轉發前，只影響後續轉寫、不回頭改既有 segment；`to` 留空表示刪除該詞。

## 十、transcript_summary.json（v0.3，整份逐字稿摘要）

對應型別 `TranscriptSummary` 與文件外殼 `TranscriptSummaryDocument`，存於各 session 資料夾，原子寫入。摘要由 `TranscriptSummarizer` 以整份 finalized transcript 產生，保留所有 finalized segment ids 作來源追溯。摘要是衍生資料，不會回寫或覆蓋 `live_segments.jsonl`；右欄摘要區不顯示需複查標籤。

```json
{
  "schema_version": 1,
  "summary": {
    "schema_version": 1,
    "summary_id": "sum_0001",
    "session_id": "2026-06-15_1000_a3f2",
    "content": "本場主要討論研究方法、資料集限制與後續修改方向。",
    "key_points": ["資料集代表性需要補充", "研究方法需說明限制"],
    "action_items": ["補充資料集代表性段落"],
    "needs_review": false,
    "source_segment_ids": ["seg_0001", "seg_0002"],
    "created_at": "2026-06-15T02:00:00Z"
  }
}
```

## 十一、events.json（v0.2，結構化事件）

對應型別 `StructuredEvent` 與文件外殼 `EventsDocument`，存於各 session 資料夾，原子寫入。時間以媒體時間秒數（Double）為準，與其他檔案同軸；CSV 與 Markdown 匯出時才格式化為 HH:MM:SS。

v0.2 有三種產生與更新路徑：

1. `EventDraftBuilder` 依 marker 時間戳取前 30 後 90 秒視窗內的 finalized segments 生成草稿，填入 `source_marker_ids` 與 `source_segment_ids`。
2. `EventOrganizer.generateEvents(from:)` 在本機 Apple Foundation Models 可用時，可於沒有 markers 的 session 直接從 finalized segments 生成 events；這類 event 的 `source_marker_ids` 為空，來源 segment 由時間範圍回推。
3. `EventOrganizer.organize(_:)` 可整理既有 events 的 topic、speaker、summary、action item、priority、tags 等欄位，但必須保留原始 content、時間軸、來源 segment 與來源 marker。

所有機械或 AI 產生的草稿都必為 `needs_review: true`，可由檢視頁 Inspector 手動編輯。

```json
{
  "schema_version": 1,
  "events": [
    {
      "schema_version": 1,
      "event_id": "evt_0001",
      "session_id": "2026-06-15_1000_a3f2",
      "start_seconds": 2538.0,
      "end_seconds": 2582.0,
      "speaker": "口委A",
      "speaker_role": "committee",
      "type": "question",
      "topic": "研究方法",
      "content": "口委詢問為什麼選擇此資料集。",
      "response_summary": "學生說明資料來源限制。",
      "action_item": "補充代表性說明。",
      "priority": "high",
      "confidence": "low",
      "needs_review": true,
      "source_segment_ids": ["seg_0132", "seg_0133"],
      "source_marker_ids": ["m_0001"],
      "tags": ["資料集", "方法"],
      "created_at": "2026-06-15T02:00:00Z"
    }
  ]
}
```

編輯時 `event_id`、`session_id`、`start_seconds`、`end_seconds`、`source_segment_ids`、`source_marker_ids`、`created_at` 為來源欄位不可改；可改 `topic`、`speaker`、`speaker_role`、`content`、`response_summary`、`action_item`、`priority`、`tags` 與 `needs_review`。

## 十二、v0.2 匯出檔

匯出選項視窗（`ExportFormat`）在原有 transcript.md、markers.csv、session.json、JSONL 副本、原始 CAF 之外，新增：

- `structured_notes.md`：依模板呈現結構化事件。論文口試用「口試紀錄」版型與口試導向欄位標籤，其餘模板用通用版。
- `events.json`：結構化事件原檔。匯出時有既有 events.json 則直接輸出，否則由 markers 即時生成草稿。
- `events.csv`：事件的完整欄位，陣列欄位以分號串接，RFC 4180 跳脫。
- `<session_id>.m4a`：依 manifest 順序串接 CAF chunks 轉成單一 AAC 檔（`AudioExporter`，AVMutableComposition＋AppleM4A preset），與原始 CAF 匯出並存不取代。
