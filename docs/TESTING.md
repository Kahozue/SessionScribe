# SessionScribe 測試方法

版本：自 M2 起累積（2026-06-12 建立，2026-06-13 補 M3 至 M7）
對應規格：`docs/SPEC.md` 第十三節

## 一、單元測試

```bash
cd Packages/SessionScribeKit
swift test
```

涵蓋範圍（全部離開 Xcode GUI 可執行，無需麥克風權限）：

| Suite | 對象 |
|---|---|
| Session、TranscriptSegment、Marker、AudioManifest 模型 | 規格書第八節 schema 的編解碼與範例相容性 |
| JSONLWriter、JSONLReader | append 即落盤、截斷尾行容忍、中段損毀拋錯 |
| SessionStore | 資料夾結構、metadata 原子寫入、segment 與 marker 落盤 |
| SessionLibrary | 列表排序、損毀項目略過、崩潰恢復掃描冪等性 |
| MediaClock | 累計 frame 計時、pause 凍結、並行 advance 不漏計 |
| SessionController | 狀態機合法轉換、防睡眠生命週期、管線失敗時的 metadata 語義 |
| SleepInhibitor、DiskSpace | assertion 生命週期、可用空間查詢 |
| AudioLevelMeter | 靜音、滿刻度、正弦波的 rms 與 peak、分貝地板 |
| ChunkedAudioWriter | 分塊輪替、媒體時間連續性、16-bit 量化誤差、輪替即落盤 |
| AudioManifestRecovery | manifest 遺失重建、孤兒 chunk 補回、損毀 chunk 跳過 |

| MarkerSegmentAssociation、MarkerService | 時間窗關聯、依序編號、快照、即時落盤 |
| MarkdownExporter、CSVExporter、JSONExporter、ExportService | 輸出格式精確比對、RFC 4180 跳脫、子集匯出 |
| MockTranscriptionEngine | 腳本驅動 finalize、漸進 volatile、錯誤注入 |
| TranscriptionCoordinator | 引擎失敗隔離（ASR 失敗錄音不中斷）、先落盤再轉發 |
| EngineSelector | 降級鏈挑選、prepare 失敗降級、全不可用回 nil |
| 實機引擎可用性 | AppleSpeechEngine 對 zh-TW 非 unsupported（spike 佐證） |
| Session source、category_id | 舊檔缺欄位相容、round-trip |
| AudioImporter | wav 轉 CAF chunks、塊長精確、失敗清除半成品、不被恢復掃描誤判 |
| OfflineTranscriber | 跨 chunk 媒體時間連續、segments 落盤 |
| AudioManifest.locate | 跨塊定位、邊界歸屬、超界 nil |
| LibraryConfig、SessionLibrary 批次 | 分類 round-trip、批次指派與刪除 |
| TranscriptSearchService | 跨 session 命中、marker note、大小寫、空查詢 |

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

## 四、v0.2 實機驗證清單（手動）

1. **模板選擇**：工具列錄音選項選「會議」模板後錄音，右欄四鍵應顯示決議／待辦／重要／問題，Cmd+1 至 4 建立對應 type 的 marker；停止後在 Finder 開 metadata.json 確認 `template_id` 為 `meeting`。切回論文口試應恢復 Q/R/S/A 字母提示。
2. **名詞表校正**：設定頁「轉寫」加規則（例：博特→BERT），下一場（或重新轉寫）含該詞的句子落盤後應已校正；開 live_segments.jsonl 確認。空規則表行為與先前一致。
3. **自訂標記**：設定頁「標記」新增一個自訂類型，錄音時右欄「更多標記」可選用並建立 marker；重啟 app 後該類型仍在。
4. **結構化事件草稿**：對有標記的 session 在檢視頁右欄按「產生草稿」，事件卡顯示需複查徽章、點時間跳轉、點卡開編輯表單；改一個欄位儲存後重開頁面應保留，且來源段落／標記欄位不可改。
5. **新匯出格式**：匯出時勾選結構化筆記、events.json、events.csv 與 m4a，確認四檔產出；events.json 與檢視頁編輯結果一致，m4a 在 QuickTime 可播且長度與原錄音相符。

## 五、長時測試（現場前）

兩小時級錄音留待口試前驗證：磁碟用量約 350MB 一小時、記憶體無顯著成長、
chunk 輪替每五分鐘一次無爆音斷點。
