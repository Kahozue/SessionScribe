import AVFoundation

/// 離線轉寫：依 manifest 順序讀取既有 chunk，以正確的媒體時間餵入
/// TranscriptionCoordinator。匯入音檔與重轉寫共用此路徑，
/// 與即時錄音走同一套引擎抽象。
public enum OfflineTranscriber {

    public enum TranscribeError: Error {
        case missingManifest
    }

    public static func transcribe(
        sessionDirectory: URL,
        session: Session,
        coordinator: TranscriptionCoordinator,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let audioDirectory = sessionDirectory.appending(path: SessionFiles.audioDirectory)
        guard let manifest = try AudioManifestFile.readIfPresent(from: audioDirectory) else {
            throw TranscribeError.missingManifest
        }
        try await coordinator.start(
            sessionID: session.sessionID, locale: Locale(identifier: session.locale))

        let totalSeconds = manifest.totalDurationSeconds
        for chunk in manifest.chunks {
            let file = try AVAudioFile(
                forReading: audioDirectory.appending(path: chunk.file))
            let format = file.processingFormat
            var framesRead: AVAudioFramePosition = 0
            while file.framePosition < file.length {
                guard
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536)
                else { break }
                try file.read(into: buffer)
                if buffer.frameLength == 0 { break }
                let startSeconds =
                    chunk.startSeconds + Double(framesRead) / format.sampleRate
                framesRead += AVAudioFramePosition(buffer.frameLength)
                await coordinator.feed(
                    AudioSlice(buffer: buffer, startSeconds: startSeconds))
                if totalSeconds > 0 {
                    progress?(
                        min((chunk.startSeconds + Double(framesRead) / format.sampleRate)
                            / totalSeconds, 1))
                }
            }
        }
        await coordinator.finish()
    }
}
