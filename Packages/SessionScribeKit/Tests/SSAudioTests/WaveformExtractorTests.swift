import AVFoundation
import Foundation
import Testing
@testable import SSAudio
import SSCore

private let waveTestFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

private func makeWaveDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "WaveformExtractorTests-\(UUID().uuidString)")
        .appending(path: "audio")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeSineBuffer(frames: Int, amplitude: Float) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(
        pcmFormat: waveTestFormat, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let data = buffer.floatChannelData![0]
    for i in 0..<frames {
        data[i] = amplitude * sin(2 * .pi * 440 * Float(i) / 48000)
    }
    return buffer
}

private func makeSilentBuffer(frames: Int) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(
        pcmFormat: waveTestFormat, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    return buffer
}

@Suite("WaveformExtractor")
struct WaveformExtractorTests {

    @Test("正弦波振幅 0.5：rms 約 0.354、peak 約 0.5")
    func sineAmplitudes() async throws {
        let directory = try makeWaveDirectory()
        let writer = ChunkedAudioWriter(
            audioDirectory: directory, format: waveTestFormat, chunkDuration: 1.0)
        try await writer.write(makeSineBuffer(frames: 96000, amplitude: 0.5))
        _ = try await writer.finish()

        let waveform = try WaveformExtractor.extract(audioDirectory: directory)
        #expect(waveform.rms.count == Waveform.binCount(forDuration: waveform.durationSeconds))
        let midRMS = waveform.rms[waveform.rms.count / 2]
        let midPeak = waveform.peak[waveform.peak.count / 2]
        #expect(abs(midRMS - 0.3536) < 0.02)
        #expect(abs(midPeak - 0.5) < 0.02)
    }

    @Test("跨 chunk：總長與 bins 連續，靜音段近零")
    func crossChunkContinuity() async throws {
        let directory = try makeWaveDirectory()
        let writer = ChunkedAudioWriter(
            audioDirectory: directory, format: waveTestFormat, chunkDuration: 0.5)
        try await writer.write(makeSineBuffer(frames: 48000, amplitude: 0.5))
        try await writer.write(makeSilentBuffer(frames: 48000))
        _ = try await writer.finish()

        let waveform = try WaveformExtractor.extract(audioDirectory: directory)
        #expect(abs(waveform.durationSeconds - 2.0) < 0.01)
        #expect(waveform.rms.count == 20)
        #expect(waveform.rms[2] > 0.3)
        #expect(waveform.rms[waveform.rms.count - 2] < 0.02)
    }

    @Test("損毀 chunk 跳過：該區段 bins 為零，不拋錯")
    func corruptChunkSkipped() async throws {
        let directory = try makeWaveDirectory()
        let writer = ChunkedAudioWriter(
            audioDirectory: directory, format: waveTestFormat, chunkDuration: 0.5)
        try await writer.write(makeSineBuffer(frames: 48000, amplitude: 0.5))
        try await writer.write(makeSineBuffer(frames: 48000, amplitude: 0.5))
        let manifest = try await writer.finish()
        let firstChunkURL = directory.appending(path: manifest.chunks[0].file)
        try Data(repeating: 0x00, count: 64).write(to: firstChunkURL)

        let waveform = try WaveformExtractor.extract(audioDirectory: directory)
        #expect(waveform.rms[2] == 0)
        #expect(waveform.rms[waveform.rms.count - 2] > 0.3)
    }

    @Test("無 manifest 拋 missingManifest")
    func missingManifest() throws {
        let directory = try makeWaveDirectory()
        #expect(throws: WaveformExtractor.ExtractError.self) {
            try WaveformExtractor.extract(audioDirectory: directory)
        }
    }
}
