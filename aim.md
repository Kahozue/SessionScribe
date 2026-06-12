一、產品定位

我要做的是一個 macOS 原生 App，核心功能是：

1. 建立一個錄音 / 轉寫 session。
2. 錄下完整音訊。
3. 使用 macOS 26 Tahoe 的 Speech framework：SpeechAnalyzer / SpeechTranscriber 作為主要本機 ASR 引擎。
4. 顯示即時轉寫內容。
5. 支援 volatile results 與 finalized results 的 UI 呈現邏輯。
6. 讓使用者用極少量操作標記事件，例如問題、必改、建議、重要回答。
7. 依照不同場景模板，將逐字稿與標記整理成結構化筆記。
8. 支援 Markdown、JSON、CSV 匯出。
9. 支援自定義場景、標記類型、輸出欄位、整理模板、關鍵詞表與專有名詞表。
10. 以本機處理與資料不外流作為預設原則。
11. 可選擇雲端整理或雲端 ASR，但必須由使用者明確啟用然後有api供應商和key的安全輸入。

這個工具短期使用場景是「碩士論文口試」：我需要協助記錄口試委員詢問的問題、要求修改的事項、建議事項與學生回答重點。
長期使用場景包括：

* 論文口試
* 課堂講座
* 會議記錄
* 訪談
* 研究討論
* 讀書會
* 專案會議
* 客戶訪談
* 研討會
* 個人語音筆記

因此請不要把資料模型、UI 文案與功能設計硬綁死在「論文口試」。論文口試只能是其中一個預設模板。

二、目標平台與硬體環境

主要開發與執行環境：

* macOS 26 Tahoe
* MacBook Air M3
* 24GB RAM
* Xcode 最新版
* Swift / SwiftUI
* AVFoundation
* Speech framework
* Apple SpeechAnalyzer / SpeechTranscriber
* 本機 Apple ASR 優先

備援裝置：

* iPhone 會獨立錄音作為備援，不需要第一版 App 支援 iPhone。
* iPad Pro 2024 希望能查看或同步顯示操控狀態可作為查看或手寫輔助。（但若問題多我同意這部分我自己螢幕mirror處理）

三、技術路線

請優先採用 macOS 原生技術，不要使用 Electron 或 Tauri 作為第一版主架構。

建議技術棧：

* SwiftUI：主要 UI
* AppKit interop：必要時處理 macOS 視窗、快捷鍵、menu bar、檔案操作
* AVFoundation：錄音、音訊 session、音訊檔案寫入、播放
* Speech framework：SpeechAnalyzer / SpeechTranscriber
* AssetInventory：確認語音模型是否支援、是否已下載、必要時引導下載
* Foundation：檔案系統、JSON、CSV、時間格式
* Swift Concurrency：async / await、AsyncSequence、Task 管理
* SwiftData 或 SQLite：後續可用於 session 索引；MVP 可先使用檔案式儲存
* Markdown / JSON / CSV 匯出：先自己產生即可

若某個 API 在目前 Xcode / macOS SDK 中不可用，請清楚標示，並提供 fallback：

1. 優先：SpeechAnalyzer / SpeechTranscriber。
2. 備援：DictationTranscriber。
3. 再備援：SFSpeechRecognizer。
4. 最後備援：保留完整錄音，允許口試後離線處理。

請不要讓 ASR API 的不可用導致錄音功能失效。

四、核心可靠性原則

這個產品最重要的是現場可靠性，請嚴格遵守以下原則：

1. 原始錄音是最高優先級。
2. 即使 ASR 失敗，錄音仍要繼續。
3. 即使摘要或結構化整理失敗，錄音與逐字稿仍要保存。
4. 原始逐字稿不得被摘要覆蓋。
5. volatile transcript 不得直接覆蓋 finalized transcript。
6. 所有 finalized segment 必須增量寫入磁碟。
7. 所有 manual marker 必須增量寫入磁碟。
8. 所有 AI 產生的結構化結果必須標記為 needs_review。
9. 結構化結果必須能追溯到原始 transcript segment。
10. 雲端功能預設關閉。
11. API key 不得寫入程式碼。
12. 使用者未明確啟用雲端模式時，不得發出任何網路請求。
13. App 崩潰後，至少要保留已錄音 chunk、已完成轉寫 segment、已建立 marker。
14. UI 必須讓使用者清楚知道目前狀態：未錄音、錄音中、暫停、轉寫中、ASR 錯誤、儲存中、匯出完成。

五、產品名稱暫定

專案名：SessionScribe


六、資訊架構與主要畫面

請設計一個符合 macOS 26 Tahoe / Liquid Glass / Apple HIG 方向的原生介面。視覺設計要重視層次、可讀性、低干擾、長時間觀看舒適度、錄音狀態辨識。

