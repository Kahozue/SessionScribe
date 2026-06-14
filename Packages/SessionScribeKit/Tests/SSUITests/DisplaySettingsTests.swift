import Foundation
import SSCore
import Testing

@testable import SSUI

@Suite("DisplaySettings")
struct DisplaySettingsTests {

    @Test("字級設定縮放語意 UI 字體，不只逐字稿正文")
    func fontSizeScalesSemanticUIStyles() {
        #expect(
            DisplaySettings.scaledFontSize(
                for: .callout,
                baseFontSize: DisplaySettings.defaultFontSize
            ) == DisplaySettings.defaultFontSize
        )

        let defaultCaption = DisplaySettings.scaledFontSize(
            for: .caption,
            baseFontSize: DisplaySettings.defaultFontSize)
        let largerCaption = DisplaySettings.scaledFontSize(
            for: .caption,
            baseFontSize: DisplaySettings.fontSizeRange.upperBound)

        #expect(largerCaption > defaultCaption)
        #expect(
            DisplaySettings.scaledFontSize(for: .headline, baseFontSize: 20)
                > DisplaySettings.scaledFontSize(for: .callout, baseFontSize: 20)
        )
    }

    @Test("逐字稿摘要不顯示需複查標籤")
    func summaryDoesNotShowReviewBadge() {
        let summary = TranscriptSummary(
            summaryID: "sum_0001",
            sessionID: "s1",
            content: "摘要內容",
            needsReview: true,
            sourceSegmentIDs: ["seg_1"],
            createdAt: Date(timeIntervalSince1970: 0))

        #expect(!SummaryBadgePolicy.showsReviewBadge(for: summary))
    }

    @Test("右欄卡片內文使用一致可讀字級")
    func inspectorCardsUseConsistentReadableBodyStyles() {
        #expect(InspectorCardTypography.summaryBody == .callout)
        #expect(InspectorCardTypography.summarySubheading == .callout)
        #expect(InspectorCardTypography.summaryListItem == .callout)
        #expect(InspectorCardTypography.summarySource == .callout)

        #expect(InspectorCardTypography.eventMetadata == .callout)
        #expect(InspectorCardTypography.eventContent == .callout)
        #expect(InspectorCardTypography.eventSource == .callout)
    }

    @Test("雲端字幕翻譯會標記文字雲端隱私模式")
    func cloudTranslationMarksTextCloudPrivacy() {
        #expect(RecordingPrivacyPolicy.modeAfterCloudTranslation(.localOnly) == .textCloudAssist)
        #expect(RecordingPrivacyPolicy.modeAfterCloudTranslation(.audioCloudASR) == .textAndAudioCloud)
    }
}
