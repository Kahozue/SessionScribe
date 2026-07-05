import SwiftUI

/// 可互動卡片的 hover 回饋（spec 第七節第 4、7 項）：輕微提亮。
/// 非動畫狀態切換，Reduce Motion 無需降級。只給可點擊的卡片使用。
struct CardHoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(
                .primary.opacity(hovered ? 0.05 : 0),
                in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovered = $0 }
    }
}

extension View {
    func cardHoverHighlight(cornerRadius: CGFloat = 8) -> some View {
        modifier(CardHoverHighlight(cornerRadius: cornerRadius))
    }
}
