import AppKit
import SSAudio
import SSCore
import SSTranscription
import SwiftUI

/// 錄音檢視頁的 view model：載入 metadata、segments、markers，
/// 透過 SessionPlayerCache 共用播放器（切換 session 進度不歸零），
/// 並推導歌詞式定位的當前 segment。
@MainActor
@Observable
final class SessionDetailViewModel {
    private(set) var session: Session?
    private(set) var segments: [TranscriptSegment] = []
    private(set) var markers: [Marker] = []
    private(set) var player: SessionPlayer?
    var errorMessage: String?
    private(set) var transcribing = false
    private(set) var transcribeProgress = 0.0

    let directory: URL
    private let store: SessionStore

    init(directory: URL) {
        self.directory = directory
        self.store = SessionStore(directory: directory)
    }

    func load() async {
        do {
            session = try await store.loadMetadata()
            segments = try await store.loadSegments()
            markers = try await store.loadMarkers()
            player = try? SessionPlayerCache.shared.player(
                for: directory.appending(path: SessionFiles.audioDirectory))
        } catch {
            errorMessage = "載入 session 失敗：\(error.localizedDescription)"
        }
    }

    /// 點標題改名：metadata 即時落盤。
    func rename(to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard var updated = session, !trimmed.isEmpty, trimmed != updated.title else { return }
        updated.title = trimmed
        session = updated
        Task {
            do {
                try await store.saveMetadata(updated)
            } catch {
                errorMessage = "重新命名失敗：\(error.localizedDescription)"
            }
        }
    }

    /// 歌詞式定位：播放時間落在哪個 segment（取最後一個已開始的）。
    var currentSegmentID: String? {
        guard let player, !segments.isEmpty else { return nil }
        let time = player.currentSeconds
        return segments.last { $0.startSeconds <= time }?.segmentID
    }

    /// 對既有音訊離線轉寫（匯入的 session 或純錄音場次）。
    func transcribe() async {
        guard let session, !transcribing else { return }
        transcribing = true
        transcribeProgress = 0
        defer { transcribing = false }
        let useMock = UserDefaults.standard.bool(forKey: DisplaySettings.useMockEngineKey)
        guard
            let engine = await EngineSelector.selectAndPrepare(
                from: EngineSelector.defaultChain(useMock: useMock),
                locale: Locale(identifier: session.locale))
        else {
            errorMessage = "沒有可用的轉寫引擎。"
            return
        }
        let coordinator = TranscriptionCoordinator(engine: engine, store: store)
        do {
            try await OfflineTranscriber.transcribe(
                sessionDirectory: directory, session: session, coordinator: coordinator
            ) { progress in
                Task { @MainActor in self.transcribeProgress = progress }
            }
            segments = try await store.loadSegments()
        } catch {
            errorMessage = "轉寫失敗：\(error.localizedDescription)"
        }
    }
}

/// 錄音檢視頁（規格 1.1 第 5、10 項）：metadata、chunk 串接播放、
/// 進度條、倍速、歌詞模式與列表模式雙顯示。
public struct SessionDetailView: View {
    @State private var model: SessionDetailViewModel
    /// 搜尋跳轉時要定位的 segment。
    let highlightSegmentID: String?
    /// 右欄（事件標記與後續擴充）收合狀態，與主視窗工具列的切換鈕共用。
    @Binding var showInspector: Bool
    /// 改名後通知外層（側欄列表同步）。
    let onRename: (() -> Void)?

    /// 搜尋跳轉的高亮：定位後短暫顯示再淡出（規格 1.1 第 9 項回饋修正）。
    @State private var activeHighlightID: String?
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFieldFocused: Bool
    @AppStorage(DisplaySettings.transcriptModeKey)
    private var transcriptMode = DisplaySettings.lyricsMode

    private static let playbackRates: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    public init(
        directory: URL,
        highlightSegmentID: String? = nil,
        showInspector: Binding<Bool> = .constant(true),
        onRename: (() -> Void)? = nil
    ) {
        _model = State(initialValue: SessionDetailViewModel(directory: directory))
        self.highlightSegmentID = highlightSegmentID
        self._showInspector = showInspector
        self.onRename = onRename
    }