主要畫面結構

建議採用三欄式或兩欄式 macOS app 佈局：

1. Sidebar：Session 列表、模板、設定入口。
2. Main content：目前 session 的即時逐字稿。
3. Inspector / Right panel：事件標記、結構化筆記、匯出、狀態。


頂部控制列

必須有：

* New Session
* Start
* Pause
* Resume
* Stop
* Save
* Export
* Privacy Mode
* ASR Engine Status
* Recording Duration
* Audio Level Indicator

即時轉寫區

需要同時處理兩種文字狀態：

* volatile transcript：即時猜測，視覺上要較淡、可被替換。
* finalized transcript：最終段落，視覺上要穩定、清楚、可被引用。

請在 UI 上避免讓使用者誤以為 volatile 內容已定稿。
例如：

* finalized：正常文字。
* volatile：較淡、斜體或半透明。
* segment hover：顯示時間範圍。
* 點擊 segment：後續可播放對應音訊。

事件標記區
至少需要四個大按鈕與快捷鍵：

* Q：問題
* R：必改
* S：建議
* A：重要回答

按下後立即建立 marker，並對齊最近的 transcript segment 與當前錄音時間。

請支援極少量操作，不要要求使用者頻繁輸入文字。
可以提供可選 note 欄位，但不能阻塞錄音與標記流程。

七、HCI 與視覺設計要求

介面體驗非常重要，請不要只做工程 demo。

設計原則

1. 低認知負荷：現場使用者正在旁聽與手寫，不應被介面干擾。
2. 高狀態可見性：錄音中、暫停、錯誤、匯出完成必須一眼可辨識。
3. 快速可逆操作：標記錯了可以事後改，不要要求當下精準。
4. 漸進揭露：MVP 的主畫面簡潔，進階設定放在設定頁。
5. 資料安全感：清楚顯示「本機模式」或「雲端模式」。
6. 長時間閱讀舒適：逐字稿行距、字重、對比度要適合 1–3 小時使用。
7. 尊重 macOS 原生行為：支援 Command 快捷鍵、系統字體、深色模式、視窗 resize、sidebar、toolbar。

色彩系統

請使用正式、冷靜、學術感、專業工具感的色彩。

請支援系統深色模式，且不得只用顏色傳達狀態；需搭配文字、圖示或形狀。

錄音狀態顏色

字體與排版

* 使用 macOS 系統字體。
* 行距要適合長時間閱讀。
* 事件卡片要有明確時間戳。
* 不要使用過度花俏動畫。
* 動畫只能用於狀態轉換與回饋，不得干擾記錄。

八、資料模型

請設計清楚的資料模型

Session Metadata

每個 session 都要有 metadata.json：

{
“session_id”: “2026-06-15_1000_session”,
“title”: “碩士論文口試 - 第一場”,
“template_id”: “thesis_defense”,
“created_at”: “ISO-8601 timestamp”,
“started_at”: “ISO-8601 timestamp”,
“ended_at”: null,
“locale”: “zh-TW”,
“asr_engine”: “SpeechAnalyzer”,
“privacy_mode”: “local_only”,
“audio_input”: “MacBook Air Microphone”,
“notes”: “”,
“app_version”: “0.1.0”
}

Transcript Segment

逐字稿 segment 必須增量寫入 live_segments.jsonl：

{
“segment_id”: “seg_0001”,
“session_id”: “2026-06-15_1000_session”,
“start_time”: “00:00:12.300”,
“end_time”: “00:00:18.700”,
“text”: “請問你為什麼選擇這個資料集？”,
“is_final”: true,
“language”: “zh-TW”,
“engine”: “SpeechAnalyzer”,
“model”: “system”,
“confidence”: null,
“created_at”: “ISO-8601 timestamp”
}

volatile results 可以保存在記憶體或獨立 volatile 狀態，不應寫成 finalized transcript。若需要保存 debug，可另存 volatile_segments.jsonl。

Manual Marker

manual_markers.jsonl：

{
“marker_id”: “m_0001”,
“session_id”: “2026-06-15_1000_session”,
“timestamp”: “00:42:18.000”,
“type”: “question”,
“label”: “問題”,
“note”: “”,
“nearest_segment_ids”: [“seg_0132”, “seg_0133”],
“created_at”: “ISO-8601 timestamp”
}

預設 marker types：

* question：問題
* required_revision：必改
* suggestion：建議
* important_answer：重要回答

使用者必須能自定義 marker types，例如：

* 決議
* 待辦
* 爭議點
* 引用文獻
* 實驗問題
* 風險
* 追問
* 結論
* 重要數字
* 人名
* 專有名詞

Structured Event

events.json：

