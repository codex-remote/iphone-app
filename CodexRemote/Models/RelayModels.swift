import Foundation

enum ConnectionState: String, Sendable {
    case connecting
    case connected
    case disconnected

    var label: String {
        switch self {
        case .connecting: "LINKING"
        case .connected: "ONLINE"
        case .disconnected: "OFFLINE"
        }
    }
}

enum AgentState: String, Sendable {
    case offline
    case idle
    case running

    var label: String { rawValue.uppercased() }
}

enum TurnPhase: String, Sendable {
    case idle
    case running
    case completed
    case failed
    case interrupted

    var label: String { rawValue.uppercased() }
    var isTerminal: Bool { self == .completed || self == .failed || self == .interrupted }
}

enum LogStream: String, Sendable {
    case system
    case assistant
    case stdout
    case stderr

    var shortLabel: String {
        switch self {
        case .system: "SYS"
        case .assistant: "AI"
        case .stdout: "OUT"
        case .stderr: "ERR"
        }
    }
}

struct LogEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let stream: LogStream
    let text: String

    init(id: UUID = UUID(), timestamp: Date = Date(), stream: LogStream, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.stream = stream
        self.text = text
    }
}

struct ProjectSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let threadCount: Int
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, path
        case threadCount = "thread_count"
        case updatedAt = "updated_at"
    }
}

struct ThreadSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let projectID: String
    let title: String
    let preview: String
    let status: String
    let source: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, preview, status, source
        case projectID = "project_id"
        case updatedAt = "updated_at"
    }
}

struct TurnResult: Equatable, Sendable {
    let title: String
    let detail: String
    let changedFiles: Int
    let duration: TimeInterval
}

enum RelayEvent: Sendable {
    case connection(ConnectionState)
    case agent(name: String, state: AgentState)
    case projects([ProjectSummary])
    case threads(projectID: String, values: [ThreadSummary])
    case turnStarted(threadID: String, turnID: String, startedAt: Date)
    case output(LogEntry)
    case turnEnded(phase: TurnPhase, result: TurnResult)
    case reset
}

struct RelayEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    let specVersion: String
    let messageID: String
    let type: String
    let occurredAt: Date
    let traceID: String
    let sender: RelaySender
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case type, sender, payload
        case specVersion = "spec_version"
        case messageID = "message_id"
        case occurredAt = "occurred_at"
        case traceID = "trace_id"
    }
}

struct RelayEnvelopeHeader: Decodable {
    let specVersion: String
    let type: String
    let traceID: String

    enum CodingKeys: String, CodingKey {
        case type
        case specVersion = "spec_version"
        case traceID = "trace_id"
    }
}

struct RelaySender: Codable, Sendable {
    let kind: String
    let id: String
}

struct EmptyPayload: Codable, Sendable {}
struct ThreadListPayload: Codable, Sendable {
    let projectID: String
    enum CodingKeys: String, CodingKey { case projectID = "project_id" }
}
struct TurnStartPayload: Codable, Sendable {
    let projectID: String
    let threadID: String?
    let prompt: String
    enum CodingKeys: String, CodingKey {
        case prompt
        case projectID = "project_id"
        case threadID = "thread_id"
    }
}
struct TurnInterruptPayload: Codable, Sendable {
    let threadID: String
    let turnID: String
    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
    }
}

enum DemoScenario: String, CaseIterable, Identifiable {
    case idle
    case running
    case completed
    case failed
    case offline

    var id: Self { self }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .idle: "pause.circle"
        case .running: "waveform.path.ecg"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .offline: "wifi.slash"
        }
    }
}
