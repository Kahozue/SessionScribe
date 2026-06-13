import AVFoundation
import Foundation

/// 將 session 的 CAF chunks 依 manifest 順序串接匯出為單一 .m4a（AAC，v0.2）。
/// 不破壞原始 chunk；用 AVMutableComposition 串接後以 AppleM4A preset 轉檔。
public enum AudioExporter {

    public enum ExportError: Error {
        case missingManifest
        case emptyAudio
        case noAudioTrack
        case exportFailed
    }

    public static func exportM4A(audioDirectory: URL, to destination: URL) async throws {
        guard let manifest = try AudioManifestFile.readIfPresent(from: audioDirectory) else {
            throw ExportError.missingManifest
        }
        guard !manifest.chunks.isEmpty else { throw ExportError.emptyAudio }

        let composition = AVMutableComposition()
        guard
            let track = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.noAudioTrack }

        var cursor = CMTime.zero
        for chunk in manifest.chunks {
            let url = audioDirectory.appending(path: chunk.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVURLAsset(url: url)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceTrack = audioTracks.first else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: cursor)
            cursor = cursor + duration
        }

        guard
            let session = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetAppleM4A)
        else { throw ExportError.exportFailed }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try await session.export(to: destination, as: .m4a)
    }
}
