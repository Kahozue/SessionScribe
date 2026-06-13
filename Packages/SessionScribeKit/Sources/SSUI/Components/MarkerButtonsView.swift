import SSCore
import SwiftUI

/// 模板四鍵標記按鈕：2×2 格對應當前場次模板的前四個 markerType，
/// 以位置對應 Cmd+1 至 4。論文口試模板額外顯示 Q/R/S/A 字母助記，
/// 其餘模板只顯示 Cmd 編號。單鍵 Q/R/S/A 的焦點規則由逐字稿區的
/// onKeyPress 處理（僅論文口試生效）。
public struct MarkerButtonsView: View {
    let markerTypes: [MarkerType]
    let showLetterHints: Bool
    let isEnabled: Bool
    let onMark: (MarkerType) -> Void

    public init(
        markerTypes: [MarkerType],
        showLetterHints: Bool,
        isEnabled: Bool,
        onMark: @escaping (MarkerType) -> Void
    ) {
        self.markerTypes = markerTypes
        self.showLetterHints = showLetterHints
        self.isEnabled = isEnabled
        self.onMark = onMark
    }

    private static let letters = ["Q", "R", "S", "A"]
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

    @ViewBuilder
    private func markerButton(_ index: Int) -> some View {
        if index < markerTypes.count {
            let type = markerTypes[index]
            Button {
                onMark(type)
            } label: {
                VStack(spacing: 2) {
                    Text(type.label)
                        .font(.headline)
                    Text(hint(index))
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

    private func hint(_ index: Int) -> String {
        showLetterHints ? "\(Self.letters[index]) ⌘\(index + 1)" : "⌘\(index + 1)"
    }
}
