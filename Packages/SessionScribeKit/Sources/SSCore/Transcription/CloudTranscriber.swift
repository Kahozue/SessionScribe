import Foundation

/// 雲端離線轉寫：把 session 音訊（CAF chunks）以 AudioExporter 串成單一 .m4a 上傳雲端 STT，
/// 結果對應為 TranscriptSegment 落盤。時間以整段音訊起點為基準。
public enum CloudTranscriber {

    public enum TranscribeError: LocalizedError {
        case noAudio

        public var errorDescription: String? {
            switch self {
            case .noAudio: "這個 session 沒有可轉寫的音訊。"
            }
        }
    }

    /// 純對應：STT 分段 → TranscriptSegment。
    public static func makeSegments(from stt: [CloudSTTSegment], sessionID: String,
                                    language: String, model: String) -> [TranscriptSegment] {
        stt.map { s in
            TranscriptSegment(
                segmentID: UUID().uuidString,
                sessionID: sessionID,
                startSeconds: s.startSeconds,
                endSeconds: s.endSeconds,
                text: s.text,
                isFinal: true,
                language: language,
                engine: "cloud",
                model: model,
                speaker: s.speaker)
        }
    }

    /// 完整流程：匯出 m4a → 呼叫 STT → 套名詞表 → 落盤。progress 0→1。
    public static func transcribe(
        sessionDirectory: URL,
        session: Session,
        client: CloudSTTClient,
        store: SessionStore,
        model: String,
        lexicon: [LexiconRule] = [],
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let audioDirectory = sessionDirectory.appending(path: SessionFiles.audioDirectory)
        guard try AudioManifestFile.readIfPresent(from: audioDirectory) != nil else {
            throw TranscribeError.noAudio
        }
        progress?(0.1)
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "ss-stt-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await AudioExporter.exportM4A(audioDirectory: audioDirectory, to: tmp)
        progress?(0.4)

        let languageCode = Locale(identifier: session.locale).language.languageCode?.identifier
        let raw = try await client.transcribe(audioFileURL: tmp, languageCode: languageCode)
        progress?(0.8)

        var segments = makeSegments(
            from: raw, sessionID: session.sessionID, language: session.locale, model: model)
        if !lexicon.isEmpty {
            segments = segments.map {
                var s = $0; s.text = Lexicon.apply(s.text, rules: lexicon); return s
            }
        }
        for segment in segments {
            try await store.appendSegment(segment)
        }
        progress?(1)
    }
}
