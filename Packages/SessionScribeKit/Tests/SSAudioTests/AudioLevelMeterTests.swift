import AVFoundation
import Testing
@testable import SSAudio

/// 產生單聲道 Float32 測試 buffer。
private func makeBuffer(samples: [Float], sampleRate: Double = 48000) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
        buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
    }
    return buffer
}

@Suite("AudioLevelMeter")
struct AudioLevelMeterTests {

    @Test("靜音 buffer 的 rms 與 peak 為零")
    func silenceIsZero() {
        let level = AudioLevelMeter.level(of: makeBuffer(samples: [Float](repeating: 0, count: 480)))
        #expect(level.rms == 0)
        #expect(level.peak == 0)
    }

    @Test("滿刻度直流訊號的 rms 與 peak 為一")
    func fullScaleConstant() {
        let level = AudioLevelMeter.level(of: makeBuffer(samples: [Float](repeating: 1, count: 480)))
        #expect(abs(level.rms - 1.0) < 0.0001)
        #expect(level.peak == 1.0)
    }

    @Test("振幅 0.5 正弦波：peak 約 0.5，rms 約 0.5 除以根號二")
    func halfAmplitudeSine() {
        let samples = (0..<4800).map { index in
            Float(0.5 * sin(2.0 * .pi * 440.0 * Double(index) / 48000.0))
        }
        let level = AudioLevelMeter.level(of: makeBuffer(samples: samples))
        #expect(abs(level.peak - 0.5) < 0.01)
        #expect(abs(level.rms - 0.3536) < 0.01)
    }

    @Test("負值樣本以絕對值計入 peak")
    func peakUsesAbsoluteValue() {
        let level = AudioLevelMeter.level(of: makeBuffer(samples: [0, -0.8, 0.3]))
        #expect(abs(level.peak - 0.8) < 0.0001)
    }

    @Test("空 buffer 回傳零，不除以零")
    func emptyBufferIsZero() {
        let level = AudioLevelMeter.level(of: makeBuffer(samples: []))
        #expect(level.rms == 0)
        #expect(level.peak == 0)
    }

    @Test("靜音的分貝值鉗在地板值，不是負無限")
    func decibelsClampedAtFloor() {
        let level = AudioLevelMeter.level(of: makeBuffer(samples: [Float](repeating: 0, count: 48)))
        #expect(level.rmsDecibels == AudioLevel.decibelFloor)
        #expect(level.rmsDecibels.isFinite)
    }

    @Test("滿刻度的分貝值為零")
    func fullScaleIsZeroDecibels() {
        let level = AudioLevelMeter.level(of: makeBuffer(samples: [Float](repeating: 1, count: 48)))
        #expect(abs(level.rmsDecibels) < 0.001)
    }
}
