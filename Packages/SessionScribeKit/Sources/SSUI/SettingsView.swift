import SSCore
import SwiftUI

/// App 設定視窗（Cmd+,）。字級與外觀自工具列移入此處；
/// v0.2 起的設定（名詞表、自訂標記等）都收在這裡，與主視窗共用 model。
public struct SettingsView: View {
    let model: RecordingViewModel

    public init(model: RecordingViewModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem {
                    Label("顯示", systemImage: "textformat.size")
                }
            TranscriptionSettingsTab(model: model)
                .tabItem {
                    Label("轉寫", systemImage: "waveform.badge.mic")
                }
        }
        .frame(width: 460)
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
    @Bindable var model: RecordingViewModel
    @AppStorage(DisplaySettings.useMockEngineKey)
    private var useMockEngine = false
    @State private var newFrom = ""
    @State private var newTo = ""

    private var canAdd: Bool {
        !newFrom.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("引擎") {
                Toggle("使用 Mock 引擎（開發測試用，下一場生效）", isOn: $useMockEngine)
                Text("正常使用時保持關閉，由降級鏈自動選擇：SpeechAnalyzer、SFSpeechRecognizer、純錄音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("專有名詞校正表") {
                Text("轉寫產生時做全文字面替換，下一場轉寫生效。中英夾雜術語可在此校正，校正為留空表示刪除該詞。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.libraryConfig.lexicon.isEmpty {
                    Text("尚無規則。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.libraryConfig.lexicon) { rule in
                        HStack(spacing: 8) {
                            Text(rule.from)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(rule.to.isEmpty ? "（刪除）" : rule.to)
                                .foregroundStyle(rule.to.isEmpty ? .secondary : .primary)
                            Spacer()
                        }
                    }
                    .onDelete { model.removeLexiconRules(atOffsets: $0) }
                }
                HStack(spacing: 8) {
                    TextField("原詞", text: $newFrom)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("校正為", text: $newTo)
                    Button("新增") {
                        model.addLexiconRule(from: newFrom, to: newTo)
                        newFrom = ""
                        newTo = ""
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .formStyle(.grouped)
    }
}
