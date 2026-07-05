import SSUI
import SwiftUI

@main
struct SessionScribeApp: App {
    @State private var model = RecordingViewModel()
    @AppStorage(DisplaySettings.menuBarControlsEnabledKey)
    private var menuBarControlsEnabled = true

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(model: model)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .help) {
                OpenShortcutsButton()
            }
        }

        // 字幕浮層（規格 1.2）：無邊框透明、置頂、可拖曳，預設底部置中，與主視窗共用 model。
        Window("即時逐字稿", id: "floating-transcript") {
            CaptionOverlayView(model: model)
        }
        .windowStyle(.plain)
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultWindowPlacement { content, context in
            let bounds = context.defaultDisplay.visibleRect
            let size = content.sizeThatFits(.unspecified)
            let position = CGPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.maxY - size.height - 60)
            return WindowPlacement(position, size: size)
        }

        // 設定視窗（Cmd+,）：字級、外觀、引擎與 v0.2 起的設定，與主視窗共用 model。
        Settings {
            SettingsView(model: model)
        }

        // 選單列錄音控制：與主視窗共享同一個 model，
        // 開關關閉時 scene 不建立（isInserted）。
        MenuBarExtra(isInserted: $menuBarControlsEnabled) {
            MenuBarControlsView(model: model)
        } label: {
            MenuBarIconView(model: model)
        }
        .menuBarExtraStyle(.window)

        // 鍵盤快捷鍵總覽：說明選單開啟。
        Window("鍵盤快捷鍵", id: "shortcuts-overview") {
            ShortcutsOverviewView()
        }
        .windowResizability(.contentSize)
    }
}

private struct OpenShortcutsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("鍵盤快捷鍵") {
            openWindow(id: "shortcuts-overview")
        }
    }
}
