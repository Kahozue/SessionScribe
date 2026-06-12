# SessionScribe 測試方法

版本：自 M2 起累積（2026-06-12 建立）
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

## 三、長時測試（現場前）

兩小時級錄音留待口試前驗證：磁碟用量約 350MB 一小時、記憶體無顯著成長、
chunk 輪替每五分鐘一次無爆音斷點。
