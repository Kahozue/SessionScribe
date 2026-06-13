import Foundation
import SSCore

/// 測試用翻譯引擎：可注入 prepare 失敗、特定文字 translate 失敗，
/// 預設把譯文標上前綴以驗證對應關係。
public final class MockTranslator: LiveTranslator, @unchecked Sendable {

    public enum MockError: Error {
        case prepareFailed
        case translateFailed
    }

    private let failPrepare: Bool
    private let failTranslateContaining: [String]
    private let transform: @Sendable (String) -> String

    public init(
        failPrepare: Bool = false,
        failTranslateContaining: [String] = [],
        transform: @escaping @Sendable (String) -> String = { "譯：" + $0 }
    ) {
        self.failPrepare = failPrepare
        self.failTranslateContaining = failTranslateContaining
        self.transform = transform
    }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        if failPrepare { throw MockError.prepareFailed }
    }

    public func translate(_ text: String) async throws -> String {
        if failTranslateContaining.contains(where: text.contains) {
            throw MockError.translateFailed
        }
        return transform(text)
    }
}
