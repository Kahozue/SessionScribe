import SwiftUI

/// 新項目出現時的輕量確認（spec 第七節第 7 項）：
/// 短暫 accent 高亮後衰減；Reduce Motion 或條件不成立時不閃。
struct FlashOnAppear: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashing = false

    func body(content: Content) -> some View {
        content
            .background(
                Color.accentColor.opacity(flashing ? 0.18 : 0),
                in: RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                guard enabled, !reduceMotion else { return }
                flashing = true
                withAnimation(.easeOut(duration: 0.9).delay(0.15)) { flashing = false }
            }
    }
}

extension View {
    func flashOnAppear(if enabled: Bool, cornerRadius: CGFloat = 6) -> some View {
        modifier(FlashOnAppear(enabled: enabled, cornerRadius: cornerRadius))
    }
}
