# Spike：SpeechTranscriber 的 zh-TW 支援驗證

日期：2026-06-12
環境：macOS 26.5 (25F71)、Xcode 26.5 (17F42)、Swift 6.3.2、MacBook Air M3

## 問題

`docs/ARCHITECTURE.md` 待驗證事項第 1 條：SpeechTranscriber 是否支援 zh-TW。此答案決定 v0.1 主引擎人選。

## 方法

編譯並執行獨立 Swift 程式，呼叫：

- `SpeechTranscriber.supportedLocales`
- `SpeechTranscriber.installedLocales`
- `DictationTranscriber.supportedLocales`
- `SFSpeechRecognizer.supportedLocales()`

## 結果

| API | zh-TW | 備註 |
|---|---|---|
| SpeechTranscriber.supportedLocales | 支援 | 共 30 個 locale，含 zh_TW、zh_CN、zh_HK、yue_CN |
| SpeechTranscriber.installedLocales | 已安裝 | 本機已含 zh_TW 模型，無需下載 |
| DictationTranscriber.supportedLocales | 支援 | 共 54 個 locale |
| SFSpeechRecognizer.supportedLocales() | 支援 | zh-TW、zh-CN、zh-HK |

SpeechTranscriber 支援的 30 個 locale：de_AT、de_CH、de_DE、en_AU、en_CA、en_GB、en_IE、en_IN、en_NZ、en_SG、en_US、en_ZA、es_CL、es_ES、es_MX、es_US、fr_BE、fr_CA、fr_CH、fr_FR、it_CH、it_IT、ja_JP、ko_KR、pt_BR、pt_PT、yue_CN、zh_CN、zh_HK、zh_TW。

## 結論

1. v0.1 主引擎照原計畫使用 SpeechAnalyzer + SpeechTranscriber，zh_TW 完整支援且目標機器上模型已就緒。
2. fallback 鏈（DictationTranscriber、SFSpeechRecognizer）每一層都有 zh-TW 支援，風險清單第 1 項解除。
3. AssetInventory 下載引導仍要實作：其他機器或語言可能未安裝模型，`installedLocales` 與 `supportedLocales` 的差集就是需要下載的情況。
4. API 型態確認：`supportedLocales` 與 `installedLocales` 是 async static property，與架構文件假設一致。
