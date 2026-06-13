import Foundation

/// 雲端事件整理：行為對齊本機 EventOrganizer，差別只在用雲端 LLM 取結構化 JSON。
/// 重用 EventOrganizer 的 instructions 與 applyOrganized/buildEvent，確保可靠性邏輯一致。
public struct CloudEventOrganizer: EventOrganizing {
    let client: CloudLLMClient
    public init(client: CloudLLMClient) { self.client = client }

    private struct OrganizedJSON: Decodable {
        var topic: String?; var type: String?; var priority: String?
        var speakerRole: String?; var responseSummary: String?; var actionItem: String?
        var tags: [String]?
    }
    private struct GeneratedJSON: Decodable { var events: [GeneratedEventJSON] }
    private struct GeneratedEventJSON: Decodable {
        var topic: String?; var type: String?; var priority: String?
        var speakerRole: String?; var responseSummary: String?; var actionItem: String?
        var tags: [String]?; var startSeconds: Double?; var endSeconds: Double?
    }

    private static let organizeSchema = """

        請只輸出 JSON 物件，鍵為：topic、type、priority（high/medium/low）、speakerRole、
        responseSummary、actionItem、tags（字串陣列）。無法判斷的欄位給空字串或空陣列。
        """
    private static let generateSchema = """

        請只輸出 JSON 物件 {"events":[...]}，每個 event 的鍵為：topic、type、
        priority（high/medium/low）、speakerRole、responseSummary、actionItem、
        tags（字串陣列）、startSeconds（整數秒）、endSeconds（整數秒）。
        """

    public func organize(_ events: [StructuredEvent], locale: Locale,
                         progress: @Sendable (Double) -> Void) async throws -> [StructuredEvent] {
        var result: [StructuredEvent] = []
        result.reserveCapacity(events.count)
        for (index, event) in events.enumerated() {
            let prompt = "以下是某個標記前後的逐字稿片段，請依指示整理成結構化欄位：\n\n\(event.content)"
            let reply = try await client.complete(
                system: EventOrganizer.instructions + Self.organizeSchema, user: prompt)
            let json = try JSONExtraction.firstJSONValue(in: reply)
            let fields = try Self.decode(OrganizedJSON.self, from: json)
            result.append(EventOrganizer.applyOrganized(
                topic: fields.topic ?? "", type: fields.type ?? "", priority: fields.priority ?? "",
                speakerRole: fields.speakerRole ?? "", responseSummary: fields.responseSummary ?? "",
                actionItem: fields.actionItem ?? "", tags: fields.tags ?? [], to: event))
            progress(Double(index + 1) / Double(max(events.count, 1)))
        }
        return result
    }

    public func generateEvents(from segments: [TranscriptSegment], sessionID: String,
                               locale: Locale) async throws -> [StructuredEvent] {
        let finals = segments.filter(\.isFinal).sorted { $0.startSeconds < $1.startSeconds }
        guard !finals.isEmpty else { return [] }
        let transcript = finals
            .map { "[\(Int($0.startSeconds))-\(Int($0.endSeconds))] \($0.text)" }
            .joined(separator: "\n")
        let prompt = "以下是一段帶秒數區間的逐字稿，請切分成數個事件並整理：\n\n\(transcript)"
        let reply = try await client.complete(
            system: EventOrganizer.generateInstructions + Self.generateSchema, user: prompt)
        let json = try JSONExtraction.firstJSONValue(in: reply)
        let decoded = try Self.decode(GeneratedJSON.self, from: json)
        let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        return decoded.events.enumerated().map { index, gen in
            EventOrganizer.buildEvent(
                index: index, topic: gen.topic ?? "", type: gen.type ?? "",
                priority: gen.priority ?? "", speakerRole: gen.speakerRole ?? "",
                responseSummary: gen.responseSummary ?? "", actionItem: gen.actionItem ?? "",
                tags: gen.tags ?? [], startSeconds: gen.startSeconds ?? 0,
                endSeconds: gen.endSeconds ?? 0, segments: finals,
                sessionID: sessionID, createdAt: createdAt)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw CloudLLMError.malformedResponse("JSON 欄位無法對應")
        }
        return value
    }
}