{
“event_id”: “evt_0001”,
“session_id”: “2026-06-15_1000_session”,
“time_start”: “00:42:18”,
“time_end”: “00:43:02”,
“speaker”: “口委A”,
“speaker_role”: “committee”,
“type”: “question”,
“topic”: “研究方法”,
“content”: “口委詢問為什麼選擇此資料集，以及資料集是否足以代表實際情境。”,
“response_summary”: “學生回覆目前資料來源限制，並說明選擇原因。”,
“action_item”: “補充資料集選擇理由、限制與代表性說明。”,
“priority”: “high”,
“confidence”: “medium”,
“needs_review”: true,
“source_segment_ids”: [“seg_0132”, “seg_0133”, “seg_0134”],
“source_marker_ids”: [“m_0001”],
“tags”: [“資料集”, “方法”, “代表性”]
}

九、自定義功能

請在資料模型與 UI 上預留以下自定義能力 讓 App 不限於論文場景：

1. 自定義模板。
2. 自定義 marker type。
3. 自定義 event type。
4. 自定義 topic taxonomy。
5. 自定義匯出欄位。
6. 自定義 Markdown 輸出格式。
7. 自定義 AI 整理 prompt。
8. 自定義專有名詞表。
9. 自定義 speaker role。
10. 自定義快捷鍵。


十一、語音識別要求

主要 ASR 引擎：

* Apple SpeechAnalyzer
* SpeechTranscriber
* on-device transcription
* zh-TW 優先
* 支援 live transcription
* 支援 prerecorded audio transcription
* 支援 volatile results
* 支援 finalized results
* 支援 timing metadata

請建立一個抽象 ASR protocol，例如：

protocol TranscriptionEngine {
func prepare(locale: Locale) async throws
func startLiveTranscription() async throws
func feedAudioBuffer(…)
func stop() async throws
var finalizedSegments: AsyncStream { get }
var volatileText: AsyncStream { get }
}

實作：

* AppleSpeechTranscriptionEngine
* FallbackSpeechRecognitionEngine
* MockTranscriptionEngine，用於 UI 測試

請不要讓 UI 直接依賴 SpeechAnalyzer 具體類別。
請把轉寫引擎抽象化，方便未來加入 WhisperKit、whisper.cpp、OpenAI、Deepgram 或其他 ASR。

十二、音訊錄製要求

請使用 AVFoundation 建立可靠錄音流程。

要求：

1. 支援選擇輸入裝置。
2. 顯示音量 level meter。
3. 錄音時寫入 raw audio。
4. 最好支援 chunk 保存，例如每 1–5 分鐘切一個 chunk，避免崩潰造成整段遺失。
5. 停止後合併或索引音訊 chunk。
6. pause / resume 時要正確記錄時間軸。
7. 轉寫時間戳與音訊時間軸要一致。
8. ASR 與錄音寫入要解耦。
9. 錄音權限錯誤要清楚提示。
10. 若使用者未授權麥克風，App 要提供引導。

十三、隱私模式

請實作 privacy mode 設計，MVP 至少要有資料模型與 UI 顯示，雲端功能可後續實作。

模式：

1. Local Only
    * 音訊留本機。
    * 逐字稿留本機。
    * 使用 Apple 本機 ASR。
    * 不發出網路請求。
2. Text Cloud Assist
    * 音訊留本機。
    * 只把使用者選定的逐字稿或 structured extraction request 傳給雲端 LLM。
    * 啟用前必須明確提醒。
3. Audio Cloud ASR
    * 允許把音訊片段傳到雲端 ASR。
    * 啟用前必須明確提醒。
    * 預設關閉。
    * API key 只從本機設定或環境變數讀取。

請在 UI 上持續顯示目前模式。
只要不是 Local Only，就必須有明顯但不干擾的提示。

十四、結構化整理

結構化整理可以

先根據 manual markers 與附近 transcript segments 生成初步事件卡：

* 使用 marker timestamp 找到前後 30–90 秒 transcript。
* 生成 event draft。
* event 需要標記 needs_review = true。
* 使用者可以手動編輯。

加入本機或雲端 LLM 整理：

* 根據模板 prompt 整理事件。
* 自動分類 type / topic / priority。
* 生成 action_item。
* 生成 response_summary。
* 保留 source_segment_ids。
* 不得覆蓋 raw transcript。
* 所有 AI 產物標記 needs_review。

十五、匯出要求

每個 session 可以匯出：

1. raw audio
2. live_transcript.md
3. live_segments.jsonl
4. manual_markers.jsonl
5. structured_notes.md
6. events.json
7. events.csv

Markdown 匯出格式需根據模板不同而不同。

論文口試 Markdown 格式範例

口試紀錄

基本資訊

