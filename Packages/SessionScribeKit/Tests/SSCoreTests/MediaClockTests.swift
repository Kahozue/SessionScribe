import Testing
@testable import SSCore

@Suite("MediaClock")
struct MediaClockTests {

    @Test("初始為零秒")
    func startsAtZero() {
        let clock = MediaClock(sampleRate: 48000)
        #expect(clock.currentSeconds == 0)
    }

    @Test("依累計 frame 數換算秒數")
    func advanceAccumulatesFrames() {
        let clock = MediaClock(sampleRate: 48000)
        clock.advance(frames: 48000)
        #expect(clock.currentSeconds == 1.0)
        clock.advance(frames: 24000)
        #expect(clock.currentSeconds == 1.5)
    }

    @Test("pause 期間無 buffer 流入，時間自然停止")
    func timeFreezesWithoutBuffers() {
        let clock = MediaClock(sampleRate: 48000)
        clock.advance(frames: 96000)
        let beforePause = clock.currentSeconds
        // 模擬暫停：不餵任何 buffer，多次讀取值不變。
        #expect(clock.currentSeconds == beforePause)
        #expect(clock.currentSeconds == 2.0)
        // resume 後從暫停點繼續累計。
        clock.advance(frames: 48000)
        #expect(clock.currentSeconds == 3.0)
    }

    @Test("reset 歸零")
    func resetReturnsToZero() {
        let clock = MediaClock(sampleRate: 48000)
        clock.advance(frames: 48000)
        clock.reset()
        #expect(clock.currentSeconds == 0)
    }

    @Test("非 48kHz 取樣率換算正確")
    func respectsSampleRate() {
        let clock = MediaClock(sampleRate: 44100)
        clock.advance(frames: 44100)
        #expect(clock.currentSeconds == 1.0)
        clock.advance(frames: 22050)
        #expect(clock.currentSeconds == 1.5)
    }

    @Test("多執行緒同時 advance 不漏計")
    func concurrentAdvancesAllCounted() async {
        let clock = MediaClock(sampleRate: 48000)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { clock.advance(frames: 480) }
            }
        }
        #expect(clock.currentSeconds == 1.0)
    }
}
