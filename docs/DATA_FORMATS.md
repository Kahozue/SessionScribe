# SessionScribe 資料格式

版本：1.0（2026-06-12，M1 產出）
對應規格：`docs/SPEC.md` 1.0 第八節
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
├── manual_markers.jsonl     append-only，每筆 append 後 fsync
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
| `privacy_mode` | String | `local_only`、`text_cloud_assist`、`audio_cloud_asr`；v0.1 僅 local_only |
| `audio_input` | String | 輸入裝置名稱 |
| `recovered` | Bool | 曾經崩潰恢復 |
| `notes` | String | 使用者備註 |
| `app_version` | String | 寫入時的 app 版本 |

寫入一律經 `Data.write(options: .atomic)`，崩潰瞬間不會留下半截 metadata。

## 四、live_segments.jsonl

對應型別 `TranscriptSegment`，一行一筆 finalized 結果。volatile 結果只存在記憶體，永不寫入本檔。欄位：`schema_version`、`segment_id`、`session_id`、`start_seconds`、`end_seconds`、`text`、`is_final`、`language`、`engine`、`model`、`confidence`（可 null）、`created_at`。

## 五、manual_markers.jsonl

對應型別 `Marker`，一行一筆。欄位：`schema_version`、`marker_id`、`session_id`、`media_seconds`、`type`、`label`、`note`、`nearest_segment_ids`、`created_at`。

`type` 是開放字串。內建四種由 `MarkerType.defaults` 提供：`question`（問題）、`required_revision`（必改）、`suggestion`（建議）、`important_answer`（重要回答）。自定義 type 自始即可寫入與讀回，v0.2 才提供管理 UI。

`nearest_segment_ids` 只是寫入當下的快照。marker 與 segment 的關聯以 `media_seconds` 為唯一真相，讀取與匯出時由時間戳動態重算。

## 六、JSONL 寫入與讀取語義

寫入（`JSONLWriter`）：

1. 開啟時定位到檔案尾端，append-only，不改寫既有內容。
2. 每筆 append 寫入單行 JSON 加換行，隨即 `synchronize()`（fsync），App 崩潰或斷電最多損失正在寫入的那一行。

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

## 八、audio/manifest.json（M2 實作）

格式預告，依規格書第八節：`schema_version`、`sample_rate`、`channels`、`chunks[]`（每個 chunk 的 `file`、`start_seconds`、`duration_seconds`、`created_at`）。M1 僅建立 `audio/` 目錄。
