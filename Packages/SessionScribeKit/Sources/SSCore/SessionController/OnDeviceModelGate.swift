import Foundation

/// 序列化本機 LLM（SystemLanguageModel）請求。同時併發多個 respond 會有一個拋
/// generationFailed（模型不支援併發），故摘要、整理、生成草稿共用此閘門逐一執行。
/// run 為 nonisolated：operation 在呼叫端的隔離域執行（LanguageModelSession 非 Sendable
/// 不會跨 actor），只有 acquire/release 進入 actor 排隊。
public actor OnDeviceModelGate {
    public static let shared = OnDeviceModelGate()

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// 取得閘門後執行 operation，完成或拋錯都釋放，讓下一個請求接手。
    public nonisolated func run<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await operation()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }
}
