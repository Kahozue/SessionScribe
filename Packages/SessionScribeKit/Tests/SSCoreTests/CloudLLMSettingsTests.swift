import Foundation
import Testing
@testable import SSCore

struct CloudLLMSettingsTests {
    @Test func 預設關閉且各功能本機() {
        let s = CloudLLMSettings()
        #expect(s.enabled == false)
        #expect(s.providers.isEmpty)
        for f in AssistFeature.allCases { #expect(s.engine(for: f) == .local) }
        #expect(s.textProviderID == nil)
        #expect(s.audioProviderID == nil)
    }

    @Test func 編碼解碼往返() throws {
        var s = CloudLLMSettings()
        s.providers = [CloudProviderConfig(id: "p1", format: .anthropic, displayName: "Claude",
            baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-6")]
        s.enabled = true
        s.setEngine(.cloud, for: .summary)
        s.textProviderID = "p1"
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(CloudLLMSettings.self, from: data)
        #expect(back == s)
        #expect(back.engine(for: .summary) == .cloud)
        #expect(back.engine(for: .events) == .local)
    }

    @Test func 舊格式遷移到per_feature() throws {
        let legacy = """
        {"enabled":true,"engine":"cloud","activeProviderID":"p1",
         "providers":[{"id":"p1","format":"openai_compatible","displayName":"X",
         "baseURL":"https://api.example.com/v1","model":"m"}]}
        """
        let s = try JSONDecoder().decode(CloudLLMSettings.self, from: Data(legacy.utf8))
        #expect(s.enabled)
        #expect(s.engine(for: .summary) == .cloud)
        #expect(s.engine(for: .events) == .cloud)
        #expect(s.engine(for: .translation) == .local)
        #expect(s.engine(for: .offlineTranscript) == .local)
        #expect(s.engine(for: .liveASR) == .local)
        #expect(s.textProviderID == "p1")
        #expect(s.audioProviderID == nil)
    }

    @Test func provider依capability取槽() {
        var s = CloudLLMSettings()
        let text = CloudProviderConfig(id: "t", format: .anthropic, displayName: "T",
            baseURL: "https://a", model: "m")
        let audio = CloudProviderConfig(id: "a", format: .openAICompatible, displayName: "A",
            baseURL: "https://b", model: "whisper-1")
        s.providers = [text, audio]
        s.textProviderID = "t"; s.audioProviderID = "a"
        #expect(s.provider(for: .summary)?.id == "t")
        #expect(s.provider(for: .offlineTranscript)?.id == "a")
    }

    @Test func anyFeatureCloud() {
        var s = CloudLLMSettings(); s.enabled = true
        #expect(s.anyFeatureCloud == false)
        s.setEngine(.cloud, for: .events)
        #expect(s.anyFeatureCloud)
    }

    @Test func 預設供應商樣板齊四家() {
        let defaults = CloudProviderConfig.builtInTemplates
        #expect(defaults.map(\.displayName).contains("OpenAI"))
        #expect(defaults.map(\.displayName).contains("DeepSeek"))
        #expect(defaults.map(\.displayName).contains("Anthropic"))
        #expect(defaults.map(\.displayName).contains("Gemini"))
    }

    @Test func 語音供應商樣板只列可直接STT的預設值() {
        let defaults = CloudProviderConfig.builtInAudioTemplates
        #expect(defaults.map(\.displayName) == ["OpenAI", "Gemini"])
        #expect(defaults.first { $0.displayName == "OpenAI" }?.model == "gpt-4o-transcribe-diarize")
        #expect(defaults.allSatisfy { $0.format.supportsSTT })
    }

    @Test func feature能力分類正確() {
        #expect(AssistFeature.offlineTranscript.capability == .audio)
        #expect(AssistFeature.liveASR.capability == .audio)
        #expect(AssistFeature.summary.capability == .text)
        #expect(AssistFeature.events.capability == .text)
        #expect(AssistFeature.translation.capability == .text)
    }

    @Test func 供應商STT能力() {
        #expect(CloudProviderFormat.openAICompatible.supportsSTT)
        #expect(CloudProviderFormat.gemini.supportsSTT)
        #expect(CloudProviderFormat.anthropic.supportsSTT == false)
    }
}
