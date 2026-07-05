import SwiftUI

/// 首次啟動的三步輕量導覽（spec 第七節第 6 項）：
/// 錄音與權限、標記快捷鍵、Local Only 隱私。
/// 質感對齊系統設定的簡潔，不做插畫堆疊；步進動畫過 Reduce Motion 降級。
struct OnboardingSheet: View {
    @AppStorage(DisplaySettings.onboardingCompletedKey)
    private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    private struct Page {
        let symbol: String
        let title: String
        let message: String
    }

    private let pages: [Page] = [
        Page(
            symbol: "mic.fill",
            title: "開始錄音",
            message: "按工具列的錄音鈕開始，第一次會請求麥克風權限。原始錄音永遠優先：轉寫失敗不影響錄音與已保存的資料。"),
        Page(
            symbol: "bookmark.fill",
            title: "單鍵標記",
            message: "錄音中按 Q、R、S、A 或 Cmd+1 至 4，零確認步驟記下重要時刻。四鍵語意跟著場景模板切換。"),
        Page(
            symbol: "lock.shield.fill",
            title: "預設只在本機",
            message: "錄音與逐字稿只存在你的 Mac，轉寫與 AI 整理用本機模型。除非你在設定裡為某功能選擇雲端，不會建立任何連線。"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: pages[step].symbol)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .frame(height: 56)
            Text(pages[step].title)
                .appFont(.title2, weight: .bold)
            Text(pages[step].message)
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 64, alignment: .top)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Button {
                if step < pages.count - 1 {
                    if reduceMotion {
                        step += 1
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                    }
                } else {
                    completed = true
                }
            } label: {
                Text(step < pages.count - 1 ? "繼續" : "開始使用")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("略過") {
                completed = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 400)
        .appTypography()
        .interactiveDismissDisabled(false)
    }
}
