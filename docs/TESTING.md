# SessionScribe 測試方法

版本：自 M2 起累積（2026-06-12 建立，2026-06-13 補 M3 至 M7、v0.2 回歸與 v0.3 摘要）
對應規格：`docs/SPEC.md` 第十三節

## 一、單元測試

```bash
swift test --package-path Packages/SessionScribeKit
```

涵蓋範圍（全部離開 Xcode GUI 可執行，無需麥克風權限）：

| Suite | 對象 |
|---|---|
| Session、TranscriptSegment、Marker、AudioManifest 模型 | 規格書第八節 schema 的編解碼與範例相容性 |
| JSONLWriter、JSONLReader | append 即落盤、截斷尾行容忍、中段損毀拋錯 |
| SessionStore | 資料夾結構、metadata 原子寫入、segment 與 marker 落盤 |
| SessionStore.saveMarkers | 取消 marker 時原子重寫 manual_markers.jsonl、重開 append writer |
| SessionLibrary | 列表排序、損毀項目略過、崩潰恢復掃描冪等性 |
| MediaClock | 累計 frame 計時、pause 凍結、並行 advance 不漏計 |
| SessionController | 狀態機合法轉換、防睡眠生命週期、管線失敗時的 metadata 語義 |
| SleepInhibitor、DiskSpace | assertion 生命週期、可用空間查詢 |
| AudioLevelMeter | 靜音、滿刻度、正弦波的 rms 與 peak、分貝地板 |
| ChunkedAudioWriter | 分塊輪替、媒體時間連續性、16-bit 量化誤差、輪替即落盤 |
| AudioManifestRecovery | manifest 遺失重建、孤兒 chunk 補回、損毀 chunk 跳過 |

| MarkerSegmentAssociation、MarkerService | 時間窗關聯、依序編號、快照、即時落盤 |
| MarkdownExporter、CSVExporter、JSONExporter、ExportService | 輸出格式精確比對、RFC 4180 跳脫、子集匯出 |
| AudioExporter | CAF chunks 依 manifest 串接轉 m4a |
| MockTranscriptionEngine | 腳本驅動 finalize、漸進 volatile、錯誤注入 |
| TranscriptionCoordinator | 引擎失敗隔離（ASR 失敗錄音不中斷）、先落盤再轉發 |
| EngineSelector | 降級鏈挑選、prepare 失敗降級、全不可用回 nil |
| 實機引擎可用性 | AppleSpeechEngine 對 zh-TW 非 unsupported（spike 佐證） |
| Session source、category_id | 舊檔缺欄位相容、round-trip |
| AudioImporter | wav 轉 CAF chunks、塊長精確、失敗清除半成品、不被恢復掃描誤判 |
| OfflineTranscriber | 跨 chunk 媒體時間連續、segments 落盤 |
| AudioManifest.locate | 跨塊定位、邊界歸屬、超界 nil |
| LibraryConfig、SessionLibrary 批次 | 分類 round-trip、批次指派與刪除 |
| LibraryConfig marker types、lexicon | 舊檔相容、自訂標記與名詞表 round-trip |
| TranscriptSearchService | 跨 session 命中、marker note、大小寫、空查詢 |
| EventDraftBuilder、EventOrganizer | 依 marker 生成草稿、無 marker 時 AI 從 segments 生成 events、整理後保留來源欄位並強制 needs_review |
| TranscriptSummary、TranscriptSummarizer | transcript_summary.json、整份 finalized 逐字稿來源追溯、needs_review |
| MarkerVisualStyle、MarkerTimeline | Cmd+1 至 4 色票、模板 slot 取色、事件整理後 inline marker 保留 |

音訊測試使用合成 buffer（固定值與正弦波），不經過麥克風；寫出的 CAF 以
`AVAudioFile` 讀回驗證 frame 數與樣本值。

## 二、M2 實機驗證清單（手動）

依架構文件第七節 M2 驗證項目，於目標機器執行：

1. **首次錄音與權限**：啟動 app、新增 session、按開始。應出現麥克風授權對話框；
   拒絕後再按開始應出現引導對話框，可一鍵開啟系統設定。
2. **錄音產物**：錄 30 秒後停止。在 sidebar 右鍵「在 Finder 顯示」，確認
   `audio/` 內有 `chunk_0001.caf` 與 `manifest.json`，CAF 可在 QuickTime 播放。
3. **崩潰恢復**：錄音中以 `kill -9 <pid>` 強制終止。重啟 app，該 session 應標示
   「已恢復」，`manifest.json` 含孤兒 chunk，音訊檔可播放。
4. **pause/resume 時間軸**：錄音、暫停約一分鐘、繼續，重複數次。toolbar 時長
   在暫停期間應凍結；停止後 manifest 的總長度應等於實際收音時間（不含暫停）。
5. **防睡眠**：錄音中執行 `pmset -g assertions`，應看到
   PreventUserIdleSystemSleep 的 assertion（reason 為 SessionScribe 錄音中）；
   停止後 assertion 消失。
