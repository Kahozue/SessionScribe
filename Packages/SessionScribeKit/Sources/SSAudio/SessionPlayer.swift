import AVFoundation
import Observation
import SSCore

/// session 音訊播放：依 manifest 串接 chunk 順播，seek 以媒體時間跨塊定位
/// （AudioManifest.locate）。chunk 不合併，逐塊以 AVAudioPlayer 播放。
@MainActor
@Observable
public final class SessionPlayer: NSObject, AVAudioPlayerDelegate {

    public enum PlayerError: Error {
        case missingManifest
        case emptyAudio
    }

    public private(set) var isPlaying = false
    public private(set) var currentSeconds: Double = 0
    public let totalSeconds: Double

    private let audioDirectory: URL
    private let manifest: AudioManifest
    private var player: AVAudioPlayer?
    private var currentChunkIndex = -1
    private var pollTask: Task<Void, Never>?

    public init(audioDirectory: URL) throws {
        guard let manifest = try AudioManifestFile.readIfPresent(from: audioDirectory) else {
            throw PlayerError.missingManifest
        }
        guard !manifest.chunks.isEmpty else {
            throw PlayerError.emptyAudio
        }
        self.audioDirectory = audioDirectory
        self.manifest = manifest
        self.totalSeconds = manifest.totalDurationSeconds
        super.init()
    }

    public func togglePlay() {
        isPlaying ? pause() : play()
    }

    public func play() {
        if player == nil {
            applySeek(to: currentSeconds >= totalSeconds ? 0 : currentSeconds)
        }
        player?.play()
        isPlaying = player?.isPlaying ?? false
        startPolling()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        stopPolling()
    }

    public func seek(to seconds: Double) {
        let wasPlaying = isPlaying
        applySeek(to: seconds)
        if wasPlaying {
            player?.play()
        } else {
            isPlaying = false
        }
    }

    public func stop() {
        pause()
        player = nil
        currentChunkIndex = -1
        currentSeconds = 0
    }

    // MARK: - AVAudioPlayerDelegate

    public nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully flag: Bool
    ) {
        Task { @MainActor in
            self.advanceToNextChunk()
        }
    }

    // MARK: - 私有

    private func applySeek(to seconds: Double) {
        let clamped = min(max(0, seconds), max(0, totalSeconds - 0.01))
        guard let location = manifest.locate(seconds: clamped) else { return }
        loadChunk(at: location.chunkIndex)
        player?.currentTime = location.offsetSeconds
        currentSeconds = clamped
    }

    private func loadChunk(at index: Int) {
        guard index != currentChunkIndex || player == nil else { return }
        let url = audioDirectory.appending(path: manifest.chunks[index].file)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        currentChunkIndex = index
    }

    private func advanceToNextChunk() {
        let next = currentChunkIndex + 1
        guard next < manifest.chunks.count else {
            isPlaying = false
            stopPolling()
            currentSeconds = totalSeconds
            player = nil
            currentChunkIndex = -1
            return
        }
        loadChunk(at: next)
        player?.play()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                if isPlaying, currentChunkIndex >= 0, let player {
                    currentSeconds =
                        manifest.chunks[currentChunkIndex].startSeconds + player.currentTime
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
