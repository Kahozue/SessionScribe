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

        // 浮動即時逐字稿（規格 1.1 第 1 項）：置頂、可調大小，與主視窗共用 model。
        Window("即時逐字稿", id: "floating-transcript") {
            FloatingTranscriptView(model: model)
        }
        .windowLevel(.floating)
        .defaultSize(width: 460, height: 320)
        .windowResizability(.contentMinSize)
    }
}
