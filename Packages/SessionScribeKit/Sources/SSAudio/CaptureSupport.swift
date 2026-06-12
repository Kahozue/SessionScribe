import AVFoundation

/// 麥克風授權狀態查詢與請求（規格書第六節第 9 條）。
public enum MicrophonePermission {

    public enum Status: String, Equatable, Sendable {
        case undetermined
        case denied
        case restricted
        case authorized
    }

    public enum PermissionError: Error, Equatable {
        case denied
    }

    /// 系統設定的麥克風隱私頁，授權被拒時引導使用者開啟。
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    public static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .undetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .denied
        }
    }

    /// 觸發系統授權對話框；已決定過則直接回傳結果。
    public static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// 一個可選的音訊輸入裝置。
public struct AudioInputDevice: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 輸入裝置列舉（規格書第六節第 1 條）。
public enum AudioInputDevices {

    public static func available() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        return session.devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
}
