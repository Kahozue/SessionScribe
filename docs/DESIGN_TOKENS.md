# 設計 tokens（作品集輪 UI/UX 打磨基準）

比對基準文件：打磨與新 UI 一律對照本清單，偏差需有光學對齊理由。
風格準則：iOS 風、乾淨、少文字、不花俏。

## 間距（4pt 節奏）

| token | 值 | 用途 |
|---|---|---|
| space-1 | 4 | 同組緊鄰元素（圖示與文字、chip 內元素） |
| space-2 | 6 | chip 水平內距、小元素間距 |
| space-3 | 8 | 元件間距基準、卡片內元素 |
| space-4 | 10 | 控制列元素間距 |
| space-5 | 12 | 卡片內距、面板內距 |
| space-6 | 16 | 區塊間距、視窗邊距 |

chip 內距：horizontal 6 / vertical 2。

## 圓角

| token | 值 | 用途 |
|---|---|---|
| radius-s | 6 | 小元素（按鈕底、輸入框、內嵌 chip） |
| radius-m | 8 | 卡片（右欄三區、列表卡） |
| radius-l | 16 | 浮層（字幕浮層） |

chip 用 Capsule。

## 色彩語意

| 語意 | 值 | 用途 |
|---|---|---|
| accent | Color.accentColor | 播放進度、選取、主要動作 |
| marker 色票 | blue/red/green/purple（slot 0-3）、gray（fallback） | 標記四鍵、事件卡、波形疊線；取自 MarkerVisualStyle |
| 錄音 | red | 錄音中狀態點與符號 |
| 警告、需複查 | orange | AI 產物需複查標籤、設定警告 |
| 譯文 | teal | 逐字稿譯文行 |
| 文字層級 | primary/secondary/tertiary | 內文/輔助說明/弱化資訊 |
| 背景層 | quaternary | 卡片與輸入區底色 |

marker 色票的透明度階：背景 0.14、邊框 0.42（MarkerVisualStyle）。

## 字級

全部走 `appFont(_:)`（跟隨全畫面字級調整），視窗級容器套 `appTypography()`。

| 階層 | 用途 |
|---|---|
| title3 | 播放鍵等大圖示 |
| body | 內文 |
| callout | 控制列、按鈕文字 |
| caption | 輔助說明、時間戳 |

例外（合法的獨立字級系統，不套 appFont）：
- 逐字稿內文與歌詞模式：跟隨 `transcriptFontSize` 動態字級。
- 字幕浮層：跟隨 `captionFontSize` 獨立設定。

## 動效原則

- 全部動畫過 Reduce Motion 檢核：`accessibilityReduceMotion` 開啟時降級為直接切換。
- 節奏統一，不花俏；微互動限 hover、按下、折疊 chevron、chip 短暫高亮、橫幅進出場。
