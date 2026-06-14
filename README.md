# SessionScribe

macOS 原生的錄音、即時轉寫與事件標記工具。為現場記錄場景設計（論文口試、會議、訪談、講座），核心原則是現場可靠性：原始錄音永遠是最高優先級，ASR 或任何後續處理失敗都不影響錄音與已保存的資料。

目前狀態：v0.2 驗收通過。v0.3 進行中：右欄整份逐字稿摘要與雲端整理（Text Cloud Assist）已實作並通過實機驗收；右欄摘要、結構化事件、事件標記三區皆可分別折疊；五項功能（離線轉錄稿、即時 ASR、摘要、結構化事件、字幕翻譯）可各自選本地或雲端，已轉錄 session 提供重新轉錄入口；兩小時級長錄測試仍列 v0.3 驗收項目。

## 功能

- 完整錄音：PCM CAF 分塊增量保存加 manifest 索引，崩潰最多損失當前緩衝；啟動時自動恢復崩潰殘留 session
- 本機即時轉寫：macOS 26 SpeechAnalyzer / SpeechTranscriber 為主引擎（zh-TW 已驗證），SFSpeechRecognizer 備援，全部不可用時自動退為純錄音；Mock 引擎供無語音環境開發測試
- volatile 與 finalized 轉寫結果在 UI 上明確區分；浮動置頂的即時逐字稿視窗
- 單鍵事件標記：Q/R/S/A 與 Cmd+1 至 4，依目前模板對應四個主要標記；Cmd+1 至 4 具固定色票，右欄書籤圖示可取消既有標記
- 內建場景模板：論文口試、會議、訪談、講座；錄音時四鍵文案與 type 依模板切換
- 自訂標記與專有名詞表：設定頁可新增自訂 marker type，lexicon 規則會套用於後續 finalized 與 volatile 轉寫文字
- 整份逐字稿摘要：檢視頁右欄最上方可用本機 AI 產生摘要、重點與待辦，摘要區可折疊，不顯示需複查標籤
- 結構化事件：檢視頁右欄可依標記彙整 events，也可在本機 Apple Foundation Models 可用時用 AI 從逐字稿生成草稿或補齊欄位；AI 產物一律標為需複查
- 匯出：transcript.md、markers.csv、session.json、jsonl 原檔副本、structured_notes.md、events.json、events.csv、m4a；逐字稿可多選後匯出選取段落
- 匯入音檔（caf、wav、m4a、mp3、aiff）轉為標準 session，可選離線轉寫
- 錄音檢視頁：chunk 串接播放、歌詞式定位（當前段放大置中、點擊跳轉播放）
- 跨逐字稿搜尋（segments 與標記備註），結果一鍵跳轉定位
- session 分類（自訂、隱藏）、多選批次移動與刪除
- 全畫面字級調整與深淺色外觀
- 各功能引擎個別選擇：離線轉錄稿、即時 ASR、摘要、結構化事件、字幕翻譯五項功能各自選本地或雲端；本次實作離線轉錄稿、摘要、結構化事件、字幕翻譯四項雲端，支援 OpenAI 相容／Anthropic／Gemini；本機與雲端並存、由使用者選用，預設關閉、API key 存 Keychain。即時 ASR 雲端串流尚未實作（設定面板標「開發中」，實際走本地）
- 雲端離線轉錄稿（Audio Cloud ASR）：選雲端時把整段 session 音訊匯出為單一 m4a 上傳雲端 STT（OpenAI 相容或 Gemini，Anthropic 不支援 STT），結果落盤為一般逐字稿並標記該 session 為雲端音訊模式
- 雲端字幕翻譯：即時翻譯選雲端時，只送每句定稿文字給雲端 LLM 翻譯，不涉音訊
- 重新轉錄：已轉錄且有音訊的 session 在檢視頁資訊列提供「重新轉錄」按鈕，二次確認後以目前辨識語言與名詞表覆蓋既有逐字稿；既有摘要、結構化事件、譯文不自動更新，需自行重新產生
- 預設 Local Only：未選雲端的功能一律不建立連線。v0.3 起為帶雲端功能而加入 network client entitlement，Local Only 改由程式層堅守（唯一的網路層只在「總開關開且該功能選雲端」時建構），輔以持續 UI 狀態標、啟用前警告與下方可驗證性說明

