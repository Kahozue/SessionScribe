import Foundation

/// App 版本資訊（設定頁「關於」顯示用）。從 main bundle 的 Info.plist 讀取，
/// 因此 Xcode 執行與 DMG 發行版都顯示各自建置時的 MARKETING_VERSION。
public enum AppVersion {
    /// 組合顯示字串：「0.3.0 (1)」；build 缺漏或與版本相同時只顯示版本，版本缺漏回 nil。
    public static func displayString(short: String?, build: String?) -> String? {
        guard let short, !short.isEmpty else { return nil }
        guard let build, !build.isEmpty, build != short else { return short }
        return "\(short) (\(build))"
    }

    /// 目前執行中 app 的版本字串；非 app bundle 環境（單元測試）可能為 nil。
    public static var current: String? {
        let info = Bundle.main.infoDictionary
        return displayString(
            short: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String)
    }
}
