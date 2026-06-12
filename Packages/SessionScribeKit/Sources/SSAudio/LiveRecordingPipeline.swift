import AVFoundation
import SSCore

/// 實機錄音管線：組合 AudioCaptureService、ChunkedAudioWriter 與 MediaClock，
/// 實作 SSCore 的 RecordingPipeline。一條 buffer 流推進時鐘、計算音量、寫入 chunk；
/// ASR 消費者（M4）將另外訂閱同一個 distributor 的流。
public actor LiveRecordingPipeline: RecordingPipeline {

    private let capture = AudioCaptureService()
    private let audioDirectory: URL
    private let deviceUID: String?
    private let chunkDuration: TimeInterval

    private var clock: MediaClock?
    private var writer: ChunkedAudioWriter?
    private var consumerTask: Task<Void, Never>?
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?
    private var writeError: (any Error)?

    public init(
        audioDirectory: URL,
        deviceUID: String? = nil,
        chunkDuration: TimeInterval = AudioDefaults.chunkDuration
    ) {
        self.audioDirectory = audioDirectory
        self.deviceUID = deviceUID
        self.chunkDuration = chunkDuration
    }

    /// 音量更新流，供 level meter UI 訂閱（在 start 前訂閱）。
    public func levelUpdates() -> AsyncStream<AudioLevel> {
        AsyncStream { continuation in
            levelContinuation = continuation
        }
    }

    public func start() async throws {
        if MicrophonePermission.status != .authorized {
            guard await MicrophonePermission.request() else {
                throw MicrophonePermission.PermissionError.denied
            }
        }
        let stream = await capture.makeBufferStream()
        let format = try await capture.start(deviceUID: deviceUID)
        let clock = MediaClock(sampleRate: format.sampleRate)
        self.clock = clock
        writer = ChunkedAudioWriter(
            audioDirectory: audioDirectory, format: format, chunkDuration: chunkDuration)
        consumerTask = Task {
            for await captured in stream {
                await self.process(captured)
            }
        }
    }

    public func pause() async throws {
        await capture.pause()
    }

    public func resume() async throws {
        try await capture.resume()
    }

    /// 停止擷取、瀝乾 buffer 流、收尾 chunk 與索引。
    /// 寫入錯誤在此拋出：SessionController 會保持 ended_at == null，
    /// 留給下次啟動的恢復掃描。
    public func stop() async throws {
        await capture.stop()
        await consumerTask?.value
        consumerTask = nil
        levelContinuation?.finish()
        _ = try await writer?.finish()
        if let writeError {
            throw writeError
        }
    }

    public var mediaSeconds: Double {
        clock?.currentSeconds ?? 0
    }

    private func process(_ captured: CapturedBuffer) async {
        clock?.advance(frames: captured.frames)
        levelContinuation?.yield(AudioLevelMeter.level(of: captured.buffer))
        guard let writer else { return }
        do {
            try await writer.write(captured)
        } catch {
            // 記錄首個寫入錯誤；錄音流程繼續，stop 時回報。
            if writeError == nil {
                writeError = error
            }
        }
    }
}
