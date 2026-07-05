# SessionScribe 測試方法

版本：自 M2 起累積（2026-06-12 建立，2026-06-13 補 M3 至 M7、v0.2 回歸與 v0.3 摘要，2026-07-05 補規格 1.4 單元測試與實機清單）
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
| TranscriptSummary、TranscriptSummarizer | transcript_summary.json、整份 finalized 逐字稿來源追溯、摘要區無需複查標籤 |
| MarkerVisualStyle、MarkerTimeline | Cmd+1 至 4 色票、模板 slot 取色、事件整理後 inline marker 保留 |
| JSONExtraction | 容錯抽出第一個 JSON 物件/陣列：剝 ```json 圍欄、前後雜訊、忽略字串內括號、陣列、無 JSON 拋錯 |
| OpenAICompatibleClient、AnthropicClient、GeminiClient | request 組裝（端點、headers、body JSON 形狀）與 response 解析，以注入 transport stub 不打真網路；HTTP 錯誤狀態轉錯 |
| CloudEventOrganizer、CloudTranscriptSummarizer | 以 MockCloudLLMClient 驗：補語意欄位不覆蓋 raw、來源保留、needs_review 強制 true、空逐字稿回空摘要 |
| AssistResolver | 引擎路由：雲端+key 齊回雲端；總開關關／引擎本機／缺 key 一律退回本機（Local Only 程式層強制）；sttClient 額外要求供應商 supportsSTT |
| CloudLLMSettings、KeychainStore | 設定 round-trip 與預設、供應商樣板齊四家、舊格式（單一 engine/activeProviderID）自動遷移；InMemoryKeychainStore 存取／覆寫／刪除語義 |
| CloudSTTClient（OpenAISTTClient、GeminiSTTClient） | request 組裝（multipart、長逾時、依 model 選 json/verbose_json/diarized_json）；回應解析：verbose_json 分段、diarized_json 保留 speaker、無 segments 整段一句、Gemini 取 text 為單段；非 2xx 拋含供應商原因的 HTTP 錯誤 |
| CloudTranscriber | STT 段落對應為 TranscriptSegment、空輸入回空陣列、無時間戳時以音訊總長補結束時間 |
| CloudTranslator | 翻譯回傳純文字與 JSON 物件皆可解析、去除前後空白與中西式包覆引號 |
| TranslationCoordinator | prepare 成功後逐段翻譯且 segmentID 對應依序轉發；prepare 失敗全短路；單段失敗不阻斷後續；空白不翻 |
| CloudLLMError | 網路、401、429、逾時、解析失敗轉成使用者可讀中文訊息 |
| CloudTranscriptionPresentation | 轉寫按鈕文案依實際雲端 STT 可用性切換；雲端錯誤顯示使用者訊息而非 Swift 錯誤代碼 |
| Waveform、WaveformExtractor | bin 數規則、waveform.json round-trip；正弦波 rms/peak 數值、跨 chunk 連續、損毀 chunk 跳過為零值 |

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
4. **浮動視窗**：開啟浮動逐字稿，視窗應置頂、可調大小，字級按鈕與主視窗同步，標題列與逐字稿內文都會跟著調整。
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

1. **整份逐字稿摘要**：有 finalized 逐字稿的 session 進入檢視頁，右欄最上方顯示「逐字稿摘要」，下方依序是「結構化事件」與「事件標記」。按「AI 產生摘要」後產生摘要、重點與待辦；摘要區不顯示需複查標籤，重開 session 後摘要仍在。摘要區 chevron 可折疊且不影響事件與標記區。
2. **全畫面字級**：設定頁「介面字級」滑桿調整後，側欄、工具列、右欄摘要／事件／標記、設定頁、浮動視窗與逐字稿內文都同步變大或變小，不只中欄逐字稿正文。
3. **摘要可用性**：沒有逐字稿時摘要按鈕停用；本機 Apple Intelligence 未開或模型未就緒時，按鈕停用並顯示原因。
4. **兩小時級長錄**：磁碟用量約 350MB 一小時、記憶體無顯著成長、chunk 輪替每五分鐘一次無爆音斷點。

## 六、雲端整理實機驗收清單（手動，v0.3 Text Cloud Assist，已通過）

需各家有效 API key。三家分別填 key 後逐項驗（2026-06-14 實機驗收通過）：

1. **三家測試連線**：設定頁「雲端」分頁，分別以 OpenAI 相容、Anthropic、Gemini 樣板新增供應商、填 key、按「測試連線」，各看到「連線成功」。錯 key 應顯示「API key 無效或未授權（401）」之類清楚訊息。
2. **雲端事件整理與摘要**：開總開關、引擎設雲端、選定供應商。對有逐字稿的 session 在檢視頁按「AI 整理／AI 產生草稿」與「AI 產生摘要」，雲端回填語意欄位與摘要，事件標 needs_review，本機逐字稿不被覆蓋。切引擎回本機後行為回到本機 FoundationModels。
3. **Local Only 強制（零外連）**：引擎設本機（或總開關關），以 Little Snitch／Charles 觀察，跑整理與摘要時應有零外連；切雲端後才出現對應供應商端點的連線。
4. **金鑰持久化**：填 key、關閉 app 重開，供應商設定與選用狀態保留，key 從 Keychain 讀回（設定頁 SecureField 重新顯示已存的 key）；刪除供應商後對應 Keychain 項目一併清除。
5. **錯誤情境本機資料不損**：故意填錯 key（401）、拔網路（連線失敗）、逾時，皆顯示清楚中文錯誤訊息，且錄音與逐字稿仍保存，可重試或改用本機。
6. **狀態標與隱私旗標**：雲端引擎生效時主錄音畫面標頭出現「雲端整理」標；跑過雲端整理的 session 檢視頁標頭顯示同一標，且 metadata.json 的 `privacy_mode` 已記為 `text_cloud_assist`。首次開總開關跳啟用前警告。

## 七、規格 1.4 實機驗證清單（手動，待執行）

各功能引擎個別選擇、雲端離線轉錄稿、雲端字幕翻譯與重新轉錄。需 OpenAI 與 Gemini 有效 API key：

1. **五功能引擎面板**：設定頁「雲端」分頁「每項功能引擎」有五列本地/雲端切換；總開關關時全部停用；即時 ASR 的雲端段標「雲端（開發中）」且點選不生效（維持本地）。
2. **兩槽供應商**：文字類與語音類各自可選 active 供應商；語音槽選單只出現 OpenAI 相容與 Gemini（無 Anthropic）；語音槽以 OpenAI 樣板新增供應商時預設 model 為 `gpt-4o-mini-transcribe`。
3. **雲端離線轉錄稿（OpenAI）**：轉錄稿設雲端、語音槽選 OpenAI、key 齊備，對匯入或純錄音 session 執行轉寫，按鈕文案顯示雲端字樣；完成後 live_segments.jsonl 的 `engine` 為 `cloud`，metadata 的 `privacy_mode` 為 `audio_cloud_asr`；改用 `gpt-4o-transcribe-diarize` 時 `speaker` 欄有值。
4. **雲端離線轉錄稿（Gemini）**：同上改 Gemini，整段一句、結束時間等於音訊總長。
5. **路由退回本地**：總開關關、或轉錄稿設本地、或語音槽未選供應商、或 key 缺，任一情況執行轉寫都走本機引擎（可用 Little Snitch 驗證零外連），不報錯。
6. **雲端字幕翻譯**：字幕翻譯設雲端、文字槽齊備，開啟即時翻譯錄一段，每句定稿後譯文疊在原文下；只送文字（以 Charles 檢查 payload 無音訊）；session 的 `privacy_mode` 記 `text_cloud_assist`。
7. **重新轉錄**：已轉錄且有音訊的 session 檢視頁資訊列有「重新轉錄」；點擊出現二次確認並說明覆蓋範圍；確認後逐字稿被新結果覆蓋，既有摘要、events、譯文不變；轉寫中途失敗（拔網路）時既有逐字稿完好無損。
8. **文字加音訊混合旗標**：同一 session 先跑雲端摘要再跑雲端重新轉錄，`privacy_mode` 應為 `text_and_audio_cloud`。
9. **Keychain 延遲讀取**：啟動 app 與純瀏覽設定頁其他分頁時不觸發 Keychain 授權提示；只有執行雲端動作或在雲端分頁按「從系統匯入」才讀取金鑰。

## 八、波形圖實機驗證（手動）

1. 開啟一個已停止且有音訊的 session，首次進檢視頁顯示 Slider 與生成進度，完成後切換為波形；重開頁面直接顯示波形（讀快取）。
2. 點擊與拖曳波形跳轉播放位置，時間與歌詞模式定位一致；左右方向鍵微調 5 秒。
3. 有標記的 session 波形上出現對應色票短線，位置與標記時間一致。
4. 深淺色下波形已播放與未播放區段對比清楚。
5. 刪除該 session 的 waveform.json 後重開頁面會重新生成。

## 九、Menu bar 錄音控制實機驗證（手動）

1. 選單列圖示隨狀態切換：閒置為 waveform、錄音中為紅色錄音符號、暫停為暫停符號，停止後回閒置。
2. 沒有進行中 session 時，從 menu bar 按「開始錄音」自動建新錄音並開始；主視窗側欄同步出現新 session。
3. 暫停、繼續、停止與主視窗工具列狀態雙向同步（主視窗操作後 menu bar 面板即時反映，反之亦然）。
4. 錄音中面板出現依當前模板的四個快速標記鍵；點擊後主視窗即時右欄同步出現標記，media 時間與主視窗觸發一致。
5. 「開啟主視窗」：主視窗關閉時能重開，已開時帶到前景聚焦。
6. 設定頁顯示分頁關閉「在選單列顯示錄音控制」，選單列圖示即消失；重開即回。設定跨重啟記憶。

## 十、無障礙與鍵盤體驗實機驗證（手動）

1. VoiceOver 全流程：錄音、標記、停止、檢視、匯出可獨立完成；圖示型按鈕（字幕浮層三鈕、播放鍵）讀出正確中文標籤。
2. level meter 與波形圖以 VoiceOver 讀出文字化數值；波形可用 VoiceOver 調整（上下滑動改播放位置）。
3. 焦點順序：主視窗三欄、設定頁、sheet 的 Tab 順序合理，無死路。
4. 系統「減少動態效果」開啟後：歌詞模式切換、右欄折疊、狀態列進出場、紅點呼吸、標記 flash、onboarding 步進全部變為直接切換。
5. 說明選單有「鍵盤快捷鍵」，開啟的總覽視窗列出全部快捷鍵與單鍵焦點規則。
6. Accessibility Inspector audit 主畫面、檢視頁、設定頁無 critical 項。
