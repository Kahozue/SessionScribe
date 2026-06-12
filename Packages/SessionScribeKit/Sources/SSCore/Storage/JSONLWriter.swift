import Foundation

/// append-only JSONL 寫入器：每筆記錄編碼為單行 JSON，寫入後立即 fsync，
/// 確保 finalized segment 與 manual marker 增量落盤（核心可靠性原則 6、7）。
public final class JSONLWriter {
    public let url: URL
    private let handle: FileHandle

    /// 開啟（必要時建立）檔案並定位到尾端，後續 append 一律續寫。
    public init(url: URL) throws {
        self.url = url
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        self.handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    public func append<T: Encodable>(_ record: T) throws {
        var line = try SSJSON.lineEncoder.encode(record)
        line.append(UInt8(ascii: "\n"))
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    public func close() throws {
        try handle.close()
    }

    deinit {
        try? handle.close()
    }
}

/// JSONL 讀取器。容忍截斷的尾行（崩潰或斷電時最後一筆可能寫到一半，
/// 風險清單第 10 條）；中段損毀行視為資料錯誤拋出。
public enum JSONLReader {

    public enum ReadError: Error {
        case corruptedLine(lineNumber: Int, underlying: any Error)
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        var records: [T] = []
        for (index, line) in lines.enumerated() {
            do {
                records.append(try SSJSON.decoder.decode(T.self, from: line))
            } catch where index == lines.count - 1 {
                break
            } catch {
                throw ReadError.corruptedLine(lineNumber: index + 1, underlying: error)
            }
        }
        return records
    }
}
