import SSCore
import SwiftUI

/// 四個大標記按鈕：Q 問題、R 必改、S 建議、A 重要回答。
/// 大按鈕永遠可點（錄音中），Cmd+1 至 4 為全域快捷；單鍵 Q/R/S/A
/// 的焦點規則由逐字稿區的 onKeyPress 處理。
public struct MarkerButtonsView: View {
    let isEnabled: Bool
    let onMark: (MarkerType) -> Void

    public init(isEnabled: Bool, onMark: @escaping (MarkerType) -> Void) {
        self.isEnabled = isEnabled
        self.onMark = onMark
    }

    private static let hints = ["Q ⌘1", "R ⌘2", "S ⌘3", "A ⌘4"]
    private static let shortcuts: [KeyEquivalent] = ["1", "2", "3", "4"]

    public var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                markerButton(0)
                markerButton(1)
            }
            GridRow {
                markerButton(2)
                markerButton(3)
            }
        }
    }

    private func markerButton(_ index: Int) -> some View {
        let type = MarkerType.defaults[index]
        return Button {
            onMark(type)
        } label: {
            VStack(spacing: 2) {
                Text(type.label)
                    .font(.headline)
                Text(Self.hints[index])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(Self.shortcuts[index], modifiers: .command)
        .disabled(!isEnabled)
        .accessibilityLabel("標記\(type.label)")
    }
}
