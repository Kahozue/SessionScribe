import SwiftUI
@preconcurrency import Translation

/// 臨時：即時翻譯 sandbox spike（規格 1.2 Phase 3 前置 gate）。
/// 驗 App Sandbox 無 network entitlement 下，lowLatency 翻譯模型能否下載＋on-device 推論。
/// 走的是 Phase 3 正式要用的 direct-init 路徑（非 SwiftUI .translationTask）。
/// 驗完即整檔刪除，連同 SettingsView 的嵌入點。
struct TranslationSpikeView: View {
    @State private var status = "尚未執行"
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("臨時驗證：zh-TW → en，lowLatency 策略，direct init。按下會嘗試下載模型並翻一句。")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Button(running ? "執行中…" : "執行翻譯 spike") {
                running = true
                status = "執行中…"
                Task {
                    let result = await runSpike()
                    status = result
                    running = false
                }
            }
            .disabled(running)
            Text(status)
                .appFont(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @MainActor
    private func runSpike() async -> String {
        guard #available(macOS 26.4, *) else {
            return "此機器非 macOS 26.4+，lowLatency 策略不可用。"
        }
        let source = Locale.Language(identifier: "zh-TW")
        let target = Locale.Language(identifier: "en")
        let session = TranslationSession(
            installedSource: source, target: target, preferredStrategy: .lowLatency)
        do {
            try await session.prepareTranslation()
        } catch {
            return "prepareTranslation 失敗：\(error)\n→ 沙盒下載可能不通，Phase 3 需重新評估。"
        }
        do {
            let response = try await session.translate(
                "這是一個測試句子，用來驗證即時翻譯是否在沙盒中可用。")
            return "翻譯成功：\(response.targetText)"
        } catch {
            return "translate 失敗：\(error)"
        }
    }
}
