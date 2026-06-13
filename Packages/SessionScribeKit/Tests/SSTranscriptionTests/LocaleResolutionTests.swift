import Foundation
import Testing

@testable import SSTranscription

@Suite("AppleSpeechEngine locale 解析")
struct LocaleResolutionTests {

    // SpeechTranscriber 實際支援的形式：帶地區，無裸語言碼。
    private let supported = [
        "en-AU", "en-GB", "en-US", "ja-JP", "zh-CN", "zh-HK", "zh-TW",
    ].map(Locale.init(identifier:))

    @Test("裸 en 解析到慣用地區 en-US（非碰巧第一個 en-AU）")
    func bareEnglishResolvesToUS() {
        let match = AppleSpeechEngine.bestSupported(
            for: Locale(identifier: "en"), from: supported)
        #expect(match?.identifier(.bcp47) == "en-US")
    }

    @Test("裸 ja 解析到 ja-JP")
    func bareJapaneseResolvesToJP() {
        let match = AppleSpeechEngine.bestSupported(
            for: Locale(identifier: "ja"), from: supported)
        #expect(match?.identifier(.bcp47) == "ja-JP")
    }

    @Test("zh-TW 精確相符，不會誤配 zh-CN 或 zh-HK")
    func traditionalChineseExactMatch() {
        let match = AppleSpeechEngine.bestSupported(
            for: Locale(identifier: "zh-TW"), from: supported)
        #expect(match?.identifier(.bcp47) == "zh-TW")
    }

    @Test("有指定地區但不支援則回 nil（不退而求其次跨地區）")
    func unsupportedRegionReturnsNil() {
        let match = AppleSpeechEngine.bestSupported(
            for: Locale(identifier: "en-NZ"), from: supported)
        #expect(match == nil)
    }

    @Test("完全不支援的語言回 nil")
    func unsupportedLanguageReturnsNil() {
        let match = AppleSpeechEngine.bestSupported(
            for: Locale(identifier: "ko"), from: supported)
        #expect(match == nil)
    }
}
