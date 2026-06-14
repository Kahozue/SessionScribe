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

        let keychain = ReadCountingKeychainStore()
        #expect(TranscriptionRoutePresentation.usesCloud(settings: settings))
        #expect(keychain.secretReadCount == 0)
        #expect(TranscriptionRoutePresentation.actionTitle(usesCloud: true) == "雲端轉寫這段音訊")
        #expect(TranscriptionRoutePresentation.progressTitle(usesCloud: true, progress: 0.42) == "雲端轉寫中 42%")
    }

    @Test func 雲端錯誤顯示使用者訊息而非Swift錯誤代碼() {
        let message = UIErrorMessage.describe(CloudLLMError.http(status: 401, body: ""))
        #expect(message == "API key 無效或未授權（401）。")
    }
}

private final class ReadCountingKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0

    var secretReadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }

    func secret(account _: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        return nil
    }

    func setSecret(_: String, account _: String) throws {}
    func deleteSecret(account _: String) throws {}
}
