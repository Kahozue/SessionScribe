import AVFoundation
import Foundation
import SSCore

/// 照 manifest 順序離線抽樣 CAF chunks 產生波形 bins（spec 第四節）。
/// 損毀 chunk 跳過、該區段 bins 維持零值，不阻斷整體生成
/// （比照 AudioManifestRecovery 的容錯原則）。
public enum WaveformExtractor {

    public enum ExtractError: Error {
        case missingManifest
        case emptyAudio
    }

    public static func extract(
        audioDirectory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> Waveform {
        guard let manifest = try AudioManifestFile.readIfPresent(from: audioDirectory) else {
            throw ExtractError.missingManifest
        }
        let duration = manifest.totalDurationSeconds
        guard duration > 0, !manifest.chunks.isEmpty else {
            throw ExtractError.emptyAudio
        }
        let binCount = Waveform.binCount(forDuration: duration)
        let binDuration = duration / Double(binCount)
        var sumSquares = [Double](repeating: 0, count: binCount)
        var sampleCounts = [Int](repeating: 0, count: binCount)
        var peaks = [Float](repeating: 0, count: binCount)
        var processedSeconds = 0.0

        for chunk in manifest.chunks {
            defer {
                processedSeconds += chunk.durationSeconds
                progress?(min(1, processedSeconds / duration))
            }
            let url = audioDirectory.appending(path: chunk.file)
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let format = file.processingFormat
            let blockFrames: AVAudioFrameCount = 65536
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: blockFrames) else { continue }
            var chunkFrameOffset = 0.0
            while file.framePosition < file.length {
                do {
                    try file.read(into: buffer, frameCount: blockFrames)
                } catch {
                    break
                }
                let frames = Int(buffer.frameLength)
                guard frames > 0, let channel = buffer.floatChannelData?[0] else { break }
                for i in 0..<frames {
                    let seconds =
                        chunk.startSeconds + (chunkFrameOffset + Double(i)) / format.sampleRate
                    let bin = min(binCount - 1, max(0, Int(seconds / binDuration)))
                    let sample = channel[i]
                    sumSquares[bin] += Double(sample) * Double(sample)
                    sampleCounts[bin] += 1
                    if abs(sample) > peaks[bin] {
                        peaks[bin] = abs(sample)
                    }
                }
                chunkFrameOffset += Double(frames)
            }
        }

        let rms = (0..<binCount).map { index -> Float in
            guard sampleCounts[index] > 0 else { return 0 }
            return Float((sumSquares[index] / Double(sampleCounts[index])).squareRoot())
        }
        return Waveform(durationSeconds: duration, rms: rms, peak: peaks)
    }
}
