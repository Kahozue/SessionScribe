import Foundation
import Testing
@testable import SSCore

struct CloudLLMSettingsTests {
    @Test func 預設關閉且引擎為本機() {
        let s = CloudLLMSettings()
        #expect(s.enabled == false)
        #expect(s.engine == .local)
        #expect(s.providers.isEmpty)
        #expect(s.activeProvider == nil)
    }

    @Test func 編碼解碼往返() throws {
        var s = CloudLLMSettings()
        let p = CloudProviderConfig(id: "p1", format: .anthropic, displayName: "Claude",
            baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-6")
        s.providers = [p]
        s.activeProviderID = "p1"
        s.enabled = true
        s.engine = .cloud
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(CloudLLMSettings.self, from: data)
        #expect(back == s)
        #expect(back.activeProvider?.format == .anthropic)
    }

    @Test func 預設供應商樣板齊四家() {
        let defaults = CloudProviderConfig.builtInTemplates
        #expect(defaults.map(\.displayName).contains("OpenAI"))
        #expect(defaults.map(\.displayName).contains("DeepSeek"))
        #expect(defaults.map(\.displayName).contains("Anthropic"))
        #expect(defaults.map(\.displayName).contains("Gemini"))
    }
}
