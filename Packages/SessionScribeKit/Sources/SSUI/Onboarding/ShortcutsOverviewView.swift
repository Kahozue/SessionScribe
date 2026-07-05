import SwiftUI

/// 鍵盤快捷鍵總覽（spec 第六節）：「說明」選單開啟，列出全部快捷鍵，
/// 單鍵標記的焦點規則一併說明。
public struct ShortcutsOverviewView: View {

    public init() {}

    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    private let recording: [Shortcut] = [
        Shortcut(keys: "Q / R / S / A", action: "建立四鍵標記（論文口試模板；逐字稿區聚焦時）"),
        Shortcut(keys: "Cmd+1 至 Cmd+4", action: "建立四鍵標記（依當前模板，任何聚焦位置）"),
    ]

    private let playback: [Shortcut] = [
        Shortcut(keys: "左 / 右方向鍵", action: "播放位置往前／往後 5 秒（波形聚焦時）"),
        Shortcut(keys: "空白鍵", action: "播放／暫停（系統列表焦點行為）"),
    ]

    private let general: [Shortcut] = [
        Shortcut(keys: "Cmd+,", action: "開啟設定"),
        Shortcut(keys: "Return", action: "確認目前的 sheet 動作（匯出、分類等）"),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("錄音與標記", shortcuts: recording)
            Text("單鍵 Q/R/S/A 只在逐字稿區持有鍵盤焦點時生效，避免與輸入框衝突；Cmd 快捷鍵不受焦點限制。")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            section("播放", shortcuts: playback)
            section("一般", shortcuts: general)
        }
        .padding(20)
        .frame(width: 440)
        .appTypography()
    }

    private func section(_ title: String, shortcuts: [Shortcut]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.headline)
            ForEach(shortcuts) { shortcut in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(shortcut.keys)
                        .appFont(.callout, monospacedDigit: true)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .frame(minWidth: 130, alignment: .leading)
                    Text(shortcut.action)
                        .appFont(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
