import Foundation
import Testing
@testable import SSCore

struct AssistResolverTests {
    private func cloudSettings() -> CloudLLMSettings {
        var s = CloudLLMSettings()
        s.providers = [CloudProviderConfig(id: "p1", format: .openAICompatible,
            displayName: "X", baseURL: "https://api.example.com/v1", model: "m")]
        s.activeProviderID = "p1"
        s.enabled = true
        s.engine = .cloud
        return s
    }

    @Test func 引擎雲端且key齊_回雲端() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setSecret("sk", account: "p1")
        let organizer = AssistResolver.eventOrganizer(settings: cloudSettings(), keychain: keychain)
        #expect(organizer is CloudEventOrganizer)
    }

    @Test func 總開關關_強制本機() throws {
        var s = cloudSettings(); s.enabled = false
        let organizer = AssistResolver.eventOrganizer(settings: s, keychain: InMemoryKeychainStore())
        #expect(organizer is LocalEventOrganizer)
    }

    @Test func 引擎本機_強制本機() throws {
        var s = cloudSettings(); s.engine = .local
        let organizer = AssistResolver.eventOrganizer(settings: s, keychain: InMemoryKeychainStore())
        #expect(organizer is LocalEventOrganizer)
    }

    @Test func 缺key_退回本機() throws {
        let organizer = AssistResolver.eventOrganizer(
            settings: cloudSettings(), keychain: InMemoryKeychainStore())
        #expect(organizer is LocalEventOrganizer)
    }

    @Test func 摘要器同樣路由() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setSecret("sk", account: "p1")
        #expect(AssistResolver.summarizer(settings: cloudSettings(), keychain: keychain) is CloudTranscriptSummarizer)
        #expect(AssistResolver.summarizer(settings: CloudLLMSettings(), keychain: keychain) is LocalTranscriptSummarizer)
    }
}
