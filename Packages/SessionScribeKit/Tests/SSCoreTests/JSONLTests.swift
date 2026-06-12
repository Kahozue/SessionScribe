import Foundation
import Testing
@testable import SSCore

private struct Record: Codable, Equatable {
    var id: Int
    var text: String
}

private func makeTempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "SSCoreTests-\(UUID().uuidString)")
        .appending(path: "test.jsonl")
}

@Suite("JSONLWriter")
struct JSONLWriterTests {

    @Test("每筆記錄寫入一行有效 JSON")
    func appendsOneLinePerRecord() throws {
        let url = makeTempFile()
        let writer = try JSONLWriter(url: url)
        try writer.append(Record(id: 1, text: "第一筆"))
        try writer.append(Record(id: 2, text: "第二筆"))
        try writer.close()

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n")
        #expect(lines.count == 2)
        for line in lines {
            #expect(throws: Never.self) {
                try SSJSON.decoder.decode(Record.self, from: Data(line.utf8))
            }
        }
    }

    @Test("append 後立即落盤，不等 close")
    func appendIsImmediatelyOnDisk() throws {
        let url = makeTempFile()
        let writer = try JSONLWriter(url: url)
        try writer.append(Record(id: 1, text: "a"))

        // writer 尚未 close，另開讀取應已看到該筆。
        let records = try JSONLReader.read(Record.self, from: url)
        #expect(records == [Record(id: 1, text: "a")])
        try writer.close()
    }

    @Test("自動建立檔案與中間目錄")
    func createsFileAndParentDirectories() throws {
        let url = makeTempFile()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let writer = try JSONLWriter(url: url)
        try writer.close()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("重新開啟既有檔案時從尾端續寫")
    func reopenAppendsToExistingFile() throws {
        let url = makeTempFile()
        let first = try JSONLWriter(url: url)
        try first.append(Record(id: 1, text: "a"))
        try first.close()

        let second = try JSONLWriter(url: url)
        try second.append(Record(id: 2, text: "b"))
        try second.close()

        let records = try JSONLReader.read(Record.self, from: url)
        #expect(records == [Record(id: 1, text: "a"), Record(id: 2, text: "b")])
    }
}

@Suite("JSONLReader")
struct JSONLReaderTests {

    @Test("容忍截斷的尾行（風險清單第 10 條）")
    func toleratesTruncatedLastLine() throws {
        let url = makeTempFile()
        let writer = try JSONLWriter(url: url)
        try writer.append(Record(id: 1, text: "完整"))
        try writer.append(Record(id: 2, text: "完整"))
        try writer.close()

        // 模擬斷電：尾端附加半截 JSON。
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"id": 3, "te"#.utf8))
        try handle.close()

        let records = try JSONLReader.read(Record.self, from: url)
        #expect(records == [Record(id: 1, text: "完整"), Record(id: 2, text: "完整")])
    }

    @Test("中段損毀行視為資料錯誤而拋錯")
    func throwsOnCorruptionInMiddle() throws {
        let url = makeTempFile()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = """
        {"id": 1, "text": "好"}
        這不是JSON
        {"id": 3, "text": "好"}
        """
        try Data(content.utf8).write(to: url)
        #expect(throws: (any Error).self) {
            try JSONLReader.read(Record.self, from: url)
        }
    }

    @Test("檔案不存在時回傳空陣列")
    func missingFileReturnsEmpty() throws {
        let url = makeTempFile()
        let records = try JSONLReader.read(Record.self, from: url)
        #expect(records.isEmpty)
    }

    @Test("空檔案回傳空陣列")
    func emptyFileReturnsEmpty() throws {
        let url = makeTempFile()
        let writer = try JSONLWriter(url: url)
        try writer.close()
        let records = try JSONLReader.read(Record.self, from: url)
        #expect(records.isEmpty)
    }
}
