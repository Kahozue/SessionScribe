import AVFoundation
import Testing
@testable import SSAudio

@Suite("MicrophonePermission")
struct MicrophonePermissionTests {

    @Test("回報的授權狀態是四種已定義值之一")
    func statusIsWellDefined() {
        let status = MicrophonePermission.status
        #expect(
            [.undetermined, .denied, .restricted, .authorized].contains(status))
    }

    @Test("提供開啟系統設定麥克風頁的引導連結")
    func settingsLinkIsValid() {
        #expect(MicrophonePermission.settingsURL.scheme == "x-apple.systempreferences")
    }
}

@Suite("AudioInputDevices")
struct AudioInputDevicesTests {

    @Test("列舉輸入裝置不出錯，項目有非空 id 與名稱")
    func availableDevicesAreWellFormed() {
        let devices = AudioInputDevices.available()
        for device in devices {
            #expect(!device.id.isEmpty)
            #expect(!device.name.isEmpty)
        }
    }
}

@Suite("AudioCaptureService（不啟動引擎的部分）")
struct AudioCaptureServiceTests {

    @Test("未啟動即停止不出錯")
    func stopWithoutStartIsSafe() async {
        let service = AudioCaptureService()
        await service.stop()
    }

    @Test("可在啟動前取得 buffer 流")
    func bufferStreamAvailableBeforeStart() async {
        let service = AudioCaptureService()
        _ = await service.makeBufferStream()
        await service.stop()
    }
}
