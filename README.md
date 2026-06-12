# SessionScribe

macOS 原生的錄音、即時轉寫與事件標記工具。為現場記錄場景設計（論文口試、會議、訪談、講座），核心原則是現場可靠性：原始錄音永遠是最高優先級，ASR 或任何後續處理失敗都不影響錄音與已保存的資料。

目前狀態：M0（專案骨架）。功能里程碑見下方。

## 核心特性（規劃中）

- 完整錄音，PCM CAF 分塊增量保存，崩潰最多損失當前緩衝
- macOS 26 SpeechAnalyzer / SpeechTranscriber 本機即時轉寫（zh-TW 已驗證支援）
- volatile 與 finalized 轉寫結果在 UI 上明確區分
- 單鍵事件標記（問題、必改、建議、重要回答），立即落盤
- Markdown / JSON / CSV 匯出
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

核心邏輯在 `Packages/SessionScribeKit`，單元測試不需開 Xcode：

```bash
cd Packages/SessionScribeKit
swift test
```

## 麥克風授權

第一次開始錄音時，系統會詢問麥克風權限。若先前拒絕過，到「系統設定 > 隱私權與安全性 > 麥克風」開啟 SessionScribe。錄音功能自 M2 起提供。

## 隱私

- 預設 Local Only：音訊與逐字稿只存本機，使用 Apple 本機語音模型
- App 的 entitlements 不含網路權限，可直接檢視 `SessionScribe/SessionScribe.entitlements` 驗證
- 雲端輔助功能（v0.3）採 opt-in，啟用前明確提示，API key 只存本機

## 文件

- [規格書](docs/SPEC.md)
- [架構文件](docs/ARCHITECTURE.md)
- [Spike：zh-TW 語音支援驗證](docs/spikes/2026-06-12-speech-zh-tw.md)

## 里程碑

| 里程碑 | 內容 | 狀態 |
|---|---|---|
| M0 | 專案骨架、entitlements、UI 殼層、zh-TW spike | 完成 |
| M1 | 資料模型、儲存層、MediaClock | 未開始 |
| M2 | 錄音管線、分塊保存、pause/resume、崩潰恢復 | 未開始 |
| M3 | 事件標記、匯出 | 未開始 |
| M4 | Mock 引擎、即時逐字稿 UI | 未開始 |
| M5 | Apple Speech 引擎整合（v0.1 完成） | 未開始 |

## License

待定。