* 日期：
* 場次：
* 模板：論文口試
* 語言：zh-TW
* ASR 引擎：
* 隱私模式：

口委問題

00:42:18 研究方法

口委詢問為什麼選擇此資料集，以及資料集是否足以代表實際情境。

* 學生回答摘要：
* 後續修正：
* 優先程度：
* 待人工確認：是

必改事項

建議事項

格式與排版問題

待確認片段

原始逐字稿索引

十六、專案檔案結構

請提出並實作清楚的檔案結構。建議類似：

十七、MVP 驗收標準

第一版 MVP 必須符合以下條件：

1. App 可以在 macOS 啟動。
2. 可以建立新 session。
3. 可以開始錄音。
4. 可以暫停與繼續。
5. 可以停止並保存 session。
6. 錄音資料增量保存。
7. ASR 失敗時錄音不中斷。
8. 可以使用 SpeechAnalyzer / SpeechTranscriber 進行本機轉寫，或在 API 不可用時使用 fallback / mock 模式。
9. 可以顯示 live transcript。
10. volatile 與 finalized transcript 在 UI 上有區分。
11. 可以按 Q/R/S/A 建立 marker。
12. marker 會立即寫入磁碟。
13. finalized transcript segment 會立即寫入磁碟。
14. 可以匯出 Markdown、JSON、CSV。
15. 可以建立第二個 session。
16. Local Only 模式不發出任何網路請求。
17. README 說明如何安裝、如何執行、如何授權麥克風、如何建立 session、如何匯出。
18. 專案不得包含 API key 或敏感資料。
19. App UI 必須具備基本 HCI 品質，不可只是粗糙 demo。
20. 至少提供 mock transcription mode，方便沒有 macOS 26 API 時測 UI。

十八、長時間穩定性測試

請設計測試方法：

1. 連續錄音 2 小時（耗時的就先不用）。
2. 錄音中 ASR 模擬失敗。
3. 錄音中 App 強制關閉後檢查已保存 chunks。
4. 快速連按 marker 按鈕。
5. pause / resume 多次。
6. 建立兩個 session。
7. 匯出空 transcript。
8. 匯出含多個 marker 的 transcript。
9. Local Only 模式檢查是否沒有網路呼叫。
10. 深色模式與淺色模式檢查可讀性。

十九、第一階段請先輸出內容

請先不要直接塞大量程式碼。第一輪請輸出：

1. 你對需求的理解。
2. 推薦架構。
3. macOS SpeechAnalyzer / SpeechTranscriber 整合策略。
4. 錄音與 ASR 解耦策略。
5. 檔案結構。
6. 資料模型。
7. 主要 UI 畫面設計。
8. 色彩與 HCI 設計策略。
9. MVP 任務拆分。
10. 風險清單與對策。
11. 第一個可執行版本要完成哪些檔案。
12. 接下來你會如何分批實作。

完成上述規劃後，再開始產生程式碼。

二十、禁止事項

請避免以下錯誤：

1. 不要第一版就做複雜 speaker diarization。
2. 不要第一版就做 iPhone / iPad companion app。
3. 不要第一版就依賴雲端 API。
4. 不要讓摘要覆蓋原始逐字稿。
5. 不要只把資料存在記憶體。
6. 不要把 API key 寫進程式碼。
7. 不要預設上傳音訊。
8. 不要把論文口試寫死成唯一場景。
9. 不要忽略深色模式。
10. 不要忽略麥克風權限。
11. 不要忽略錄音中斷與 ASR 失敗。
12. 不要用大量裝飾性動畫干擾現場記錄。
13. 不要讓 marker 建立流程需要多步驟確認。
14. 不要用顏色作為唯一狀態提示。
15. 不要假設使用者一直有網路。
16. 不要假設 SpeechAnalyzer 一定支援所有 locale。
17. 不要硬綁某一個 ASR 引擎，必須透過 protocol 抽象化。
18. 不要犧牲錄音穩定性換取漂亮功能。

二十一、開發優先順序

請依照以下順序開發：

1. 專案骨架。
2. 資料模型。
3. SessionManager。
4. SessionStorage。
5. 基本 UI shell。
6. 錄音權限與 AudioRecorder。
7. 音訊 chunk 保存。
8. Start / Pause / Resume / Stop。
9. Manual markers。
10. Exporters。
11. MockTranscriptionEngine。
12. AppleSpeechTranscriptionEngine。
13. Live transcript UI。
14. volatile / finalized transcript UI。
15. Template 系統。
16. Thesis defense template。
17. Meeting / Interview / Lecture templates。
18. EventDraftBuilder。
19. Settings。
20. README 與 docs。

請在每一步完成後說明：

* 新增哪些檔案
* 修改哪些檔案
* 如何執行
* 如何測試
* 目前仍有哪些限制