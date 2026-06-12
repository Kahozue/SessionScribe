import Foundation

// SSAudio：錄音擷取、CAF 分塊寫入、manifest 維護與音量量測。
// M2 實作 AudioCaptureService、ChunkedAudioWriter、AudioLevelMeter。

/// 音訊 chunk 的預設長度（秒）。崩潰時最多損失當前 chunk 的未寫入緩衝。
public enum AudioDefaults {
    public static let chunkDuration: TimeInterval = 300
}
