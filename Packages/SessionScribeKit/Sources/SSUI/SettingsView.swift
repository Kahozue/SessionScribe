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
            MarkerSettingsTab(model: model)
                .tabItem {
                    Label("標記", systemImage: "bookmark")
                }
            TranscriptionSettingsTab(model: model)
                .tabItem {
                    Label("轉寫", systemImage: "waveform.badge.mic")
                }
            CloudSettingsTab()
                .tabItem {
                    Label("雲端", systemImage: "cloud")
                }
        }
        .frame(width: 460)
        .padding(.bottom, 8)
        .appTypography()
        .dynamicTypeSize(DisplaySettings.uiTypeSize)
    }
}

private struct DisplaySettingsTab: View {
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize
    @AppStorage(DisplaySettings.appearanceKey)
    private var appearance = "system"

    var body: some View {
        Form {
            Section("介面字級") {
                HStack {
                    Slider(
                        value: $fontSize,
                        in: DisplaySettings.fontSizeRange,
                        step: 1
                    ) {
                        Text("字級")
                    }
                    Text("\(Int(fontSize)) pt")
                        .appFont(.callout, monospacedDigit: true)
                        .frame(width: 44, alignment: .trailing)
                }
                Text("範例文字：請問你為什麼選擇這個資料集？")
                    .appFont(.body)
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

private struct MarkerSettingsTab: View {
    @Bindable var model: RecordingViewModel
    @State private var newRaw = ""
    @State private var newLabel = ""

    private var canAdd: Bool {
        !newRaw.trimmingCharacters(in: .whitespaces).isEmpty
            && !newLabel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("自訂標記類型") {
                Text("模板四鍵之外的額外標記，錄音時可從即時右欄的「更多標記」選用。type 是寫入紀錄的識別碼（建議英數），標籤是顯示文字。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                if model.customMarkerTypes.isEmpty {
                    Text("尚無自訂標記。")
                        .appFont(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.customMarkerTypes, id: \.rawValue) { type in
                        HStack(spacing: 8) {
                            Text(type.label)
                            Text(type.rawValue)
                                .appFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .onDelete { model.removeMarkerTypes(atOffsets: $0) }
                }
                HStack(spacing: 8) {
                    TextField("type（英數）", text: $newRaw)
                    TextField("標籤", text: $newLabel)
                    Button("新增") {
                        model.addMarkerType(rawValue: newRaw, label: newLabel)
                        newRaw = ""
                        newLabel = ""
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TranscriptionSettingsTab: View {
    @Bindable var model: RecordingViewModel
    @AppStorage(DisplaySettings.useMockEngineKey)
    private var useMockEngine = false
    @AppStorage(DisplaySettings.recognitionLanguageKey)
    private var recognitionLanguage = CaptionLanguage.zhTW.code
    @AppStorage(DisplaySettings.translationEnabledKey)
    private var translationEnabled = false
    @AppStorage(DisplaySettings.translationTargetKey)
    private var translationTarget = CaptionLanguage.zhTW.code
    @State private var newFrom = ""
    @State private var newTo = ""

    private var canAdd: Bool {
        !newFrom.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sameLanguageWarning: Bool {
        translationEnabled && translationTarget == recognitionLanguage
    }

    var body: some View {
        Form {
            Section("辨識語言") {
                Picker("辨識語言", selection: $recognitionLanguage) {
                    ForEach(CaptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.code)
                    }
                }
                Text("決定逐字稿用哪種語言辨識，也是即時翻譯的來源語言。下一場錄音生效。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                if let progress = model.modelDownloadProgress {
                    ProgressView(value: progress) {
                        Text("下載辨識模型中… \(Int(progress * 100))%")
                            .appFont(.caption)
                    }
                } else {
                    Button("預先下載此語言模型") {
                        model.downloadRecognitionModel()
                    }
                    Text("先下好，正式錄音時就不必等下載。中文通常已內建；英文、日文首次需下載。")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("即時翻譯") {
                Toggle("開啟即時翻譯（下一場生效）", isOn: $translationEnabled)
                if translationEnabled {
                    Picker("翻譯成", selection: $translationTarget) {
                        ForEach(CaptionLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.code)
                        }
                    }
                    if sameLanguageWarning {
                        Text("目標語言與辨識語言相同，不會翻譯。")
                            .appFont(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("譯文只在每句定稿後出現（會比原文晚一截），疊在原文下。首次使用會下載語言模型；需 macOS 26.4 以上。")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("引擎") {
                Toggle("使用 Mock 引擎（開發測試用，下一場生效）", isOn: $useMockEngine)
                Text("正常使用時保持關閉，由降級鏈自動選擇：SpeechAnalyzer、SFSpeechRecognizer、純錄音。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("專有名詞校正表") {
                Text("轉寫產生時做全文字面替換，下一場轉寫生效。中英夾雜術語可在此校正，校正為留空表示刪除該詞。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                if model.libraryConfig.lexicon.isEmpty {
                    Text("尚無規則。")
                        .appFont(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.libraryConfig.lexicon) { rule in
                        HStack(spacing: 8) {
                            Text(rule.from)
                            Image(systemName: "arrow.right")
                                .appFont(.caption)
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
                        .appFont(.caption)
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

private struct CloudSettingsTab: View {
    @State private var settings = CloudLLMSettings.load()
    @State private var showEnableWarning = false
    private let keychain: KeychainStore = SystemKeychainStore()

    private static let featureRows: [(AssistFeature, String, Bool)] = [
        (.offlineTranscript, "轉錄稿", true),
        (.liveASR, "即時 ASR", false),   // 雲端串流開發中：雲端段停用
        (.summary, "摘要", true),
        (.events, "結構化事件", true),
        (.translation, "字幕翻譯", true),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("啟用雲端", isOn: Binding(
                    get: { settings.enabled },
                    set: { newValue in
                        if newValue { showEnableWarning = true }
                        else { settings.enabled = false; persist() }
                    }))
            }

            Section("每項功能引擎") {
                ForEach(Self.featureRows, id: \.0) { feature, label, cloudEnabled in
                    Picker(label, selection: Binding(
                        get: { settings.engine(for: feature) },
                        set: { newValue in
                            // 即時 ASR 雲端串流開發中：不接受選成雲端（segment 點了不生效）。
                            guard cloudEnabled || newValue != .cloud else { return }
                            settings.setEngine(newValue, for: feature); persist()
                        })) {
                        Text("本地").tag(AssistEngineKind.local)
                        Text(cloudEnabled ? "雲端" : "雲端（開發中）").tag(AssistEngineKind.cloud)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!settings.enabled)
                    .opacity(cloudEnabled ? 1 : 0.6)
                }
            }

            ProviderSlotSection(
                title: "文字類供應商（摘要/事件/翻譯）",
                settings: $settings, keychain: keychain,
                providerID: $settings.textProviderID, sttOnly: false)

            ProviderSlotSection(
                title: "語音類供應商（轉錄稿/ASR）",
                settings: $settings, keychain: keychain,
                providerID: $settings.audioProviderID, sttOnly: true)
        }
        .formStyle(.grouped)
        .alert("啟用雲端", isPresented: $showEnableWarning) {
            Button("取消", role: .cancel) {}
            Button("啟用") { settings.enabled = true; persist() }
        } message: {
            Text("依各功能設定運作。選為雲端的文字功能會上傳逐字稿與事件文字；選為雲端的轉錄稿會上傳音訊。未選雲端者一律留在本機。AI 產物標記需複查。")
        }
    }

    private func persist() { settings.save() }
}

/// 單一供應商槽：選 active、新增樣板、編輯目前供應商與金鑰、測試連線。
private struct ProviderSlotSection: View {
    let title: String
    @Binding var settings: CloudLLMSettings
    let keychain: KeychainStore
    @Binding var providerID: String?
    /// 只列支援 STT 的供應商（語音槽）。
    let sttOnly: Bool

    @State private var apiKey = ""
    @State private var testResult: String?

    private var visibleProviders: [CloudProviderConfig] {
        sttOnly ? settings.providers.filter { $0.format.supportsSTT } : settings.providers
    }
    private var active: CloudProviderConfig? {
        settings.providers.first { $0.id == providerID }
    }
    private var templates: [CloudProviderConfig] {
        sttOnly ? CloudProviderConfig.builtInAudioTemplates
                : CloudProviderConfig.builtInTemplates
    }

    var body: some View {
        Section(title) {
            Picker("使用", selection: Binding(
                get: { providerID ?? "" },
                set: { providerID = $0.isEmpty ? nil : $0; loadKey(); persist() })) {
                Text("未選擇").tag("")
                ForEach(visibleProviders) { p in Text(p.displayName).tag(p.id) }
            }
            Menu("新增供應商") {
                ForEach(templates) { tpl in Button(tpl.displayName) { addTemplate(tpl) } }
            }

            if let provider = active,
               let index = settings.providers.firstIndex(where: { $0.id == provider.id }) {
                Picker("格式", selection: $settings.providers[index].format) {
                    ForEach(CloudProviderFormat.allCases.filter { !sttOnly || $0.supportsSTT }, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                TextField("Base URL", text: $settings.providers[index].baseURL)
                TextField("Model", text: $settings.providers[index].model)
                SecureField("API key", text: $apiKey)
                HStack {
                    Button("儲存金鑰") { saveKey(account: provider.id) }
                    if !sttOnly {
                        Button("測試連線") { testConnection() }
                    }
                    if let testResult {
                        Text(testResult).appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                if sttOnly {
                    Text("語音轉文字供應商會在執行離線轉錄時驗證 `/audio/transcriptions` 或 Gemini 音訊輸入。")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("刪除此供應商", role: .destructive) { removeProvider(provider.id) }
                .onChange(of: settings.providers) { persist() }
            }
        }
        .onAppear { loadKey() }
    }

    private func persist() { settings.save() }

    private func addTemplate(_ tpl: CloudProviderConfig) {
        var copy = tpl
        copy.id = "\(tpl.id)-\(UUID().uuidString.prefix(6))"
        settings.providers.append(copy)
        providerID = copy.id
        apiKey = ""
        persist()
    }

    private func removeProvider(_ id: String) {
        settings.providers.removeAll { $0.id == id }
        // 同一供應商可能同時被文字槽與語音槽選用，兩槽都要清掉懸空參考。
        if settings.textProviderID == id { settings.textProviderID = nil }
        if settings.audioProviderID == id { settings.audioProviderID = nil }
        try? keychain.deleteSecret(account: id)
        loadKey()
        persist()
    }

    private func loadKey() {
        apiKey = (try? keychain.secret(account: providerID ?? "")) ?? ""
    }

    private func saveKey(account: String) {
        try? keychain.setSecret(apiKey, account: account)
        testResult = "已儲存"
    }

    private func testConnection() {
        guard let provider = active else { return }
        try? keychain.setSecret(apiKey, account: provider.id)
        guard let client = AssistResolver.makeClient(provider: provider, key: apiKey) else {
            testResult = "設定不完整"; return
        }
        testResult = "測試中…"
        Task {
            do {
                _ = try await client.complete(system: "回覆 JSON {\"ok\":true}", user: "ping")
                await MainActor.run { testResult = "連線成功" }
            } catch let error as CloudLLMError {
                await MainActor.run { testResult = error.userMessage }
            } catch {
                await MainActor.run { testResult = "連線失敗" }
            }
        }
    }
}
