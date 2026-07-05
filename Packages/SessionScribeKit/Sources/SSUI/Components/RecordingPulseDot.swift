import SwiftUI

/// 錄音紅點：錄音中輕微呼吸（透明度律動），暫停或 Reduce Motion 時靜態
/// （spec 第七節第 2 項；降級規則見 DESIGN_TOKENS 動效原則）。
struct RecordingPulseDot: View {
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var animated: Bool { !paused && !reduceMotion }

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .opacity(animated && pulsing ? 0.35 : 1)
            .animation(
                animated ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil,
                value: pulsing
            )
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}
