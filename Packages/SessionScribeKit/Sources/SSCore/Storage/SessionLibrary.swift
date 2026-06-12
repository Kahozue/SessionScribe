import Foundation

/// Session 列表與崩潰恢復掃描。掃描 root 目錄下每個含 metadata.json 的子目錄；
/// 散落檔案、缺 metadata 或 metadata 損毀的項目一律略過，不阻斷列表。
public struct SessionLibrary: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func directory(for sessionID: String) -> URL {
        rootDirectory.appending(path: sessionID)
    }

    /// 所有可讀取的 session，依 createdAt 由新到舊排序。
    public func sessions() throws -> [Session] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        let sessions = entries.compactMap { entry -> Session? in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return nil }
            return try? SessionMetadataFile.read(from: entry)
        }
        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    /// 批次指派分類（規格 1.1 第 7 項）：nil 即移回未分類。metadata 原子覆寫。
    public func assign(categoryID: String?, to sessionIDs: Set<String>) throws {
        for sessionID in sessionIDs {
            let dir = directory(for: sessionID)
            guard var session = try? SessionMetadataFile.read(from: dir) else { continue }
            session.categoryID = categoryID
            try SessionMetadataFile.write(session, to: dir)
        }
    }

    /// 批次刪除：優先移到垃圾桶（可復原），失敗時直接移除。
    public func delete(sessionIDs: Set<String>) throws {
        let fileManager = FileManager.default
        for sessionID in sessionIDs {
            let dir = directory(for: sessionID)
            guard fileManager.fileExists(atPath: dir.path) else { continue }
            do {
                try fileManager.trashItem(at: dir, resultingItemURL: nil)
            } catch {
                try fileManager.removeItem(at: dir)
            }
        }
    }

    /// 崩潰恢復掃描（規格書第二節決議 4）：`endedAt == nil` 且非進行中、
    /// 尚未標記過 recovered 的 session 視為崩潰殘留，標記 `recovered: true`
    /// 並原子落盤。回傳本次新標記的 session；已標記過的不重複回報（冪等）。
    public func recoverCrashedSessions(activeSessionIDs: Set<String> = []) throws -> [Session] {
        var recovered: [Session] = []
        for session in try sessions() {
            guard session.endedAt == nil,
                !session.recovered,
                !activeSessionIDs.contains(session.sessionID)
            else { continue }
            var marked = session
            marked.recovered = true
            try SessionMetadataFile.write(marked, to: directory(for: session.sessionID))
            recovered.append(marked)
        }
        return recovered
    }
}
