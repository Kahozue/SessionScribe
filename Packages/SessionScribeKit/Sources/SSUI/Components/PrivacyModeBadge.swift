import SSCore
import SwiftUI

/// 非 Local Only 時顯示的精簡狀態標；Local Only 不顯示（回傳 EmptyView）。
struct PrivacyModeBadge: View {
    let mode: PrivacyMode

    var body: some View {
        if mode != .localOnly {
            Label(label, systemImage: "cloud")
                .appFont(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.yellow.opacity(0.18), in: Capsule())
                .foregroundStyle(.secondary)
                .help("此 session 啟用雲端整理，文字會送往雲端供應商。")
        }
    }

    private var label: String {
        switch mode {
        case .localOnly: ""
        case .textCloudAssist: "雲端整理"
        case .audioCloudASR: "雲端 ASR"
        }
    }
}
