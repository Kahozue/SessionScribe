import Foundation

/// 轉寫協調者：包住一個 TranscriptionEngine，吸收引擎錯誤使其不影響錄音
/// （核心可靠性原則 2），並負責 finalized segment 先落盤再轉發 UI（原則 6）。
public actor TranscriptionCoordinator {

    private let engine: any TranscriptionEngine
    private let store: SessionStore?
    /// 名詞表校正規則（v0.2）：在 finalized 落盤前與 volatile 轉發前套用。
    private let lexicon: [LexiconRule]
    /// 詞彙提示（v0.2 名詞表第二層）：取名詞表的校正目標（to）去重，
    /// start 前餵給引擎偏向辨識，從源頭緩解中英術語辨識劣化。
    private let contextualStrings: [String]
    public private(set) var failed = false
    public private(set) var lastError: (any Error)?

    private var finalizedOut: AsyncStream<TranscriptSegment>.Continuation?
    private var volatileOut: AsyncStream<VolatileUpdate>.Continuation?
    private var pumpTasks: [Task<Void, Never>] = []

    public init(
        engine: any TranscriptionEngine,
        store: SessionStore?,
        lexicon: [LexiconRule] = []
    ) {
        self.engine = engine
        self.store = store
        self.lexicon = lexicon
        var seen = Set<String>()
        self.contextualStrings = lexicon.compactMap { rule in
            let term = rule.to.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, seen.insert(term).inserted else { return nil }
            return term
        }
    }

    public nonisolated var engineInfo: EngineInfo { engine.info }

    /// UI 訂閱（須在 start 前呼叫）。
    public func finalizedUpdates() -> AsyncStream<TranscriptSegment> {
        AsyncStream { finalizedOut = $0 }
    }

    public func volatileUpdates() -> AsyncStream<VolatileUpdate> {
        AsyncStream { volatileOut = $0 }
    }

    public func start(sessionID: String, locale: Locale) async throws {
        let finalized = await engine.finalizedSegments()
        let volatiles = await engine.volatileUpdates()
        if !contextualStrings.isEmpty {
            await engine.setContextualStrings(contextualStrings)
        }
        try await engine.start(sessionID: sessionID, locale: locale)
        pumpTasks.append(
            Task {
                for await segment in finalized {
                    await self.handleFinalized(segment)
                }
                await self.closeFinalized()
            })
        pumpTasks.append(
            Task {
                for await update in volatiles {
                    await self.forwardVolatile(update)
                }
                await self.closeVolatile()
            })
    }

    /// 引擎拋錯時記錄並停止餵入；錄音與寫檔分支完全不受影響。
    public func feed(_ slice: AudioSlice) async {
        guard !failed else { return }
        do {
            try await engine.feed(slice)
        } catch {
            failed = true
            lastError = error
        }
    }

    public func finish() async {
        do {
            try await engine.finish()
        } catch {
            if lastError == nil {
                lastError = error
            }
        }
        for task in pumpTasks {
            await task.value
        }
        pumpTasks = []
    }

    // MARK: - 私有

    private func handleFinalized(_ rawSegment: TranscriptSegment) async {
        var segment = rawSegment
        if !lexicon.isEmpty {
            segment.text = Lexicon.apply(segment.text, rules: lexicon)
        }
        if let store {
            do {
                try await store.appendSegment(segment)
            } catch {
                // 落盤失敗仍轉發 UI（原則 3：逐字稿保存失敗不吞掉已有結果）。
                if lastError == nil {
                    lastError = error
                }
            }
        }
        finalizedOut?.yield(segment)
    }

    private func forwardVolatile(_ update: VolatileUpdate) {
        guard !lexicon.isEmpty else {
            volatileOut?.yield(update)
            return
        }
        let corrected = VolatileUpdate(
            text: Lexicon.apply(update.text, rules: lexicon),
            startSeconds: update.startSeconds)
        volatileOut?.yield(corrected)
    }

    private func closeFinalized() {
        finalizedOut?.finish()
    }

    private func closeVolatile() {
        volatileOut?.finish()
    }
}
