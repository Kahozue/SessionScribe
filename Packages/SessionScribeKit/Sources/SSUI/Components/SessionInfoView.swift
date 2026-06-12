import SSCore
import SwiftUI

/// session 詳細資訊（兩層概念的第二層）：列表只顯示標題，
/// id、時間、引擎等細節由右鍵「詳細資訊」進入這裡看。
struct SessionInfoView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.title)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Session ID", session.sessionID)
                row("來源", session.source == .imported ? "匯入" : "錄音")
                row("建立時間", Self.format(session.createdAt))
                row("開始錄音", session.startedAt.map(Self.format) ?? "未開始")
                row("結束時間", session.endedAt.map(Self.format) ?? "未結束")
                row("語言", session.locale)
                row("轉寫引擎", session.asrEngine.isEmpty ? "無（純錄音）" : session.asrEngine)
                row("輸入來源", session.audioInput)
                row("隱私模式", session.privacyMode == .localOnly ? "本機模式" : session.privacyMode.rawValue)
                row("曾崩潰恢復", session.recovered ? "是" : "否")
                row("App 版本", session.appVersion)
            }
            if !session.notes.isEmpty {
                Text("備註：\(session.notes)")
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private static func format(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month().day().hour().minute().second()
                .locale(Locale(identifier: "zh_TW")))
    }
}
