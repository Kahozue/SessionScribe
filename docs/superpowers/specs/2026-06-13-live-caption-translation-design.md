# 即時字幕體驗 + 即時翻譯 設計

日期：2026-06-13
狀態：已確認，實作中
對應里程碑：M9（即時感）、M10（字幕浮層）、M11（即時翻譯）
落地後折回 `docs/SPEC.md` 成「規格 1.2」新節（比照規格 1.1 的作法）。

## 背景與定位

v0.2 已完成並推 GitHub。`AppleSpeechEngine` 已是 macOS 26 SpeechAnalyzer + SpeechTranscriber
+ AnalyzerInput + async results stream 的主路，`volatileResults` 已開、`setContext` 詞彙提示已接。
「遷移到新管線」不是待辦，待辦是調校即時感、重設計浮動視窗、新增即時翻譯。

三條線收斂成一個分階段 spec：A 即時感（呈現層）、B 字幕浮層（Luma 式）、C 即時翻譯（設定開關，預設關）。

## 既定決策

- 範圍：三項全做，分階段。A、B 先，C 後。
- 即時感只動呈現層，不碰辨識行為（不做錄音中 `finalize(through:)`），準確度零影響。
- 浮動視窗重設計成字幕浮層（Luma 式），非美化面板。
- 翻譯做成設定開關，預設關；目標語言設定可選，預設英文；來源取辨識語言（目前 zh-TW）。
- 翻譯策略固定 `TranslationSession.Strategy.lowLatency`（需 deployment target 升 macOS 26.4）。
- 譯文只即時顯示、不持久化（不動 JSONL / DATA_FORMATS schema）。
- 字幕浮層用獨立字級 `captionFontSizeKey`，與主視窗 `fontSize` 脫鉤。

## 階段一（M9）即時感：只動呈現層

定位：volatile 資料路徑（engine → coordinator → viewModel）全 async hop、無節流無 sleep，本就即時。
鈍感來源是 `TranscriptListView.scrollToTail` 每次 volatile 更新都跑 0.35s 彈簧捲動，volatile 高頻更新時
動畫互相打斷。

改動（只動 `TranscriptListView.swift`）：

- volatile 變動觸發的捲動 → 不加動畫（就地瞬間到底）。
- 新 finalized 段落（`transcript.count` 變動）→ 輕量 0.2s ease 捲動。
- 驗證主視窗 `VolatileRowView` 隨 volatile 即時換字（現況已是）。

準確度零影響。

## 階段二（M10）字幕浮層（Luma 式）

新檔 `Sources/SSUI/CaptionOverlayView.swift`，取代 `FloatingTranscriptView` 作為浮動視窗內容。

app target（`SessionScribeApp.swift`）的 `Window("floating-transcript")` 改無邊框透明：
`.windowStyle(.plain)` + `.windowBackgroundDragBehavior(.enabled)` + `.defaultWindowPlacement`
預設底部置中，保留 `.windowLevel(.floating)`、`.windowResizability(.contentSize)`。

字幕呈現：

- 圓角、半透明深色底字幕條（非 `.thinMaterial` 面板感）。
- 兩行滾動字幕：下行「當前句」（有 volatile 顯示 volatile，否則最後一句 finalized），大字、亮；
  上行「前一句」finalized，小一點、淡。
- 無時間戳、無狀態列、無捲動歷史。
- hover 時浮現極簡控制（關閉、字級 +/-、透明度），移開淡出。
- 字級用獨立 `DisplaySettings.captionFontSizeKey`（預設 24，範圍 16–48），浮層 +/- 只調自己。
- 透明度用 `DisplaySettings.captionOpacityKey`（預設約 0.7）。

推導抽成 `RecordingViewModel.captionLines`（純函式，回傳 `(previous: String?, current: String, isVolatile: Bool)`），
可單元測試。View 本身手動視覺驗收。

## 階段三（M11）即時翻譯：設定開關，預設關

前置硬條件：deployment target 升 macOS 26.4（`lowLatency` 策略需要）。

前置 spike（驗不過就砍 Phase 3）：app 為 App Sandbox 無 network entitlement、OS 強制零網路。
Speech 模型下載走系統服務已驗證可行；翻譯模型理論同機制但未在此 sandbox 設定驗過。建 Phase 3 前
先 spike「無 network entitlement 下 lowLatency 翻譯模型能否下載＋on-device 推論」，比照
`docs/spikes/2026-06-12-speech-zh-tw.md` 記錄。驗不過則停 Phase 3、退回只轉寫。

分層（比照 transcription）：

- `LiveTranslator` protocol（SSCore）：`availability(source:target:)`、`prepare(source:target:)`、
  `translate(_:) async throws -> String`。
- `AppleTranslator`（SSTranscription）：包 `TranslationSession`，策略固定 `.lowLatency`。
- `MockTranslator`（測試用）。
- `TranslationCoordinator`（SSCore，actor）：吸收翻譯錯誤使其絕不影響錄音與轉寫（比照核心原則 2），
  finalized 段落文字 → 譯文，以 `(segmentID, 譯文)` 經 AsyncStream 回傳。

資料流與取捨：

- 只翻 finalized 段落，不翻 volatile（避免閃爍與成本）。字幕浮層原文即時跟手，譯文在該句定稿後
  才出現在原文下方；譯文必然比原文晚一截，這是即時翻譯本質。
- viewModel 存 `translations: [segmentID: String]`，字幕浮層與主視窗列表以 segmentID 查譯文疊原文下。
- 譯文不寫磁碟。

設定（轉寫分頁新增）：翻譯開關 `translationEnabledKey`（預設 false）、目標語言 picker
`translationTargetKey`（預設 "en"）、「準備翻譯模型」狀態與下載按鈕。模型在開始錄音前 `prepare` 備妥，
避免錄音中跳系統下載 UI。

錯誤處理：模型未裝就啟用 → 設定顯示「需下載」、live 翻譯維持關直到就緒；錄音中某句翻譯失敗 →
只顯示原文、記錄、繼續；翻譯整體失效不影響轉寫與錄音。

## 測試

- 階段一：`captionLines` 推導單元測試；捲動手感手動驗收。
- 階段二：`captionLines`（previous/current/isVolatile）單元測試；浮層視覺手動驗收。
- 階段三：`TranslationCoordinator` 以 `MockTranslator` 測錯誤吸收與 segmentID 對應；availability/
  預下載邏輯以注入 availability 測；Apple 實作實機驗收。

## 不在範圍

- 譯文持久化、匯出含譯文。
- 錄音中主動 finalize。
- 辨識來源語言可選（目前固定 zh-TW）。
- 舊系統（macOS 15）legacy adapter。
