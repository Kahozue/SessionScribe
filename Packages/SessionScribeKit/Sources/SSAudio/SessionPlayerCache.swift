import Foundation

/// session 播放器快取：同一個 session 重複進出檢視頁時沿用同一個播放器，
/// 播放狀態與進度不中斷（檢視頁切換不歸零）；播放新的 session 前
/// 由 UI 呼叫 `pauseAll(except:)` 確保同一時間只播一個。
@MainActor
public final class SessionPlayerCache {
    public static let shared = SessionPlayerCache()

    private var players: [URL: SessionPlayer] = [:]

    private init() {}

    /// 取出或建立指定音訊資料夾的播放器；沒有可播放音訊時拋錯。
    public func player(for audioDirectory: URL) throws -> SessionPlayer {
        let key = audioDirectory.standardizedFileURL
        if let existing = players[key] {
            return existing
        }
        let player = try SessionPlayer(audioDirectory: audioDirectory)
        players[key] = player
        return player
    }

    /// 暫停除指定者外的所有播放器。
    public func pauseAll(except keep: SessionPlayer? = nil) {
        for player in players.values where player !== keep {
            player.pause()
        }
    }

    /// 移除播放器（session 刪除時呼叫），先停止播放。
    public func remove(audioDirectory: URL) {
        players.removeValue(forKey: audioDirectory.standardizedFileURL)?.stop()
    }
}
