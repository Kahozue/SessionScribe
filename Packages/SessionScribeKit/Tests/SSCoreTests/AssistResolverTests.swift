import Foundation
import Testing
@testable import SSCore

struct AssistResolverTests {
    private func settings(textCloud: Bool = true) -> CloudLLMSettings {
        var s = CloudLLMSettings()
        s.providers = [CloudProviderConfig(id: "p1", format: .openAICompatible,
            displayName: "X", baseURL: "https://api.example.com/v1", model: "m")]
        s.textProviderID = "p1"
        s.enabled = true
        if textCloud { s.setEngine(.cloud, for: .summary); s.setEngine(.cloud, for: .events) }
        return s
    }

    @Test func 功能雲端且key齊_回雲端() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setSecret("sk", account: "p1")
        #expect(AssistResolver.eventOrganizer(settings: settings(), keychain: keychain) is CloudEventOrganizer)
        #expect(AssistResolver.summarizer(settings: settings(), keychain: keychain) is CloudTranscriptSummarizer)
    }

    @Test func 總開關關_強制本機() throws {
        var s = settings(); s.enabled = false
        let keychain = InMemoryKeychainStore(); try keychain.setSecret("sk", account: "p1")
        #expect(AssistResolver.eventOrganizer(settings: s, keychain: keychain) is LocalEventOrganizer)
    }

    @Test func 該功能本機_強制本機() throws {
        var s = settings(); s.setEngine(.local, for: .events)
        let keychain = InMemoryKeychainStore(); try keychain.setSecret("sk", account: "p1")
        #expect(AssistResolver.eventOrganizer(settings: s, keychain: keychain) is LocalEventOrganizer)
    }

    @Test func 缺key_退回本機() throws {
        #expect(AssistResolver.eventOrganizer(settings: settings(), keychain: InMemoryKeychainStore()) is LocalEventOrganizer)
    }

    @Test func translation功能client解析() throws {
        var s = settings(textCloud: false); s.setEngine(.cloud, for: .translation)
        let keychain = InMemoryKeychainStore(); try keychain.setSecret("sk", account: "p1")
        #expect(AssistResolver.client(settings: s, keychain: keychain, feature: .translation) != nil)
        #expect(AssistResolver.client(settings: s, keychain: keychain, feature: .summary) == nil)
    }

    @Test func sttClient需STT供應商與雲端() throws {
        var s = settings(textCloud: false)
        s.providers = [CloudProviderConfig(id: "a", format: .openAICompatible,
            displayName: "A", baseURL: "https://api.example.com/v1", model: "whisper-1")]
        s.audioProviderID = "a"
        s.setEngine(.cloud, for: .offlineTranscript)
        let keychain = InMemoryKeychainStore(); try keychain.setSecret("sk", account: "a")
        #expect(AssistResolver.sttClient(settings: s, keychain: keychain) != nil)

        var anth = s
        anth.providers = [CloudProviderConfig(id: "a", format: .anthropic,
            displayName: "A", baseURL: "https://x", model: "m")]
        #expect(AssistResolver.sttClient(settings: anth, keychain: keychain) == nil)
    }
}
