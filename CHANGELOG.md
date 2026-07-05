# Changelog

格式沿用日常語彙，不套制式模板；日期為驗收或落地時間。

## v0.3（進行中，2026-06 至今）

- 各功能引擎個別選擇：離線轉錄稿、即時 ASR、摘要、結構化事件、字幕翻譯五項功能各自選本地或雲端；供應商分文字與語音兩槽。
- 整份逐字稿摘要：檢視頁右欄本機 AI 產生摘要、重點與待辦，可折疊。
- 雲端文字整理（Text Cloud Assist）：OpenAI 相容、Anthropic、Gemini 三格式。
- 雲端離線轉錄稿（Audio Cloud ASR）：整段音訊以單一 m4a 上傳 OpenAI 相容或 Gemini STT。
- 雲端字幕翻譯：每句定稿文字送雲端 LLM，不涉音訊。
- 重新轉錄入口：已轉錄 session 二次確認後以目前設定覆蓋逐字稿。
- API key 存 Keychain、安全輸入；network entitlement 加入，Local Only 改由程式層堅守（唯一 URLSession 只在總開關開且該功能選雲端時建構）。
- 播放頁波形圖：離線抽樣、快取、點擊拖曳 seek、markers 疊線。
- menu bar 錄音控制、首次啟動 onboarding、鍵盤快捷鍵總覽。
- UI/UX 細化：設計 tokens 基準、錄音狀態列、微互動統一、Reduce Motion 全面降級、無障礙補齊。
- MIT License、雙語 README、GitHub Actions CI。

## v0.2（2026-06）

- 內建場景模板：論文口試、會議、訪談、講座；錄音四鍵文案與 type 依模板切換。
- 自訂標記類型與專有名詞表（lexicon 套用於後續轉寫）。
- 結構化事件：依標記彙整草稿、本機 Apple Foundation Models 產生與補齊，AI 產物一律標需複查；事件可編輯。
- 標記色票（Cmd+1 至 4 固定四色）與取消標記。
- 匯出新增 structured_notes.md、events.json、events.csv、m4a。

## v0.1（2026-06）

- 崩潰安全錄音管線：PCM CAF 分塊增量保存加 manifest 索引，啟動時自動恢復殘留 session。
- 本機即時轉寫：SpeechAnalyzer 主引擎（zh-TW 驗證）、SFSpeechRecognizer 備援、純錄音降級；Mock 引擎供無語音環境開發。
- 單鍵事件標記（Q/R/S/A 與 Cmd+1 至 4）、多格式匯出（transcript.md、markers.csv、session.json、jsonl）。
- 浮動置頂即時字幕視窗、全畫面字級與深淺色。
- 匯入音檔轉 session、錄音檢視頁 chunk 串接播放與歌詞式定位。
- session 分類、多選批次管理、跨逐字稿搜尋。
