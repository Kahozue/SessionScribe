import Testing

@testable import SSUI

@Suite("AppVersion")
struct AppVersionTests {

    @Test("版本加 build 組合為「版本 (build)」")
    func combinesShortAndBuild() {
        #expect(AppVersion.displayString(short: "0.3.0", build: "1") == "0.3.0 (1)")
    }

    @Test("build 缺漏或與版本相同時只顯示版本")
    func fallsBackToShortOnly() {
        #expect(AppVersion.displayString(short: "0.3.0", build: nil) == "0.3.0")
        #expect(AppVersion.displayString(short: "0.3.0", build: "") == "0.3.0")
        #expect(AppVersion.displayString(short: "0.3.0", build: "0.3.0") == "0.3.0")
    }

    @Test("版本缺漏回 nil，不顯示空字串")
    func nilWhenShortMissing() {
        #expect(AppVersion.displayString(short: nil, build: "1") == nil)
        #expect(AppVersion.displayString(short: "", build: "1") == nil)
    }
}
