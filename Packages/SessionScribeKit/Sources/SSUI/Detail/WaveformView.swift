import SSCore
import SwiftUI

/// 播放列波形：Canvas 繪 bins，已播放區段 accent 色，markers 依色票疊短線。
/// 點擊與拖曳 seek；聚焦後左右方向鍵微調 5 秒；VoiceOver 可調整。
struct WaveformView: View {
    let waveform: Waveform
    let currentSeconds: Double
    let totalSeconds: Double
    let markers: [Marker]
    let template: SessionTemplate
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawBars(context: &context, size: size)
                drawMarkers(context: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seek(atX: value.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: 44)
        .focusable()
        .onKeyPress(.leftArrow) {
            onSeek(max(0, currentSeconds - 5))
            return .handled
        }
        .onKeyPress(.rightArrow) {
            onSeek(min(totalSeconds, currentSeconds + 5))
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel("播放位置")
        .accessibilityValue(
            "\(TimeFormatting.hms(currentSeconds))，總長 \(TimeFormatting.hms(totalSeconds))"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(totalSeconds, currentSeconds + 5))
            case .decrement: onSeek(max(0, currentSeconds - 5))
            @unknown default: break
            }
        }
        .help("點擊或拖曳跳轉播放位置")
    }

    private func seek(atX x: CGFloat, width: CGFloat) {
        guard width > 0, totalSeconds > 0 else { return }
        let fraction = min(1, max(0, x / width))
        onSeek(Double(fraction) * totalSeconds)
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        let count = waveform.rms.count
        guard count > 0, totalSeconds > 0 else { return }
        let barWidth = size.width / CGFloat(count)
        let playedX = CGFloat(currentSeconds / totalSeconds) * size.width
        for index in 0..<count {
            let x = CGFloat(index) * barWidth
            let amplitude = max(0.06, CGFloat(min(1, waveform.rms[index] * 1.6)))
            let height = amplitude * size.height
            let bar = CGRect(
                x: x, y: (size.height - height) / 2,
                width: max(1, barWidth - 1), height: height)
            let color: Color = x <= playedX ? .accentColor : Color.secondary.opacity(0.35)
            context.fill(
                Path(roundedRect: bar, cornerRadius: min(barWidth / 3, 2)),
                with: .color(color))
        }
    }

    private func drawMarkers(context: inout GraphicsContext, size: CGSize) {
        guard totalSeconds > 0 else { return }
        for marker in markers {
            let x = CGFloat(marker.mediaSeconds / totalSeconds) * size.width
            let style = MarkerVisualStyle.style(for: marker, template: template)
            let line = CGRect(x: x - 0.75, y: 0, width: 1.5, height: size.height)
            context.fill(Path(line), with: .color(style.tint))
        }
    }
}
