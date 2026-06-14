import Foundation
import SSCore
import Testing

@testable import SSUI

struct CloudTranscriptionPresentationTests {
    @Test func 轉寫按鈕文案依實際雲端STT可用性切換() throws {
        var settings = CloudLLMSettings(enabled: true)
        settings.providers = [
            CloudProviderConfig(
                id: "audio", format: .openAICompatible, displayName: "OpenAI",
                baseURL: "https://api.openai.com/v1", model: "gpt-4o-transcribe-diarize")
        ]
        settings.audioProviderID = "audio"
        settings.setEngine(.cloud, for: .offlineTranscript)

        let keychain = InMemoryKeychainStore()
        try keychain.setSecret("sk-test", account: "audio")

        #expect(TranscriptionRoutePresentation.usesCloud(settings: settings, keychain: keychain))
        #expect(TranscriptionRoutePresentation.actionTitle(usesCloud: true) == "雲端轉寫這段音訊")
        #expect(TranscriptionRoutePresentation.progressTitle(usesCloud: true, progress: 0.42) == "雲端轉寫中 42%")
    }

    @Test func 雲端錯誤顯示使用者訊息而非Swift錯誤代碼() {
        let message = UIErrorMessage.describe(CloudLLMError.http(status: 401, body: ""))
        #expect(message == "API key 無效或未授權（401）。")
    }
}
