import SwiftUI

/// App 設定視窗（Cmd+,）。字級與外觀自工具列移入此處；
/// v0.2 起的設定（模板、自訂標記、名詞表、雲端 opt-in）都收在這裡。
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem {
                    Label("顯示", systemImage: "textformat.size")
                }
            TranscriptionSettingsTab()
                .tabItem {
                    Label("轉寫", systemImage: "waveform.badge.mic")
                }
        }
        .frame(width: 440)
        .padding(.bottom, 8)
    }
}

private struct DisplaySettingsTab: View {
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize
    @AppStorage(DisplaySettings.appearanceKey)
    private var appearance = "system"

    var body: some View {
        Form {
            Section("逐字稿字級") {
                HStack {
                    Slider(
                        value: $fontSize,
                        in: DisplaySettings.fontSizeRange,
                        step: 1
                    ) {
                        Text("字級")
                    }
                    Text("\(Int(fontSize)) pt")
                        .font(.callout.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                Text("範例文字：請問你為什麼選擇這個資料集？")
                    .font(.system(size: fontSize))
                Button("重設為預設值") {
                    fontSize = DisplaySettings.defaultFontSize
                }
            }
            Section("外觀") {
                Picker("外觀模式", selection: $appearance) {
                    Text("跟隨系統").tag("system")
                    Text("淺色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TranscriptionSettingsTab: View {
    @AppStorage(DisplaySettings.useMockEngineKey)
    private var useMockEngine = false

    var body: some View {
        Form {
            Section("引擎") {
                Toggle("使用 Mock 引擎（開發測試用，下一場生效）", isOn: $useMockEngine)
                Text("正常使用時保持關閉，由降級鏈自動選擇：SpeechAnalyzer、SFSpeechRecognizer、純錄音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("即將推出（v0.2）") {
                Text("場景模板、自訂標記類型、專有名詞校正表、匯出 m4a 轉檔將在此設定。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
