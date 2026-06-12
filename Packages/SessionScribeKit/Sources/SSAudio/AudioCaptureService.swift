import AVFoundation
import CoreAudio
import Synchronization

/// tap 回呼產出的一顆 buffer。每次 yield 前深拷貝，消費者取得獨佔所有權，
/// 故可安全跨隔離傳遞；除此之外不得共享 AVAudioPCMBuffer。
public struct CapturedBuffer: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public var frames: Int { Int(buffer.frameLength) }

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

/// 把 tap 回呼的 buffer 分發給多個獨立消費者（架構文件：錄音寫入與 ASR 解耦，
/// 任一方失敗不影響另一方）。每個消費者收到自己的拷貝。
final class BufferDistributor: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<CapturedBuffer>.Continuation]>([:])

    func makeStream() -> AsyncStream<CapturedBuffer> {
        AsyncStream { continuation in
            let id = UUID()
            continuations.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.continuations.withLock { $0.removeValue(forKey: id) }
            }
        }
    }

    /// 自音訊執行緒呼叫：對每個消費者 yield 一份深拷貝。
    func distribute(_ buffer: AVAudioPCMBuffer) {
        let targets = continuations.withLock { Array($0.values) }
        guard !targets.isEmpty else { return }
        for continuation in targets {
            guard let copy = buffer.deepCopy() else { continue }
            continuation.yield(CapturedBuffer(buffer: copy))
        }
    }

    func finishAll() {
        let targets = continuations.withLock { state in
            defer { state.removeAll() }
            return Array(state.values)
        }
        for continuation in targets {
            continuation.finish()
        }
    }
}

extension AVAudioPCMBuffer {
    /// 深拷貝：tap 的 buffer 由引擎重複使用，yield 前必須複製。
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        copy.frameLength = frameLength
        let source = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (sourceBuffer, destinationBuffer) in zip(source, destination) {
            guard let sourceData = sourceBuffer.mData, let destinationData = destinationBuffer.mData
            else { continue }
            memcpy(
                destinationData, sourceData,
                Int(min(sourceBuffer.mDataByteSize, destinationBuffer.mDataByteSize)))
        }
        return copy
    }
}

/// AVAudioEngine 麥克風擷取：input tap 取得 buffer 流，分發給消費者。
/// 引擎啟動需要麥克風授權與實機硬體，屬整合測試範圍。
public actor AudioCaptureService {

    public enum CaptureError: Error {
        case deviceNotFound
        case audioUnitUnavailable
        case coreAudioError(OSStatus)
    }

    private var engine: AVAudioEngine?
    private let distributor = BufferDistributor()

    public init() {}

    /// 訂閱 buffer 流。可在啟動前訂閱；stop 時結束。
    public func makeBufferStream() -> AsyncStream<CapturedBuffer> {
        distributor.makeStream()
    }

    /// 啟動擷取，回傳輸入格式（消費者據此建立 writer 與 MediaClock）。
    @discardableResult
    public func start(deviceUID: String? = nil) throws -> AVAudioFormat {
        let engine = AVAudioEngine()
        if let deviceUID {
            try Self.setInputDevice(uid: deviceUID, on: engine)
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        let distributor = self.distributor
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            distributor.distribute(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        return format
    }

    /// 暫停：引擎停轉，無 buffer 流出，媒體時間自然停止。
    public func pause() {
        engine?.pause()
    }

    public func resume() throws {
        try engine?.start()
    }

    public func stop() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        distributor.finishAll()
    }

    // MARK: - 輸入裝置選擇（CoreAudio）

    private static func setInputDevice(uid: String, on engine: AVAudioEngine) throws {
        var deviceID = try deviceID(forUID: uid)
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw CaptureError.audioUnitUnavailable
        }
        let status = AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw CaptureError.coreAudioError(status)
        }
    }

    private static func deviceID(forUID uid: String) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var uidCF = uid as CFString
        let status = withUnsafeMutablePointer(to: &uidCF) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), uidPointer,
                &size, &deviceID)
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw CaptureError.deviceNotFound
        }
        return deviceID
    }
}
