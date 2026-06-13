import Foundation

/// 翻譯協調者（規格 1.2 Phase 3）：包住 LiveTranslator，吸收翻譯錯誤使其絕不影響
/// 錄音與轉寫（比照核心可靠性原則 2）。只翻 finalized 段落，逐段以 TranslatedSegment
/// 經 AsyncStream 回傳 UI。
public actor TranslationCoordinator {

    private let translator: any LiveTranslator
    /// prepare 失敗代表整場翻譯不可用，translate 直接短路；
    /// 單段 translate 失敗只記錄，不影響後續段落。
    public private(set) var preparationFailed = false
    public private(set) var lastError: (any Error)?

    private var out: AsyncStream<TranslatedSegment>.Continuation?

    public init(translator: any LiveTranslator) {
        self.translator = translator
    }

    /// UI 訂閱（須在 prepare 前呼叫）。
    public func updates() -> AsyncStream<TranslatedSegment> {
        AsyncStream { out = $0 }
    }

    public func prepare(source: Locale.Language, target: Locale.Language) async {
        do {
            try await translator.prepare(source: source, target: target)
        } catch {
            preparationFailed = true
            lastError = error
        }
    }

    /// 翻譯一段並轉發；失敗則該段不出譯文，後續段落續試。
    public func translate(segmentID: String, text: String) async {
        guard !preparationFailed else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let translated = try await translator.translate(trimmed)
            out?.yield(TranslatedSegment(segmentID: segmentID, text: translated))
        } catch {
            lastError = error
        }
    }

    public func finish() {
        out?.finish()
    }
}
