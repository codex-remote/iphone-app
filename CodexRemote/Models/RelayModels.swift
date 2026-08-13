import Foundation

enum ConnectionState: String, Sendable {
    case connecting
    case connected
    case disconnected
}

enum AgentState: String, Sendable {
    case offline
    case idle
    case running
}

enum TurnPhase: String, Sendable {
    case idle
    case running
    case completed
    case failed
    case interrupted

    var isTerminal: Bool { self == .completed || self == .failed || self == .interrupted }
}

enum LogStream: String, Sendable {
    case system
    case assistant
    case stdout
    case stderr
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
    let latestMessagePreview: String?
    let status: String
    let source: String
    let updatedAt: Date

    init(
        id: String,
        projectID: String,
        title: String,
        preview: String,
        latestMessagePreview: String? = nil,
        status: String,
        source: String,
        updatedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.preview = preview
        self.latestMessagePreview = latestMessagePreview
        self.status = status
        self.source = source
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, preview, status, source
        case latestMessagePreview = "latest_message_preview"
        case projectID = "project_id"
        case updatedAt = "updated_at"
    }

    var recentContentPreview: String {
        guard let latestMessagePreview,
              !latestMessagePreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return preview
        }
        return latestMessagePreview
    }
}

struct ThreadDetail: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let projectID: String
    let title: String
    let preview: String
    let status: String
    let source: String
    let createdAt: Date
    let updatedAt: Date
    let turns: [ThreadHistoryTurn]

    enum CodingKeys: String, CodingKey {
        case id, title, preview, status, source, turns
        case projectID = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ThreadHistoryTurn: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let status: String
    let startedAt: Date?
    let completedAt: Date?
    let durationMS: Int64?
    let error: String?
    let items: [ThreadHistoryItem]
    let truncated: Bool

    enum CodingKeys: String, CodingKey {
        case id, status, error, items, truncated
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMS = "duration_ms"
    }
}

struct ThreadHistoryItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var type: String
    var role: String?
    var phase: String?
    var status: String?
    var text: String?
    var name: String?
    var command: String?
    var cwd: String?
    var output: String?
    var path: String?
    var query: String?
    var exitCode: Int?
    var durationMS: Int64?
    var changes: [ThreadFileChange]?
    var truncated: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, role, phase, status, text, name, command, cwd, output, path, query, changes, truncated
        case exitCode = "exit_code"
        case durationMS = "duration_ms"
    }

    static func placeholder(id: String, field: String) -> ThreadHistoryItem {
        ThreadHistoryItem(
            id: id,
            type: field == "output" ? "commandExecution" : "activity",
            role: nil,
            phase: nil,
            status: "inProgress",
            text: nil,
            name: nil,
            command: nil,
            cwd: nil,
            output: nil,
            path: nil,
            query: nil,
            exitCode: nil,
            durationMS: nil,
            changes: nil,
            truncated: false
        )
    }
}

struct ThreadFileChange: Codable, Hashable, Sendable {
    let path: String
    let kind: String
    let diff: String?
}

struct TurnResult: Equatable, Sendable {
    let title: String
    let detail: String
    let changedFiles: Int
    let duration: TimeInterval
}

struct ExecutionCapabilities: Codable, Equatable, Sendable {
    let restricted: Bool
    let sandboxMode: String
    let approvalPolicy: String
    let writableScope: String
    let networkAccess: Bool
    let canRequestApproval: Bool
    let hostProcessControl: Bool
    let userLibraryWrite: Bool
    let xcodeDeviceControl: Bool
    let supportsPermissionProfiles: Bool?

    enum CodingKeys: String, CodingKey {
        case restricted
        case sandboxMode = "sandbox_mode"
        case approvalPolicy = "approval_policy"
        case writableScope = "writable_scope"
        case networkAccess = "network_access"
        case canRequestApproval = "can_request_approval"
        case hostProcessControl = "host_process_control"
        case userLibraryWrite = "user_library_write"
        case xcodeDeviceControl = "xcode_device_control"
        case supportsPermissionProfiles = "supports_permission_profiles"
    }
}

struct ExecutionProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let description: String?
    let allowed: Bool
}

struct ExecutionProfileSnapshot: Codable, Sendable {
    let projectID: String
    let defaultProfileID: String
    let profiles: [ExecutionProfile]

    enum CodingKeys: String, CodingKey {
        case profiles
        case projectID = "project_id"
        case defaultProfileID = "default_profile_id"
    }
}

enum RelayEvent: Sendable {
    case connection(ConnectionState)
    case agent(name: String, state: AgentState)
    case capabilities(ExecutionCapabilities?)
    case executionProfiles(ExecutionProfileSnapshot)
    case executionProfilesFailed(projectID: String, message: String)
    case projects([ProjectSummary])
    case projectsFailed(message: String)
    case threads(projectID: String, values: [ThreadSummary])
    case threadsFailed(projectID: String, message: String)
    case threadDetail(projectID: String, value: ThreadDetail, truncated: Bool)
    case threadDetailFailed(projectID: String, threadID: String, message: String)
    case turnStarted(threadID: String, turnID: String, startedAt: Date)
    case turnSnapshot(threadID: String, turnID: String, startedAt: Date, items: [ThreadHistoryItem], lastSequence: Int64, itemsTruncated: Bool, recentOutput: [String])
    case turnItemStarted(turnID: String, sequence: Int64, item: ThreadHistoryItem)
    case turnItemDelta(turnID: String, sequence: Int64, itemID: String, field: String, delta: String)
    case turnItemCompleted(turnID: String, sequence: Int64, item: ThreadHistoryItem)
    case output(LogEntry)
    case turnEnded(traceID: String?, turnID: String?, phase: TurnPhase, result: TurnResult?)
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
struct ExecutionProfileListPayload: Codable, Sendable {
    let projectID: String
    enum CodingKeys: String, CodingKey { case projectID = "project_id" }
}
struct ThreadReadPayload: Codable, Sendable {
    let projectID: String
    let threadID: String
    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case threadID = "thread_id"
    }
}
struct TurnStartPayload: Codable, Sendable {
    let projectID: String
    let threadID: String?
    let prompt: String
    let permissionProfileID: String?
    enum CodingKeys: String, CodingKey {
        case prompt
        case projectID = "project_id"
        case threadID = "thread_id"
        case permissionProfileID = "permission_profile_id"
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

struct TurnAcknowledgedPayload: Codable, Sendable {
    let turnID: String
    let status: String
    enum CodingKeys: String, CodingKey {
        case status
        case turnID = "turn_id"
    }
}