## 環境需求

- macOS 26 Tahoe 以上
- Xcode 26 以上
- 重新生成 Xcode 專案才需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`），直接建置不需要

## 建置與執行

```bash
git clone https://github.com/Kahozue/SessionScribe.git
cd SessionScribe
open SessionScribe.xcodeproj
```

在 Xcode 中選擇 SessionScribe scheme，Cmd+R 執行。

修改過 `project.yml` 後重新生成專案：

```bash
xcodegen generate
```

## 基本使用

1. 工具列「新增 Session」（可先選輸入裝置與模板），按「開始」錄音。
2. 逐字稿區聚焦時按 Q/R/S/A 建立標記，或用 Inspector 的大按鈕、Cmd+1 至 4。右欄事件列表中的書籤圖示可取消標記。
3. 側欄點選舊 session 進入檢視頁播放；右欄由上到下是逐字稿摘要、結構化事件、事件標記，可分別折疊。摘要可按「AI 產生摘要」，事件可按「依標記彙整」或「AI 產生草稿／AI 整理」。已有逐字稿的 session 可在資訊列按「重新轉錄」，二次確認後覆蓋逐字稿（既有摘要、結構化事件、譯文不會自動更新）。
4. 「停止」保存後按「匯出」選資料夾，可輸出逐字稿、標記、結構化事件與 m4a。側欄右鍵任何 session 也可匯出或在 Finder 顯示。
5. 「匯入音檔」可把既有錄音轉成 session，匯入後可選擇立即離線轉寫。
6. 搜尋列可跨所有逐字稿找文字；右鍵多選可批次移分類或刪除。設定頁可管理分類、自訂標記與專有名詞表。

Session 資料存於 app container 內 `~/Library/Containers/io.github.kahozue.SessionScribe/Data/Library/Application Support/SessionScribe/Sessions/`，每場一個資料夾，格式見 `docs/DATA_FORMATS.md`。

## 權限

- 麥克風：第一次開始錄音時系統會詢問。若先前拒絕過，到「系統設定 > 隱私權與安全性 > 麥克風」開啟 SessionScribe，app 也會提供引導。
- 語音辨識：只有降級到備援引擎 SFSpeechRecognizer 時需要；主引擎 SpeechAnalyzer 為純本機處理。

## 測試

```bash
swift test --package-path Packages/SessionScribeKit
```

單元測試不需要麥克風與語音模型。實機驗證清單見 `docs/TESTING.md`。

## 隱私

- 預設 Local Only：所有五項功能（離線轉錄稿、即時 ASR、摘要、結構化事件、字幕翻譯）皆設為本地，音訊與逐字稿只存本機，使用 Apple 本機語音模型；本機 AI 摘要與整理用 Apple Foundation Models，不碰網路
- 依各功能設定運作：選為雲端的文字功能（摘要／結構化事件／字幕翻譯）只把選定的逐字稿或事件文字送往所選供應商，不涉音訊；選為雲端的「離線轉錄稿」會把該 session 的整段音訊匯出為單一 m4a 上傳雲端 STT。未選雲端的功能一律不外送，預設全部本地
- Local Only 可驗證性：唯一的 `URLSession` 只在 `Packages/SessionScribeKit/Sources/SSCore/Cloud/` 一處，且只在「總開關開 AND 該功能 engine=雲端 AND 對應供應商與 key 齊備」時才會被 `AssistResolver` 建構與呼叫；某功能未選雲端或總開關關時不建構該功能的 client（有單元測試 `AssistResolverTests`／`CloudLLMSettingsTests` 佐證）。可用 Little Snitch／Charles 觀察本機模式下零外連
- API key 存系統 Keychain（service `com.sessionscribe.cloud-llm`），不寫入 UserDefaults、不寫入任何檔案、不支援環境變數讀取
- 自 v0.3 起 `SessionScribe/SessionScribe.entitlements` 含 `com.apple.security.network.client`（為雲端功能而加），其餘 Local Only 保證改由上述程式層堅守
- 專案不含 API key 與個人資料

## 各功能引擎選擇與限制

設定頁「雲端」分頁可為五項功能各自選本地或雲端：離線轉錄稿、即時 ASR、摘要、結構化事件、字幕翻譯。供應商分文字類（摘要／結構化事件／字幕翻譯共用一個 active 供應商）與語音類（離線轉錄稿／即時 ASR 共用一個 active 供應商）兩槽。

已知限制：

- **即時 ASR 雲端串流尚未實作**：設定面板會顯示即時 ASR 的雲端選項，但標示「開發中」且選了會被拉回本地；實際錄音時仍走本機 `EngineSelector` 降級鏈。
- **語音類供應商選單只列支援 STT 者**：只有 OpenAI 相容與 Gemini 格式提供語音轉文字端點，Anthropic 不支援 STT，不會出現在語音類供應商選單中。
- **語音槽新增供應商使用 STT 預設值**：OpenAI 語音樣板預設 model 為 `gpt-4o-mini-transcribe`，文字類 OpenAI 樣板仍使用 chat model。若需要 speaker label，可手動改用 `gpt-4o-transcribe-diarize`。
- **OpenAI 相容端點需自行確認支援 `/audio/transcriptions`**：部分 OpenAI 相容端點（例如 DeepSeek）並無語音轉文字 API。選為語音類供應商後，執行離線轉錄稿時若該端點無此路徑會在執行時回連線錯誤，UI 不會預先擋下。
- **雲端離線轉錄為單檔上傳**：選雲端時會把整段 session 音訊匯出為單一 `.m4a` 後上傳，受所選供應商的檔案大小與時長上限約束；超出限制時上傳會失敗並顯示錯誤訊息，不會自動切分重試。

## 文件

- [規格書](docs/SPEC.md)（1.4，對齊各功能引擎個別選擇、雲端離線轉錄稿與重新轉錄）
- [架構文件](docs/ARCHITECTURE.md)
- [資料格式](docs/DATA_FORMATS.md)
- [測試方法](docs/TESTING.md)
- [Spike：zh-TW 語音支援驗證](docs/spikes/2026-06-12-speech-zh-tw.md)

## 里程碑

| 里程碑 | 內容 | 狀態 |
|---|---|---|
| M0 | 專案骨架、entitlements、UI 殼層、zh-TW spike | 完成 |
| M1 | 資料模型、儲存層、MediaClock | 完成 |
| M2 | 錄音管線、分塊保存、pause/resume、崩潰恢復 | 完成 |
| M3 | 事件標記、匯出 | 完成 |
| M4 | Mock 引擎、即時逐字稿 UI、浮動視窗、外觀設定 | 完成 |
| M5 | Apple Speech 引擎整合與降級鏈 | 完成 |
| M6 | 匯入音檔、錄音檢視頁、歌詞式定位 | 完成 |
| M7 | 分類、批次管理、跨逐字稿搜尋 | 完成 |
| M8 | App icon、README、文件收尾 | 完成 |
| v0.2 | 內建模板、自訂標記、專有名詞表、結構化事件草稿與編輯、本機 AI 整理、structured_notes/events/m4a 匯出、標記色票與取消 | 驗收通過 |
| v0.3 | 整份逐字稿摘要、兩小時級長錄測試、雲端文字整理、各功能引擎個別選擇、雲端離線轉錄稿（Audio Cloud ASR）、雲端字幕翻譯、重新轉錄入口、API key 安全輸入、自訂 AI prompt、network entitlement | 進行中 |

v0.1 與 v0.2 驗收清單見 `docs/TESTING.md`；兩小時級長錄改列 v0.3 驗收項目。

## License

待定。
