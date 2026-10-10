import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): String(value)
        case .bool(let value): String(value)
        default: nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case .number(let value): Int64(value)
        case .string(let value): Int64(value)
        default: nil
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

struct RuntimeEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let data: Value
}

struct RuntimeErrorEnvelope: Decodable, Sendable {
    struct Failure: Decodable, Sendable {
        let code: String
        let message: String
        let retryable: Bool?
    }

    let success: Bool
    let error: Failure
}

struct RuntimeProject: Codable, Sendable {
    let projectID: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case displayName = "display_name"
    }
}

struct RuntimeProjectList: Decodable, Sendable {
    let items: [RuntimeProject]
    let agentPresence: String

    enum CodingKeys: String, CodingKey {
        case items
        case agentPresence = "agent_presence"
    }
}

struct RuntimeSession: Codable, Sendable {
    let sessionID: String
    let projectID: String
    let codexThreadID: String?
    let title: String
    let lastSessionSequence: Int64
    let latestRunStatus: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case title
        case sessionID = "session_id"
        case projectID = "project_id"
        case codexThreadID = "codex_thread_id"
        case lastSessionSequence = "last_session_sequence"
        case latestRunStatus = "latest_run_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RuntimeSessionList: Decodable, Sendable {
    let items: [RuntimeSession]
}

struct RuntimeRunEvent: Codable, Sendable {
    let agentSequence: Int64
    let type: String
    let payload: [String: JSONValue]
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case type, payload
        case agentSequence = "agent_sequence"
        case occurredAt = "occurred_at"
    }
}

struct RuntimeRun: Codable, Sendable {
    let runID: String
    let sessionID: String
    let status: String
    let stateVersion: Int64
    let prompt: String?
    let permissionProfileID: String?
    let persistedThroughSequence: Int64
    let finalSequence: Int64?
    let errorMessage: String?
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let updatedAt: Date
    let events: [RuntimeRunEvent]?

    enum CodingKeys: String, CodingKey {
        case status, prompt, events
        case runID = "run_id"
        case sessionID = "session_id"
        case stateVersion = "state_version"
        case permissionProfileID = "permission_profile_id"
        case persistedThroughSequence = "persisted_through_sequence"
        case finalSequence = "final_sequence"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case updatedAt = "updated_at"
    }
}

struct RuntimeSessionSnapshot: Decodable, Sendable {
    let session: RuntimeSession
    let runs: [RuntimeRun]
    let snapshotSessionSequence: Int64
    let agentPresence: String

    enum CodingKeys: String, CodingKey {
        case session, runs
        case snapshotSessionSequence = "snapshot_session_sequence"
        case agentPresence = "agent_presence"
    }
}

struct RuntimeCreatedRun: Decodable, Sendable {
    let runID: String
    let sessionID: String
    let status: String
    let sessionSequence: Int64
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case runID = "run_id"
        case sessionID = "session_id"
        case sessionSequence = "session_sequence"
        case createdAt = "created_at"
    }
}

struct RuntimeSyncJob: Decodable, Sendable {
    let syncID: String
    let status: String
    let processedSessions: Int64
    let totalSessions: Int64
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case status
        case syncID = "sync_id"
        case processedSessions = "processed_sessions"
        case totalSessions = "total_sessions"
        case errorMessage = "error_message"
    }
}

struct RuntimeStreamEvent: Sendable {
    let id: Int64
    let type: String
    let fields: [String: JSONValue]

    var runID: String? { fields["run_id"]?.stringValue ?? fields["runId"]?.stringValue }
}

