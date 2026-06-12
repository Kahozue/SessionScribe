import AVFoundation
import Accelerate

/// 一次音量量測結果。線性值域 0 至 1，分貝為 dBFS。
public struct AudioLevel: Equatable, Sendable {
    public static let decibelFloor: Float = -120

    public let rms: Float
    public let peak: Float

    public init(rms: Float, peak: Float) {
        self.rms = rms
        self.peak = peak
    }

    public var rmsDecibels: Float {
        guard rms > 0 else { return Self.decibelFloor }
        return max(20 * log10(rms), Self.decibelFloor)
    }

    public static let silent = AudioLevel(rms: 0, peak: 0)
}

/// 從 PCM buffer 計算音量。多聲道取各聲道最大值。
public enum AudioLevelMeter {

    public static func level(of buffer: AVAudioPCMBuffer) -> AudioLevel {
        let frameCount = vDSP_Length(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else {
            return .silent
        }
        var maxRMS: Float = 0
        var maxPeak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            var rms: Float = 0
            var peak: Float = 0
            vDSP_rmsqv(channelData[channel], 1, &rms, frameCount)
            vDSP_maxmgv(channelData[channel], 1, &peak, frameCount)
            maxRMS = max(maxRMS, rms)
            maxPeak = max(maxPeak, peak)
        }
        return AudioLevel(rms: maxRMS, peak: maxPeak)
    }
}
