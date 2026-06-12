# SessionScribe

macOS 原生的錄音、即時轉寫與事件標記工具。為現場記錄場景設計（論文口試、會議、訪談、講座），核心原則是現場可靠性：原始錄音永遠是最高優先級，ASR 或任何後續處理失敗都不影響錄音與已保存的資料。

目前狀態：M0 至 M8 完成（v0.1 功能齊備，待實機驗收）。

## 功能

- 完整錄音：PCM CAF 分塊增量保存加 manifest 索引，崩潰最多損失當前緩衝；啟動時自動恢復崩潰殘留 session
- 本機即時轉寫：macOS 26 SpeechAnalyzer / SpeechTranscriber 為主引擎（zh-TW 已驗證），SFSpeechRecognizer 備援，全部不可用時自動退為純錄音；Mock 引擎供無語音環境開發測試
- volatile 與 finalized 轉寫結果在 UI 上明確區分；浮動置頂的即時逐字稿視窗
- 單鍵事件標記：Q 問題、R 必改、S 建議、A 重要回答（Cmd+1 至 4 全域），立即落盤
- 匯出：transcript.md、markers.csv、session.json、jsonl 原檔副本；逐字稿可多選後匯出選取段落
- 匯入音檔（caf、wav、m4a、mp3、aiff）轉為標準 session，可選離線轉寫
- 錄音檢視頁：chunk 串接播放、歌詞式定位（當前段放大置中、點擊跳轉播放）
- 跨逐字稿搜尋（segments 與標記備註），結果一鍵跳轉定位
- session 分類（自訂、隱藏）、多選批次移動與刪除
- 字級調整與深淺色外觀
- 預設 Local Only：App Sandbox 不含任何 network entitlement，零網路由作業系統強制保證

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

1. 工具列「新增 Session」（可先選輸入裝置），按「開始」錄音。
2. 逐字稿區聚焦時按 Q/R/S/A 建立標記，或用 Inspector 的大按鈕、Cmd+1 至 4。
3. 「停止」保存後按「匯出」選資料夾。側欄右鍵任何 session 也可匯出或在 Finder 顯示。
4. 「匯入音檔」可把既有錄音轉成 session，匯入後可選擇立即離線轉寫。
5. 側欄點選舊 session 進入檢視頁播放；搜尋列可跨所有逐字稿找文字；右鍵多選可批次移分類或刪除。

Session 資料存於 app container 內 `~/Library/Containers/io.github.kahozue.SessionScribe/Data/Library/Application Support/SessionScribe/Sessions/`，每場一個資料夾，格式見 `docs/DATA_FORMATS.md`。

## 權限

- 麥克風：第一次開始錄音時系統會詢問。若先前拒絕過，到「系統設定 > 隱私權與安全性 > 麥克風」開啟 SessionScribe，app 也會提供引導。
- 語音辨識：只有降級到備援引擎 SFSpeechRecognizer 時需要；主引擎 SpeechAnalyzer 為純本機處理。

## 測試

```bash
cd Packages/SessionScribeKit
swift test
```

單元測試不需要麥克風與語音模型。實機驗證清單見 `docs/TESTING.md`。

## 隱私

- 預設 Local Only：音訊與逐字稿只存本機，使用 Apple 本機語音模型
- App 的 entitlements 不含網路權限，可直接檢視 `SessionScribe/SessionScribe.entitlements` 驗證
- 雲端輔助功能（v0.3）採 opt-in，啟用前明確提示，API key 只存本機
- 專案不含 API key 與個人資料

## 文件

- [規格書](docs/SPEC.md)（1.1，含第十五節使用者新增功能）
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

v0.1 驗收（規格書第十二節 21 條）待實機逐條檢核，清單與步驟見 `docs/TESTING.md`。

## License

待定。
