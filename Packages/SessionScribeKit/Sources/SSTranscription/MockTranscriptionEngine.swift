import Foundation
import SSCore

/// mock 腳本中的一句話。
public struct MockUtterance: Equatable, Sendable {
    public let text: String
    public let startSeconds: Double
    public let endSeconds: Double

    public init(text: String, startSeconds: Double, endSeconds: Double) {
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

/// 腳本驅動的假引擎：依餵入的媒體時間吐出漸進 volatile 與 finalized 結果，
/// 完全不看音訊內容，因此 UI 與儲存開發、測試都不需要真實語音或新 API。
/// 可注入錯誤模擬 ASR 失敗（驗收：ASR 失敗錄音不中斷）。
public actor MockTranscriptionEngine: TranscriptionEngine {

    public struct InjectedFailure: Error {}

    public nonisolated let info = EngineInfo(name: "Mock", isOnDevice: true)

    private let script: [MockUtterance]
    private let failAtSeconds: Double?
    private var sessionID = ""
    private var language = "zh-TW"
    private var finalizedCount = 0
    private var nextIndex = 0
    private var lastTime = 0.0
    private var finished = false
    private var finalizedContinuation: AsyncStream<TranscriptSegment>.Continuation?
    private var volatileContinuation: AsyncStream<VolatileUpdate>.Continuation?
    private let now: @Sendable () -> Date

    public init(
        script: [MockUtterance] = MockTranscriptionEngine.defaultScript,
        failAtSeconds: Double? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.script = script.sorted { $0.startSeconds < $1.startSeconds }
        self.failAtSeconds = failAtSeconds
        self.now = now
    }

    /// 論文口試問答示例，約一分鐘。
    public static let defaultScript: [MockUtterance] = [
        MockUtterance(text: "請問你為什麼選擇這個資料集？", startSeconds: 2, endSeconds: 6),
        MockUtterance(text: "因為它是公開、有人工標註，而且規模足以支撐我們的實驗設計。", startSeconds: 8, endSeconds: 15),
        MockUtterance(text: "第三章的消融實驗只跑了一個隨機種子，結論的穩定性怎麼說？", startSeconds: 18, endSeconds: 26),
        MockUtterance(text: "我們補了三個種子的結果放在附錄B，標準差在百分之零點五以內。", startSeconds: 28, endSeconds: 36),
        MockUtterance(text: "建議把相關工作一節的比較表加上推論延遲欄位。", startSeconds: 40, endSeconds: 47),
        MockUtterance(text: "好的，這部分我會在修訂版補上。", startSeconds: 49, endSeconds: 54),
    ]

    public func availability(for locale: Locale) -> EngineAvailability {
        .available
    }

    public func prepare(locale: Locale) {}

    public func start(sessionID: String, locale: Locale) {
        self.sessionID = sessionID
        self.language = locale.identifier
    }

    public func finalizedSegments() -> AsyncStream<TranscriptSegment> {
        AsyncStream { finalizedContinuation = $0 }
    }

    public func volatileUpdates() -> AsyncStream<VolatileUpdate> {
        AsyncStream { volatileContinuation = $0 }
    }

    public func feed(_ slice: AudioSlice) throws {
        let time = max(slice.startSeconds, slice.endSeconds)
        if let failAtSeconds, time >= failAtSeconds {
            throw InjectedFailure()
        }
        lastTime = max(lastTime, time)
        advance(to: lastTime)
    }

    public func finish() {
        guard !finished else { return }
        finished = true
        // 已開始未完成的 utterance 收尾為 finalized。
        if nextIndex < script.count, lastTime > script[nextIndex].startSeconds {
            finalize(script[nextIndex])
            nextIndex += 1
        }
        finalizedContinuation?.finish()
        volatileContinuation?.finish()
    }

    // MARK: - 私有

    private func advance(to time: Double) {
        while nextIndex < script.count, script[nextIndex].endSeconds <= time {
            finalize(script[nextIndex])
            nextIndex += 1
        }
        guard nextIndex < script.count else { return }
        let utterance = script[nextIndex]
        if time > utterance.startSeconds {
            let progress = min(
                (time - utterance.startSeconds)
                    / (utterance.endSeconds - utterance.startSeconds), 1)
            let prefixLength = max(1, Int(Double(utterance.text.count) * progress))
            volatileContinuation?.yield(
                VolatileUpdate(
                    text: String(utterance.text.prefix(prefixLength)),
                    startSeconds: utterance.startSeconds))
        }
    }

    private func finalize(_ utterance: MockUtterance) {
        finalizedCount += 1
        // 取整秒：ISO-8601 為秒級精度，使記憶體值與落盤 round-trip 後相等。
        let createdAt = Date(
            timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        finalizedContinuation?.yield(
            TranscriptSegment(
                segmentID: String(format: "seg_%04d", finalizedCount),
                sessionID: sessionID,
                startSeconds: utterance.startSeconds,
                endSeconds: utterance.endSeconds,
                text: utterance.text,
                isFinal: true,
                language: language,
                engine: "Mock",
                model: "mock",
                createdAt: createdAt))
    }
}
