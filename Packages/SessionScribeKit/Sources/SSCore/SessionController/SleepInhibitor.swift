import Foundation
import Synchronization

/// 以 ProcessInfo activity assertion 阻止系統 idle sleep（規格書決議 7）。
/// 錄音開始時 begin、停止時 end；重複 begin 不疊加 assertion。
public final class SleepInhibitor: SleepInhibiting, Sendable {
    private let token = Mutex<NSObjectProtocol?>(nil)

    public init() {}

    public var isActive: Bool {
        token.withLock { $0 != nil }
    }

    public func begin(reason: String) {
        token.withLock { current in
            guard current == nil else { return }
            current = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled, reason: reason)
        }
    }

    public func end() {
        let held = token.withLock { current -> NSObjectProtocol? in
            defer { current = nil }
            return current
        }
        if let held {
            ProcessInfo.processInfo.endActivity(held)
        }
    }

    deinit {
        end()
    }
}
