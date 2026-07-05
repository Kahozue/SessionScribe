import SSAudio
import SwiftUI

/// 音量指示：以 rms 推動的水平條，附圖示與輔助說明文字，不單靠顏色傳達。
struct LevelMeterView: View {
    let level: AudioLevel

    /// 對數刻度較貼近聽感：把 -60dB 至 0dB 映射到 0 至 1。
    private var normalized: Double {
        let decibels = max(level.rmsDecibels, -60)
        return Double((decibels + 60) / 60)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(
                            normalized > 0.9
                                ? AnyShapeStyle(Color.red)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.6),
                                            Color.accentColor,
                                        ],
                                        startPoint: .leading, endPoint: .trailing))
                        )
                        .frame(width: geometry.size.width * normalized)
                }
            }
            .frame(width: 72, height: 6)
        }
        .accessibilityElement()
        .accessibilityLabel("輸入音量")
        .accessibilityValue("\(Int(normalized * 100)) %")
    }
}
