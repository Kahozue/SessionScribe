import Foundation
import Testing
@testable import SSCore

@Suite("Waveform")
struct WaveformTests {

    @Test("bin 數規則：每秒 10 bins、上限 2000、至少 1")
    func binCountRule() {
        #expect(Waveform.binCount(forDuration: 0.01) == 1)
        #expect(Waveform.binCount(forDuration: 3) == 30)
        #expect(Waveform.binCount(forDuration: 199.91) == 2000)
        #expect(Waveform.binCount(forDuration: 200) == 2000)
        #expect(Waveform.binCount(forDuration: 7200) == 2000)
    }

    @Test("waveform.json round-trip 與 snake_case 鍵名")
    func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WaveformTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let waveform = Waveform(durationSeconds: 3, rms: [0.1, 0.2], peak: [0.3, 0.5])
        try WaveformFile.write(waveform, to: directory)
        let loaded = try WaveformFile.readIfPresent(from: directory)
        #expect(loaded == waveform)
        let raw = try String(contentsOf: WaveformFile.url(in: directory), encoding: .utf8)
        #expect(raw.contains("\"schema_version\""))
        #expect(raw.contains("\"duration_seconds\""))
    }

    @Test("檔案不存在回 nil")
    func missingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WaveformTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(try WaveformFile.readIfPresent(from: directory) == nil)
    }
}
