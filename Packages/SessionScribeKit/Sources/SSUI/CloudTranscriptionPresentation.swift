import Foundation
import SSCore

enum UIErrorMessage {
    static func describe(_ error: Error) -> String {
        if let cloudError = error as? CloudLLMError {
            return cloudError.userMessage
        }
        return error.localizedDescription
    }
}

enum TranscriptionRoutePresentation {
    static func usesCloud(settings: CloudLLMSettings) -> Bool {
        guard settings.enabled,
              settings.engine(for: .offlineTranscript) == .cloud,
              let provider = settings.provider(for: .offlineTranscript),
              provider.format.supportsSTT,
              URL(string: provider.baseURL) != nil else {
            return false
        }
        return true
    }

    static func actionTitle(usesCloud: Bool) -> String {
        usesCloud ? "雲端轉寫這段音訊" : "離線轉寫這段音訊"
    }

    static func importActionTitle(usesCloud: Bool) -> String {
        usesCloud ? "立即雲端轉寫" : "立即離線轉寫"
    }

    static func progressTitle(usesCloud: Bool, progress: Double) -> String {
        let label = usesCloud ? "雲端轉寫中" : "離線轉寫中"
        return "\(label) \(Int(progress * 100))%"
    }

    static func completionTitle(usesCloud: Bool) -> String {
        usesCloud ? "雲端轉寫完成" : "離線轉寫完成"
    }

    static func failureTitle(usesCloud: Bool) -> String {
        usesCloud ? "雲端轉寫失敗" : "離線轉寫失敗"
    }
}

enum CloudAssistPresentation {
    static func usesCloud(settings: CloudLLMSettings, feature: AssistFeature) -> Bool {
        guard feature.capability == .text,
              settings.enabled,
              settings.engine(for: feature) == .cloud,
              let provider = settings.provider(for: feature),
              URL(string: provider.baseURL) != nil else {
            return false
        }
        return true
    }
}