enum RuntimeAuthenticationState: Equatable, Sendable {
    case checking
    case pairing
    case authenticated(clientName: String)
    case unauthenticated(message: String?)
    case unavailable(message: String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

struct RuntimeAuthClient: Codable, Sendable {
    let clientID: String
    let name: String
    let scopes: [String]

    enum CodingKeys: String, CodingKey {
        case name, scopes
        case clientID = "client_id"
    }
}

struct RuntimeNativeTokenPair: Decodable, Sendable {
    let accessToken: String
    let accessExpiresAt: Date
    let refreshToken: String
    let refreshExpiresAt: Date
    let client: RuntimeAuthClient

    enum CodingKeys: String, CodingKey {
        case client
        case accessToken = "access_token"
        case accessExpiresAt = "access_expires_at"
        case refreshToken = "refresh_token"
        case refreshExpiresAt = "refresh_expires_at"
    }
}

extension RuntimeSession {
    func threadSummary() -> ThreadSummary {
        ThreadSummary(
            id: sessionID,
            projectID: projectID,
            title: title,
            preview: "",
            status: normalizedRuntimeStatus(latestRunStatus),
            source: "runtime",
            updatedAt: updatedAt
        )
    }
}

extension RuntimeSessionSnapshot {
    func threadDetail(excludingRunID: String? = nil) -> ThreadDetail {
        ThreadDetail(
            id: session.sessionID,
            projectID: session.projectID,
            title: session.title,
            preview: "",
            status: normalizedRuntimeStatus(session.latestRunStatus),
            source: "runtime",
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            turns: runs.filter { $0.runID != excludingRunID }.map { $0.threadHistoryTurn() }
        )
    }
}

extension RuntimeRun {
    func threadHistoryTurn() -> ThreadHistoryTurn {
        var items: [ThreadHistoryItem] = []
        if let prompt, !prompt.isEmpty {
            items.append(runtimeItem(id: "user-\(runID)", type: "userMessage", role: "user", text: prompt))
        }
        var assistantID = "assistant-\(runID)"
        var assistantText = ""
        for event in events ?? [] {
            switch event.type {
            case "assistant.delta":
                assistantText += event.payload["text"]?.stringValue ?? event.payload["delta"]?.stringValue ?? ""
            case "item.started", "item.completed":
                guard let value = event.payload["item"] else { continue }
                if let item = decodeHistoryItem(value) {
                    if item.type == "agentMessage", item.phase == nil || item.phase == "final_answer" {
                        assistantID = item.id
                        if event.type == "item.completed", let text = item.text { assistantText = text }
                    } else {
                        upsert(item, in: &items)
                    }
                }
            case "item.delta":
                let itemID = event.payload["item_id"]?.stringValue ?? ""
                if itemID == assistantID, event.payload["field"]?.stringValue == "text" {
                    assistantText += event.payload["delta"]?.stringValue ?? ""
                }
            default:
                break
            }
        }
        if !assistantText.isEmpty || status == "failed" {
            items.append(runtimeItem(
                id: assistantID,
                type: "agentMessage",
                role: "assistant",
                phase: "final_answer",
                text: assistantText.isEmpty ? errorMessage : assistantText
            ))
        }
        return ThreadHistoryTurn(
            id: runID,
            status: normalizedRuntimeStatus(status),
            startedAt: startedAt ?? createdAt,
            completedAt: finishedAt,
            durationMS: durationMilliseconds,
            error: errorMessage,
            items: items,
            truncated: false
        )
    }

    private var durationMilliseconds: Int64? {
        guard let end = finishedAt, let start = startedAt else { return nil }
        return Int64(max(0, end.timeIntervalSince(start) * 1_000))
    }
}

func normalizedRuntimeStatus(_ status: String?) -> String {
    switch status {
    case "queued", "dispatching", "accepted", "running", "waiting_agent", "recovering", "finalizing": "running"
    case "canceled": "interrupted"
    case "failed": "failed"
    default: "completed"
    }
}

func decodeHistoryItem(_ value: JSONValue) -> ThreadHistoryItem? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(ThreadHistoryItem.self, from: data)
}

private func runtimeItem(
    id: String,
    type: String,
    role: String? = nil,
    phase: String? = nil,
    text: String? = nil
) -> ThreadHistoryItem {
    ThreadHistoryItem(
        id: id, type: type, role: role, phase: phase, status: nil, text: text,
        name: nil, command: nil, cwd: nil, output: nil, path: nil, query: nil,
        exitCode: nil, durationMS: nil, changes: nil, truncated: false
    )
}

private func upsert(_ item: ThreadHistoryItem, in items: inout [ThreadHistoryItem]) {
    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    else { items.append(item) }
}
