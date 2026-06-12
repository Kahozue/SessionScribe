import Foundation
import SSCore

/// 引擎降級鏈（規格書第五節）：依序檢查可用性，挑第一個非 unsupported 的引擎；
/// 全部不可用回傳 nil，進入純錄音模式。requiresDownload 視為可用，
/// 由 prepare 階段的 AssetInventory 下載引導處理。
public enum EngineSelector {

    public static func select(
        from engines: [any TranscriptionEngine],
        locale: Locale
    ) async -> (any TranscriptionEngine)? {
        for engine in engines {
            if await engine.availability(for: locale) != .unsupported {
                return engine
            }
        }
        return nil
    }

    /// 挑選並完成 prepare（含模型下載）；prepare 失敗時降級到下一個引擎。
    public static func selectAndPrepare(
        from engines: [any TranscriptionEngine],
        locale: Locale
    ) async -> (any TranscriptionEngine)? {
        for engine in engines {
            guard await engine.availability(for: locale) != .unsupported else { continue }
            do {
                try await engine.prepare(locale: locale)
                return engine
            } catch {
                continue
            }
        }
        return nil
    }

    /// v0.1 的標準降級鏈。
    public static func defaultChain(useMock: Bool = false) -> [any TranscriptionEngine] {
        if useMock {
            return [MockTranscriptionEngine()]
        }
        return [AppleSpeechEngine(), LegacySFSpeechEngine()]
    }
}
