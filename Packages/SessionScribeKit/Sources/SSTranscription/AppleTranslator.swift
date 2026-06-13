import Foundation
import SSCore
@preconcurrency import Translation

/// 即時翻譯主引擎（規格 1.2 Phase 3）：macOS 26 Translation framework，
/// direct init + lowLatency 策略（on-device、需先下載語言模型）。
/// TranslationSession 非 Sendable 且偏主執行緒，整個 translator 隔離在 main actor。
@available(macOS 26.4, *)
@MainActor
public final class AppleTranslator: LiveTranslator {

    public enum TranslatorError: Error {
        case notPrepared
    }

    private var session: TranslationSession?

    public init() {}

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        let session = TranslationSession(
            installedSource: source, target: target, preferredStrategy: .lowLatency)
        // 模型未安裝時於此下載；完成後本場翻譯就緒。
        try await session.prepareTranslation()
        self.session = session
    }

    public func translate(_ text: String) async throws -> String {
        guard let session else { throw TranslatorError.notPrepared }
        return try await session.translate(text).targetText
    }
}
