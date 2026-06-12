import AVFoundation
import SSCore

/// 匯入音檔（規格 1.1 第 6 項）：解碼來源音檔，轉成 canonical PCM CAF chunks
/// 與 manifest，建立 `source: imported` 的 session。轉寫是可選的後續步驟
/// （OfflineTranscriber），與匯入解耦。
public enum AudioImporter {

    /// 開啟面板的副檔名清單；實際可讀性以 AVAudioFile 為準。
    public static let supportedExtensions = ["caf", "wav", "m4a", "mp3", "aiff", "aifc"]

    public enum ImportError: Error {
        case emptyFile
    }

    @discardableResult
    public static func importFile(
        at url: URL,
        into root: URL,
        title: String? = nil,
        chunkDuration: TimeInterval = AudioDefaults.chunkDuration,
        appVersion: String = "0.1.0"
    ) async throws -> Session {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw ImportError.emptyFile }

        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var session = Session(
            sessionID: Session.makeID(),
            title: title ?? url.deletingPathExtension().lastPathComponent,
            templateID: "imported",
            createdAt: now,
            locale: "zh-TW",
            audioInput: url.lastPathComponent,
            appVersion: appVersion,
            source: .imported
        )
        session.startedAt = now

        let store = try await SessionStore.create(session, in: root)
        do {
            let format = file.processingFormat
            let writer = ChunkedAudioWriter(
                audioDirectory: store.directory.appending(path: SessionFiles.audioDirectory),
                format: format,
                chunkDuration: chunkDuration)
            // 讀取量對齊 chunk 邊界：writer 的 buffer 不跨檔切割，
            // 對齊後匯入產出的 chunk 長度與設定值精確一致。
            let chunkFrames = AVAudioFramePosition(chunkDuration * format.sampleRate)
            let maxReadFrames: AVAudioFramePosition = 65536
            var remainingInChunk = chunkFrames
            while file.framePosition < file.length {
                let capacity = AVAudioFrameCount(min(maxReadFrames, remainingInChunk))
                guard
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
                else { throw ImportError.emptyFile }
                try file.read(into: buffer)
                if buffer.frameLength == 0 { break }
                remainingInChunk -= AVAudioFramePosition(buffer.frameLength)
                if remainingInChunk <= 0 {
                    remainingInChunk = chunkFrames
                }
                try await writer.write(buffer)
            }
            _ = try await writer.finish()

            // 匯入即完成：endedAt 必須落盤，否則會被恢復掃描誤判為崩潰殘留。
            session.endedAt = Date(
                timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
            try await store.saveMetadata(session)
            return session
        } catch {
            // 匯入中途失敗：清掉半成品資料夾，不留殘渣。
            try? FileManager.default.removeItem(at: store.directory)
            throw error
        }
    }
}
