import AVFoundation
import Foundation
import Speech
import SSCore

/// 主引擎：macOS 26 SpeechAnalyzer + SpeechTranscriber（on-device）。
/// volatile 與 finalized 都帶 audioTimeRange 時間中繼資料；
/// 餵入的音訊先轉成引擎的 bestAvailableAudioFormat。
public actor AppleSpeechEngine: TranscriptionEngine {

    public enum EngineError: Error {
        case notStarted
        case formatUnavailable
        case conversionFailed
        case localeUnsupported
    }

    public nonisolated let info = EngineInfo(name: "SpeechAnalyzer", isOnDevice: true)

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?
    private var sessionID = ""
    private var language = "zh-TW"
    private var segmentCount = 0
    private var contextualStrings: [String] = []
    private var finalizedContinuation: AsyncStream<TranscriptSegment>.Continuation?
    private var volatileContinuation: AsyncStream<VolatileUpdate>.Continuation?

    public init() {}

    /// 詞彙提示（v0.2 名詞表第二層），於 start 套到 analyzer 的 AnalysisContext。
    public func setContextualStrings(_ strings: [String]) {
        contextualStrings = strings
    }

    public func availability(for locale: Locale) async -> EngineAvailability {
        let supported = await SpeechTranscriber.supportedLocales
        guard let match = Self.bestSupported(for: locale, from: supported) else {
            return .unsupported
        }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(where: {
            $0.identifier(.bcp47) == match.identifier(.bcp47)
        }) ? .available : .requiresDownload
    }

    /// 模型未安裝時觸發 AssetInventory 下載。
    public func prepare(locale: Locale) async throws {
        try await prepare(locale: locale, progress: { _ in })
    }

    /// 同上但回報下載進度。AssetInstallationRequest 符合 NSProgressReporting，
    /// 以其 progress.fractionCompleted 輪詢回報；已安裝時直接回報完成。
    public func prepare(
        locale: Locale, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard let match = Self.bestSupported(for: locale, from: supported) else {
            throw EngineError.localeUnsupported
        }
        let transcriber = makeTranscriber(locale: match)
        guard
            let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber])
        else {
            progress(1)
            return
        }
        let reporter = request.progress
        let poller = Task {
            while !Task.isCancelled {
                progress(reporter.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        do {
            try await request.downloadAndInstall()
            poller.cancel()
            progress(1)
        } catch {
            poller.cancel()
            throw error
        }
    }

    public func start(sessionID: String, locale: Locale) async throws {
        self.sessionID = sessionID
        let supported = await SpeechTranscriber.supportedLocales
        let resolved = Self.bestSupported(for: locale, from: supported) ?? locale
        self.language = resolved.identifier
        let transcriber = makeTranscriber(locale: resolved)
        self.transcriber = transcriber
        guard
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber])
        else {
            throw EngineError.formatUnavailable
        }
        analyzerFormat = format
        let (inputSequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputBuilder = builder
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: inputSequence)
        // 詞彙提示：AnalysisContext.contextualStrings[.general]，於餵入音訊前設定。
        // 來源：developer.apple.com/documentation/speech/speechanalyzer/setcontext(_:)
        //       /documentation/speech/analysiscontext/contextualstrings
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: contextualStrings]
            try await analyzer.setContext(context)
        }
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    self.handle(
                        text: String(result.text.characters),
                        timeRange: Self.timeRange(of: result.text),
                        isFinal: result.isFinal)
                }
            } catch {
                // 結果流出錯：結束兩個輸出流，coordinator 會標記失敗。
            }
            self.closeStreams()
        }
    }

    public func feed(_ slice: AudioSlice) async throws {
        guard let inputBuilder else { throw EngineError.notStarted }
        guard let analyzerFormat else { throw EngineError.formatUnavailable }
        let buffer: AVAudioPCMBuffer
        if slice.buffer.format == analyzerFormat {
            buffer = slice.buffer
        } else {
            buffer = try convert(slice.buffer, to: analyzerFormat)
        }
        inputBuilder.yield(AnalyzerInput(buffer: buffer))
    }

    public func finish() async throws {
        inputBuilder?.finish()
        inputBuilder = nil
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        transcriber = nil
    }

    public func finalizedSegments() -> AsyncStream<TranscriptSegment> {
        AsyncStream { finalizedContinuation = $0 }
    }

    public func volatileUpdates() -> AsyncStream<VolatileUpdate> {
        AsyncStream { volatileContinuation = $0 }
    }

    // MARK: - 私有

    private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange])
    }

    private func handle(text: String, timeRange: (start: Double, end: Double)?, isFinal: Bool) {
        guard !text.isEmpty else { return }
        let start = timeRange?.start ?? 0
        let end = timeRange?.end ?? start
        if isFinal {
            segmentCount += 1
            let createdAt = Date(
                timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
            finalizedContinuation?.yield(
                TranscriptSegment(
                    segmentID: String(format: "seg_%04d", segmentCount),
                    sessionID: sessionID,
                    startSeconds: start,
                    endSeconds: end,
                    text: text,
                    isFinal: true,
                    language: language,
                    engine: info.name,
                    model: "system",
                    createdAt: createdAt))
        } else {
            volatileContinuation?.yield(VolatileUpdate(text: text, startSeconds: start))
        }
    }

    private func closeStreams() {
        finalizedContinuation?.finish()
        volatileContinuation?.finish()
    }

    /// 從 AttributedString 的 audioTimeRange 屬性取整段時間範圍。
    private static func timeRange(of text: AttributedString) -> (start: Double, end: Double)? {
        var start: Double?
        var end: Double?
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let runStart = range.start.seconds
            let runEnd = range.end.seconds
            start = min(start ?? runStart, runStart)
            end = max(end ?? runEnd, runEnd)
        }
        guard let start, let end else { return nil }
        return (start, end)
    }

    /// 把請求的 locale 解析成 SpeechTranscriber 實際支援的：精確 bcp47 優先；
    /// 請求未指定地區（如 en、ja）退而取同語言碼的第一個支援地區（en-US、ja-JP）；
    /// 請求有指定地區（如 zh-TW）只接受精確相符，以區分繁簡。
    static func bestSupported(for requested: Locale, from supported: [Locale]) -> Locale? {
        if let exact = supported.first(where: {
            $0.identifier(.bcp47) == requested.identifier(.bcp47)
        }) {
            return exact
        }
        guard requested.region == nil else { return nil }
        let language = requested.language.languageCode?.identifier
        let candidates = supported.filter {
            $0.language.languageCode?.identifier == language
        }
        // 優先取該語言的慣用地區（en→US、ja→JP），否則第一個支援地區。
        let preferredRegion = Locale.Language(
            identifier: Locale.Language(identifier: language ?? "").maximalIdentifier
        ).region?.identifier
        return candidates.first { $0.region?.identifier == preferredRegion }
            ?? candidates.first
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if converter == nil || converter?.inputFormat != buffer.format
            || converter?.outputFormat != format
        {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { throw EngineError.conversionFailed }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw EngineError.conversionFailed
        }
        // convert 的輸入 block 標記 @Sendable 但於 convert 呼叫期間同步執行，
        // 以一次性 box 傳遞 buffer 屬安全。
        final class OneShotInput: @unchecked Sendable {
            var buffer: AVAudioPCMBuffer?
            init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        }
        let input = OneShotInput(buffer)
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            guard let next = input.buffer else {
                status.pointee = .noDataNow
                return nil
            }
            input.buffer = nil
            status.pointee = .haveData
            return next
        }
        if let conversionError {
            throw conversionError
        }
        return output
    }
}
