import AVFoundation
import Foundation
import Speech
import SSCore

/// 備援引擎：SFSpeechRecognizer，強制 on-device（沙盒無網路，伺服器辨識必然失敗）。
/// partial 結果作 volatile；final 結果切成一個 segment 後重啟 request 續轉，
/// 媒體時間以 request 起點偏移校正。
public actor LegacySFSpeechEngine: TranscriptionEngine {

    public enum EngineError: Error {
        case unavailable
        case authorizationDenied
    }

    public nonisolated let info = EngineInfo(name: "SFSpeechRecognizer", isOnDevice: true)

    /// resultHandler 跨入 actor 前先抽出的 Sendable 載荷。
    private struct ResultPayload: Sendable {
        let text: String
        let firstTimestamp: Double
        let lastEnd: Double
        let isFinal: Bool
    }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var locale = Locale(identifier: "zh-TW")
    private var sessionID = ""
    private var segmentCount = 0
    /// 目前 request 的媒體時間起點：引擎回報的 timestamp 相對於 request 開頭。
    private var requestStartSeconds = 0.0
    private var lastFedEndSeconds = 0.0
    private var contextualStrings: [String] = []
    private var finished = false
    private var finalizedContinuation: AsyncStream<TranscriptSegment>.Continuation?
    private var volatileContinuation: AsyncStream<VolatileUpdate>.Continuation?

    public init() {}

    /// 詞彙提示（v0.2 名詞表第二層）；每次重啟 request 時重新套用。
    public func setContextualStrings(_ strings: [String]) {
        contextualStrings = strings
    }

    public func availability(for locale: Locale) async -> EngineAvailability {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
            recognizer.supportsOnDeviceRecognition
        else {
            return .unsupported
        }
        return .available
    }

    public func prepare(locale: Locale) async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw EngineError.authorizationDenied
        }
    }

    public func start(sessionID: String, locale: Locale) async throws {
        self.sessionID = sessionID
        self.locale = locale
        guard let recognizer = SFSpeechRecognizer(locale: locale),
            recognizer.supportsOnDeviceRecognition
        else {
            throw EngineError.unavailable
        }
        self.recognizer = recognizer
        startNewRequest(at: 0)
    }

    public func feed(_ slice: AudioSlice) async throws {
        guard let request else { throw EngineError.unavailable }
        lastFedEndSeconds = slice.endSeconds
        request.append(slice.buffer)
    }

    public func finish() async throws {
        finished = true
        request?.endAudio()
        // 結果回呼是非同步的，給引擎短暫時間吐出最後的 final。
        try? await Task.sleep(for: .milliseconds(800))
        task?.cancel()
        task = nil
        request = nil
        finalizedContinuation?.finish()
        volatileContinuation?.finish()
    }

    public func finalizedSegments() -> AsyncStream<TranscriptSegment> {
        AsyncStream { finalizedContinuation = $0 }
    }

    public func volatileUpdates() -> AsyncStream<VolatileUpdate> {
        AsyncStream { volatileContinuation = $0 }
    }

    // MARK: - 私有

    private func startNewRequest(at mediaSeconds: Double) {
        guard let recognizer else { return }
        requestStartSeconds = mediaSeconds
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // 詞彙提示：偏向辨識名詞表術語，即使不在系統詞庫。
        // 來源：developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings
        request.contextualStrings = contextualStrings
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let segments = result.bestTranscription.segments
            let payload = ResultPayload(
                text: result.bestTranscription.formattedString,
                firstTimestamp: segments.first?.timestamp ?? 0,
                lastEnd: (segments.last.map { $0.timestamp + $0.duration }) ?? 0,
                isFinal: result.isFinal)
            Task { await self.handle(payload) }
        }
    }

    private func handle(_ payload: ResultPayload) {
        guard !payload.text.isEmpty else { return }
        let start = requestStartSeconds + payload.firstTimestamp
        let end = requestStartSeconds + payload.lastEnd
        if payload.isFinal {
            segmentCount += 1
            let createdAt = Date(
                timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
            finalizedContinuation?.yield(
                TranscriptSegment(
                    segmentID: String(format: "seg_%04d", segmentCount),
                    sessionID: sessionID,
                    startSeconds: start,
                    endSeconds: end,
                    text: payload.text,
                    isFinal: true,
                    language: locale.identifier,
                    engine: info.name,
                    model: "system",
                    createdAt: createdAt))
            // final 後重啟 request 續轉，新 request 的時間軸從目前餵入位置起算。
            if !finished {
                startNewRequest(at: lastFedEndSeconds)
            }
        } else {
            volatileContinuation?.yield(VolatileUpdate(text: payload.text, startSeconds: start))
        }
    }
}
