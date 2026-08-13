import Foundation

enum RelayClientError: Error {
    case invalidUTF8
}

enum RelayConnectionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid ws:// or wss:// Relay URL."
        case .invalidResponse:
            "Relay returned an invalid status response."
        case .httpStatus(let statusCode):
            "Relay status check returned HTTP \(statusCode)."
        }
    }
}

struct RelayHTTPStatus: Decodable {
    let agentConnected: Bool

    enum CodingKeys: String, CodingKey {
        case agentConnected = "agent_connected"
    }
}

struct AgentHelloPayload: Codable, Sendable { let name: String; let version: String; let status: String }
struct AgentStatusPayload: Codable, Sendable { let status: String }
struct ProjectSnapshotPayload: Codable, Sendable { let projects: [ProjectSummary] }

struct ThreadSnapshotPayload: Codable, Sendable {
    let projectID: String
    let threads: [ThreadSummary]
    enum CodingKeys: String, CodingKey { case threads; case projectID = "project_id" }
}

struct ThreadDetailEventPayload: Codable, Sendable {
    let projectID: String
    let thread: ThreadDetail
    let truncated: Bool
    enum CodingKeys: String, CodingKey { case thread, truncated; case projectID = "project_id" }
}

struct TurnStartedEventPayload: Codable, Sendable {
    let threadID: String; let turnID: String; let startedAt: Date
    enum CodingKeys: String, CodingKey { case threadID = "thread_id"; case turnID = "turn_id"; case startedAt = "started_at" }
}

struct TurnOutputEventPayload: Codable, Sendable { let stream: String; let text: String }

struct TurnItemStartedEventPayload: Codable, Sendable {
    let turnID: String
    let sequence: Int64
    let item: ThreadHistoryItem
    enum CodingKeys: String, CodingKey { case sequence, item; case turnID = "turn_id" }
}

struct TurnItemDeltaEventPayload: Codable, Sendable {
    let turnID: String
    let sequence: Int64
    let itemID: String
    let field: String
    let delta: String
    enum CodingKeys: String, CodingKey { case sequence, field, delta; case turnID = "turn_id"; case itemID = "item_id" }
}

struct TurnItemCompletedEventPayload: Codable, Sendable {
    let turnID: String
    let sequence: Int64
    let item: ThreadHistoryItem
    enum CodingKeys: String, CodingKey { case sequence, item; case turnID = "turn_id" }
}

struct TurnSnapshotEventPayload: Codable, Sendable {
    let threadID: String
    let turnID: String
    let startedAt: Date
    let recentOutput: [String]
    let liveItems: [ThreadHistoryItem]?
    let lastSequence: Int64?
    let liveItemsTruncated: Bool?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case startedAt = "started_at"
        case recentOutput = "recent_output"
        case liveItems = "live_items"
        case lastSequence = "last_sequence"
        case liveItemsTruncated = "live_items_truncated"
    }
}

struct TurnCompletedEventPayload: Codable, Sendable {
    let turnID: String; let durationMS: Int64; let summary: String; let changedFiles: [String]
    enum CodingKeys: String, CodingKey { case summary; case turnID = "turn_id"; case durationMS = "duration_ms"; case changedFiles = "changed_files" }
}

struct TurnFailedEventPayload: Codable, Sendable {
    let turnID: String?; let code: String; let message: String; let durationMS: Int64?
    enum CodingKeys: String, CodingKey { case code, message; case turnID = "turn_id"; case durationMS = "duration_ms" }
}

struct TurnInterruptedEventPayload: Codable, Sendable {
    let turnID: String?; let durationMS: Int64
    enum CodingKeys: String, CodingKey { case turnID = "turn_id"; case durationMS = "duration_ms" }
}

struct TurnRejectedEventPayload: Codable, Sendable {
    let code: String
    let message: String
    let requiredCapabilities: [String]?
    let recoveryAction: String?
    let executionContext: ExecutionCapabilities?

    enum CodingKeys: String, CodingKey {
        case code, message
        case requiredCapabilities = "required_capabilities"
        case recoveryAction = "recovery_action"
        case executionContext = "execution_context"
    }
}

extension JSONEncoder {
    static var relay: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var relay: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = RelayDateParser.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid RFC3339 timestamp: \(rawValue)"
            )
        }
        return decoder
    }
}

private enum RelayDateParser {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func date(from value: String) -> Date? {
        (try? withFraction.parse(value)) ?? (try? withoutFraction.parse(value))
    }
}
