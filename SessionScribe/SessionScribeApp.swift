import SSUI
import SwiftUI

@main
struct SessionScribeApp: App {
    @State private var model = RecordingViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .defaultSize(width: 1100, height: 720)

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
    }
}