    public var body: some View {
        content
            .inspector(isPresented: $showInspector) {
                detailInspector
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if let session = model.session {
                header(session)
                Divider()
                playbackBar
                Divider()
                if model.segments.isEmpty {
                    emptyTranscriptArea
                } else if transcriptMode == DisplaySettings.listMode {
                    PlainTranscriptView(
                        segments: model.segments,
                        currentSegmentID: model.currentSegmentID,
                        highlightSegmentID: activeHighlightID
                    ) { segment in
                        model.player?.seek(to: segment.startSeconds)
                    }
                } else {
                    LyricsTranscriptView(
                        segments: model.segments,
                        currentSegmentID: model.currentSegmentID,
                        highlightSegmentID: activeHighlightID
                    ) { segment in
                        model.player?.seek(to: segment.startSeconds)
                    }
                }
            } else {
                ProgressView("載入中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.directory) { await model.load() }
        .task(id: highlightSegmentID) {
            activeHighlightID = highlightSegmentID
            guard highlightSegmentID != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.5)) {
                activeHighlightID = nil
            }
        }
        .alert(
            "發生錯誤",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// 檢視頁右欄：事件標記列表；點時間跳轉播放。後續功能擴充也放這裡。
    private var detailInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("事件標記")
                .font(.headline)
            if model.markers.isEmpty {
                Text("這個 session 沒有標記。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List(model.markers) { marker in
                    Button {
                        model.player?.seek(to: marker.mediaSeconds)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Label(marker.label, systemImage: "bookmark.fill")
                                    .font(.callout)
                                Spacer()
                                Text(TimeFormatting.hms(marker.mediaSeconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if !marker.note.isEmpty {
                                Text(marker.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("跳到 \(TimeFormatting.hms(marker.mediaSeconds))")
                }
                .listStyle(.inset)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
    }

    /// 標題列：點標題文字改名（仿 iOS）；資訊列只留語言、分段數、標記數。
    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if editingTitle {
                    TextField("名稱", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2.bold())
                        .focused($titleFieldFocused)
                        .frame(maxWidth: 360)
                        .onSubmit { commitRename() }
                        .onExitCommand { editingTitle = false }
                } else {
                    Text(session.title)
                        .font(.title2.bold())
                        .onTapGesture {
                            titleDraft = session.title
                            editingTitle = true
                            titleFieldFocused = true
                        }
                        .help("點擊重新命名")
                }
                if session.source == .imported {
                    Text("匯入")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if session.recovered {
                    Text("已恢復")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                displayModeToggle
            }
            Text("\(session.locale)　分段：\(model.segments.count)　標記：\(model.markers.count)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commitRename() {
        model.rename(to: titleDraft)
        editingTitle = false
        onRename?()
    }

    /// 顯示模式切換：點擊在歌詞模式與列表模式間循環，與倍速同樣的輕量互動。
    private var displayModeToggle: some View {
        Button {
            transcriptMode =
                transcriptMode == DisplaySettings.lyricsMode
                ? DisplaySettings.listMode : DisplaySettings.lyricsMode
        } label: {
            Label(
                transcriptMode == DisplaySettings.lyricsMode ? "歌詞模式" : "列表模式",
                systemImage: transcriptMode == DisplaySettings.lyricsMode
                    ? "music.note.list" : "list.bullet")
            .font(.callout)
        }
        .buttonStyle(.borderless)
        .help("切換逐字稿顯示方式（歌詞模式與列表模式循環）")
    }

    @ViewBuilder
    private var playbackBar: some View {
        if let player = model.player {
            HStack(spacing: 10) {
                Button {
                    if !player.isPlaying {
                        SessionPlayerCache.shared.pauseAll(except: player)
                    }
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(player.isPlaying ? "暫停" : "播放")
                Button {
                    let index =
                        Self.playbackRates.firstIndex(of: player.playbackRate) ?? 3
                    player.playbackRate =
                        Self.playbackRates[(index + 1) % Self.playbackRates.count]
                } label: {
                    Text(String(format: "%g×", player.playbackRate))
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 40)
                }
                .buttonStyle(.borderless)
                .help("播放倍速（點擊循環切換）")
                Text(TimeFormatting.hms(player.currentSeconds))
                    .font(.caption.monospacedDigit())
                Slider(
                    value: Binding(
                        get: { player.currentSeconds },
                        set: { player.seek(to: $0) }),
                    in: 0...max(player.totalSeconds, 0.01))
                Text(TimeFormatting.hms(player.totalSeconds))
                    .font(.caption.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            Text("此 session 沒有可播放的音訊。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var emptyTranscriptArea: some View {
        ContentUnavailableView {
            Label("沒有逐字稿", systemImage: "text.bubble")
        } description: {
            Text("這個 session 還沒有轉寫結果。")
        } actions: {
            if model.transcribing {
                ProgressView(value: model.transcribeProgress) {
                    Text("離線轉寫中 \(Int(model.transcribeProgress * 100))%")
                }
                .frame(width: 220)
            } else if model.player != nil {
                Button("離線轉寫這段音訊") {
                    Task { await model.transcribe() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 歌詞模式（規格 1.1 第 10 項）：當前 segment 放大、全不透明、加粗，
/// 其餘縮小降不透明度，spring 動畫切換並自動置中。
/// 內文可選取複製；點時間戳跳轉播放位置。
struct LyricsTranscriptView: View {
    let segments: [TranscriptSegment]
    let currentSegmentID: String?
    let highlightSegmentID: String?
    let onSelect: (TranscriptSegment) -> Void
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(segments) { segment in
                        lyricsRow(segment)
                            .id(segment.segmentID)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .onChange(of: currentSegmentID) {
                guard let currentSegmentID else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(currentSegmentID, anchor: .center)
                }
            }
            .onAppear {
                if let highlightSegmentID {
                    proxy.scrollTo(highlightSegmentID, anchor: .center)
                }
            }
        }
    }

    private func lyricsRow(_ segment: TranscriptSegment) -> some View {
        let isCurrent = segment.segmentID == currentSegmentID
        let isHighlighted = segment.segmentID == highlightSegmentID
        return VStack(alignment: .leading, spacing: 3) {
            Text(TimeFormatting.hms(segment.startSeconds))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(segment)
                }
                .help("點擊時間跳到 \(TimeFormatting.hms(segment.startSeconds))")
            Text(segment.text)
                .font(.system(
                    size: isCurrent ? fontSize * 1.3 : fontSize,
                    weight: isCurrent ? .bold : .regular))
                .lineSpacing(fontSize * 0.3)
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .opacity(isCurrent ? 1.0 : 0.5)
                .textSelection(.enabled)
        }
        .scaleEffect(isCurrent ? 1.0 : 0.97, anchor: .leading)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentSegmentID)
    }
}

/// 列表模式：時間徽章加內文的一般排版，適合閱讀與大段選取複製；
/// 點時間徽章跳轉播放位置，不自動捲動。
struct PlainTranscriptView: View {
    let segments: [TranscriptSegment]
    let currentSegmentID: String?
    let highlightSegmentID: String?
    let onSelect: (TranscriptSegment) -> Void
    @AppStorage(DisplaySettings.fontSizeKey)
    private var fontSize = DisplaySettings.defaultFontSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(segments) { segment in
                        plainRow(segment)
                            .id(segment.segmentID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onAppear {
                if let highlightSegmentID {
                    proxy.scrollTo(highlightSegmentID, anchor: .center)
                }
            }
        }
    }

    private func plainRow(_ segment: TranscriptSegment) -> some View {
        let isCurrent = segment.segmentID == currentSegmentID
        let isHighlighted = segment.segmentID == highlightSegmentID
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                onSelect(segment)
            } label: {
                Text(
                    "\(TimeFormatting.hms(segment.startSeconds)) - "
                        + TimeFormatting.hms(segment.endSeconds)
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("點擊跳到 \(TimeFormatting.hms(segment.startSeconds))")
            Text(segment.text)
                .font(.system(size: fontSize, weight: isCurrent ? .semibold : .regular))
                .lineSpacing(fontSize * 0.35)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8))
    }
}