6. **第二個 session**：停止後再新增 session 並錄音，兩個資料夾互不干擾。
7. **輸入裝置**：接上外接麥克風，於 toolbar 選單切換後建立 session，
   metadata.json 的 `audio_input` 應記錄裝置名稱。

## 三、M3 至 M7 實機驗證清單（手動）

1. **轉寫與標記**：新場次、開始錄音、說話。逐字稿出現 volatile 淡色尾段並就地
   替換為 finalized 卡片；逐字稿區點一下取得焦點後按 Q/R/S/A 建立標記；
   游標在任何輸入框時單鍵不得觸發；Cmd+1 至 4 全域可用；快速連按不丟標記。
2. **引擎降級**：顯示選項開啟 Mock 引擎，下一場用 Mock 腳本跑完整 UI；
   關閉後新場次狀態徽章應顯示 SpeechAnalyzer。
3. **匯出**：停止後按匯出選資料夾，確認 transcript.md、markers.csv、
   session.json、兩個 jsonl 副本；逐字稿多選數段後 Inspector 匯出選取。
4. **浮動視窗**：開啟浮動逐字稿，視窗應置頂、可調大小，字級按鈕與主視窗同步。
5. **外觀**：深淺色切換下檢查逐字稿、標記、徽章可讀性。
6. **匯入與檢視**：匯入一個 m4a，選立即轉寫；完成後檢視頁播放，
   當前段落應放大置中（歌詞效果），點任一段跳轉播放位置，時間一致。
7. **搜尋**：側欄搜尋逐字稿字詞，點結果應跳到該 session 檢視頁並定位該段。
8. **分類與批次**：建立分類、把數個 session 多選移入、隱藏分類後側欄消失、
   批次刪除有確認且可從垃圾桶復原。

## 四、v0.2 實機驗證清單（手動，已通過）

1. **模板選擇**：工具列錄音選項選「會議」模板後錄音，右欄四鍵應顯示決議／待辦／重要／問題，Cmd+1 至 4 建立對應 type 的 marker；停止後在 Finder 開 metadata.json 確認 `template_id` 為 `meeting`。切回論文口試應恢復 Q/R/S/A 字母提示。
2. **名詞表校正**：設定頁「轉寫」加規則（例：博特→BERT），下一場（或重新轉寫）含該詞的句子落盤後應已校正；開 live_segments.jsonl 確認。空規則表行為與先前一致。
3. **自訂標記**：設定頁「標記」新增一個自訂類型，錄音時右欄「更多標記」可選用並建立 marker；重啟 app 後該類型仍在。
4. **結構化事件草稿**：對有標記的 session 在檢視頁右欄按「產生草稿」，事件卡顯示需複查徽章、點時間跳轉、點卡開編輯表單；改一個欄位儲存後重開頁面應保留，且來源段落／標記欄位不可改。
5. **新匯出格式**：匯出時勾選結構化筆記、events.json、events.csv 與 m4a，確認四檔產出；events.json 與檢視頁編輯結果一致，m4a 在 QuickTime 可播且長度與原錄音相符。
6. **本機 AI 整理事件**：檢視頁右欄有「依標記彙整」與「AI 產生草稿／AI 整理」兩顆按鈕。沒有標記、只有逐字稿時，AI 鈕仍可直接從逐字稿生成草稿（與標記解耦）；已有草稿時 AI 鈕改為補齊欄位。若本機 Apple Intelligence 未開或不支援該語言，AI 鈕停用並顯示原因（機械路徑仍可用）。AI 產物：型別／主題／摘要／待辦被填上、強制 needs_review，content 取原始逐字稿、來源段落以時間回推不杜撰。事件區塊標題可點 chevron 摺疊。
7. **標記色票與取消回歸**：Cmd+1 至 4 建立的標記在中欄 inline marker、右欄事件列表、結構化事件來源標記中維持藍／紅／綠／紫色票。按「依標記彙整」或「AI 產生草稿／AI 整理」後，中欄原本標記過的位置仍顯示 inline marker。右欄事件列表點書籤圖示可取消該 marker，取消後中欄與右欄同步移除，重開 session 後仍不再出現。

## 五、v0.3 實機驗證清單（手動）

1. **整份逐字稿摘要**：有 finalized 逐字稿的 session 進入檢視頁，右欄最上方顯示「逐字稿摘要」，下方依序是「結構化事件」與「事件標記」。按「AI 產生摘要」後產生摘要、重點、待辦與需複查標記；重開 session 後摘要仍在。摘要區 chevron 可折疊且不影響事件與標記區。
2. **摘要可用性**：沒有逐字稿時摘要按鈕停用；本機 Apple Intelligence 未開或模型未就緒時，按鈕停用並顯示原因。
3. **兩小時級長錄**：磁碟用量約 350MB 一小時、記憶體無顯著成長、chunk 輪替每五分鐘一次無爆音斷點。
