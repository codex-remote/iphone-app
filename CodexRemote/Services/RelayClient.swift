import Foundation

@MainActor
final class RelayClient: RelayServiceProtocol {
    private static let specVersion = "2.0"
    private static let defaultURL = "ws://192.168.68.125:8080/ws/app"

    private var continuation: AsyncStream<RelayEvent>.Continuation?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var relayURL: String
    private var reconnectAutomatically: Bool
    private var activeTraceID: String?
    private var activeThreadID: String?
    private var activeTurnID: String?
    private var agentName = "Mac Agent"

    private let encoder = JSONEncoder.relay
    private let decoder = JSONDecoder.relay

    init() {
        relayURL = UserDefaults.standard.string(forKey: "relayURL") ?? Self.defaultURL
        reconnectAutomatically = UserDefaults.standard.object(forKey: "reconnectAutomatically") as? Bool ?? true
    }

    func events() -> AsyncStream<RelayEvent> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    func connect() async {
        receiveTask?.cancel()
        reconnectTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        emit(.connection(.connecting))
        guard let url = URL(string: relayURL), ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else {
            emit(.connection(.disconnected))
            emit(.output(LogEntry(stream: .system, text: "Relay URL is invalid.")))
            return
        }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        emit(.connection(.connected))
        receiveTask = Task { @MainActor [weak self, weak task] in
            guard let self, let task else { return }
            await receiveLoop(task)
        }
        await requestProjects()
    }

    func configure(url: String, reconnectAutomatically: Bool) async {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = normalized != relayURL
        relayURL = normalized
        self.reconnectAutomatically = reconnectAutomatically
        UserDefaults.standard.set(normalized, forKey: "relayURL")
        UserDefaults.standard.set(reconnectAutomatically, forKey: "reconnectAutomatically")
        if changed { await connect() }
    }

    func requestProjects() async {
        await send(type: "project.list", traceID: newID(), payload: EmptyPayload())
    }

    func requestThreads(projectID: String) async {
        await send(type: "thread.list", traceID: newID(), payload: ThreadListPayload(projectID: projectID))
    }

    func startTurn(projectID: String, threadID: String?, prompt: String) async {
        let traceID = newID()
        activeTraceID = traceID
        activeThreadID = threadID
        activeTurnID = nil
        await send(type: "turn.start", traceID: traceID, payload: TurnStartPayload(projectID: projectID, threadID: threadID, prompt: prompt))
    }

    func interruptTurn() async {
        guard let traceID = activeTraceID, let threadID = activeThreadID, let turnID = activeTurnID else {
            emit(.output(LogEntry(stream: .system, text: "Codex has not started the turn yet.")))
            return
        }
        await send(type: "turn.interrupt", traceID: traceID, payload: TurnInterruptPayload(threadID: threadID, turnID: turnID))
    }

    func loadScenario(_: DemoScenario) async {}

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                handle(data)
            }
        } catch {
            guard !Task.isCancelled else { return }
            emit(.connection(.disconnected))
            emit(.agent(name: agentName, state: .offline))
            emit(.output(LogEntry(stream: .system, text: "Relay connection ended: \(error.localizedDescription)")))
            scheduleReconnect()
        }
    }

    private func handle(_ data: Data) {
        guard let header = try? decoder.decode(RelayEnvelopeHeader.self, from: data), header.specVersion == Self.specVersion else {
            emit(.output(LogEntry(stream: .system, text: "Relay sent an unsupported message.")))
            return
        }
        switch header.type {
        case "agent.hello":
            if let payload: AgentHelloPayload = payload(data) {
                agentName = payload.name
                emit(.agent(name: payload.name, state: AgentState(rawValue: payload.status) ?? .idle))
            }
        case "agent.status":
            if let payload: AgentStatusPayload = payload(data) {
                emit(.agent(name: agentName, state: AgentState(rawValue: payload.status) ?? .offline))
            }
        case "project.snapshot":
            if let payload: ProjectSnapshotPayload = payload(data) { emit(.projects(payload.projects)) }
        case "thread.snapshot":
            if let payload: ThreadSnapshotPayload = payload(data) { emit(.threads(projectID: payload.projectID, values: payload.threads)) }
        case "turn.started":
            if let payload: TurnStartedEventPayload = payload(data) {
                activeThreadID = payload.threadID
                activeTurnID = payload.turnID
                emit(.turnStarted(threadID: payload.threadID, turnID: payload.turnID, startedAt: payload.startedAt))
            }
        case "turn.output":
            if let payload: TurnOutputEventPayload = payload(data) {
                let stream = LogStream(rawValue: payload.stream) ?? .stdout
                emit(.output(LogEntry(stream: stream, text: payload.text)))
            }
        case "turn.snapshot":
            if let payload: TurnSnapshotEventPayload = payload(data) {
                activeThreadID = payload.threadID
                activeTurnID = payload.turnID
                emit(.turnStarted(threadID: payload.threadID, turnID: payload.turnID, startedAt: payload.startedAt))
                payload.recentOutput.forEach { emit(.output(LogEntry(stream: .stdout, text: $0))) }
            }
        case "turn.completed":
            if let payload: TurnCompletedEventPayload = payload(data) {
                emit(.turnEnded(phase: .completed, result: TurnResult(title: "Turn completed", detail: payload.summary.isEmpty ? "Changes are ready for review." : payload.summary, changedFiles: payload.changedFiles.count, duration: Double(payload.durationMS) / 1_000)))
                clearActiveTurn()
            }
        case "turn.failed":
            if let payload: TurnFailedEventPayload = payload(data) {
                emit(.turnEnded(phase: .failed, result: TurnResult(title: "Turn failed", detail: payload.message, changedFiles: 0, duration: Double(payload.durationMS ?? 0) / 1_000)))
                clearActiveTurn()
            }
        case "turn.interrupted":
            if let payload: TurnInterruptedEventPayload = payload(data) {
                emit(.turnEnded(phase: .interrupted, result: TurnResult(title: "Turn interrupted", detail: "Codex stopped cleanly.", changedFiles: 0, duration: Double(payload.durationMS) / 1_000)))
                clearActiveTurn()
            }
        case "turn.rejected":
            if let payload: TurnRejectedEventPayload = payload(data) {
                emit(.output(LogEntry(stream: .stderr, text: "\(payload.code): \(payload.message)")))
                if header.traceID == activeTraceID {
                    emit(.turnEnded(phase: .failed, result: TurnResult(title: "Request rejected", detail: payload.message, changedFiles: 0, duration: 0)))
                    clearActiveTurn()
                }
            }
        default:
            break
        }
    }

    private func payload<Payload: Codable & Sendable>(_ data: Data) -> Payload? {
        try? decoder.decode(RelayEnvelope<Payload>.self, from: data).payload
    }

    private func send<Payload: Codable & Sendable>(type: String, traceID: String, payload: Payload) async {
        guard let socket else {
            emit(.connection(.disconnected))
            return
        }
        let envelope = RelayEnvelope(specVersion: Self.specVersion, messageID: newID(), type: type, occurredAt: Date(), traceID: traceID, sender: RelaySender(kind: "user", id: "iphone"), payload: payload)
        do {
            let data = try encoder.encode(envelope)
            guard let text = String(data: data, encoding: .utf8) else {
                throw RelayClientError.invalidUTF8
            }
            try await socket.send(.string(text))
        } catch {
            emit(.output(LogEntry(stream: .system, text: "Relay send failed: \(error.localizedDescription)")))
        }
    }

    private func scheduleReconnect() {
        guard reconnectAutomatically else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }

    private func clearActiveTurn() {
        activeTraceID = nil
        activeThreadID = nil
        activeTurnID = nil
    }

    private func emit(_ event: RelayEvent) { continuation?.yield(event) }
    private func newID() -> String { UUID().uuidString.lowercased() }
}

private enum RelayClientError: Error {
    case invalidUTF8
}

private struct AgentHelloPayload: Codable, Sendable { let name: String; let version: String; let status: String }
private struct AgentStatusPayload: Codable, Sendable {
    let status: String
}
private struct ProjectSnapshotPayload: Codable, Sendable { let projects: [ProjectSummary] }
private struct ThreadSnapshotPayload: Codable, Sendable {
    let projectID: String
    let threads: [ThreadSummary]
    enum CodingKeys: String, CodingKey { case threads; case projectID = "project_id" }
}
private struct TurnStartedEventPayload: Codable, Sendable {
    let threadID: String; let turnID: String; let startedAt: Date
    enum CodingKeys: String, CodingKey { case threadID = "thread_id"; case turnID = "turn_id"; case startedAt = "started_at" }
}
private struct TurnOutputEventPayload: Codable, Sendable { let stream: String; let text: String }
private struct TurnSnapshotEventPayload: Codable, Sendable {
    let threadID: String; let turnID: String; let startedAt: Date; let recentOutput: [String]
    enum CodingKeys: String, CodingKey { case threadID = "thread_id"; case turnID = "turn_id"; case startedAt = "started_at"; case recentOutput = "recent_output" }
}
private struct TurnCompletedEventPayload: Codable, Sendable {
    let durationMS: Int64; let summary: String; let changedFiles: [String]
    enum CodingKeys: String, CodingKey { case summary; case durationMS = "duration_ms"; case changedFiles = "changed_files" }
}
private struct TurnFailedEventPayload: Codable, Sendable {
    let code: String; let message: String; let durationMS: Int64?
    enum CodingKeys: String, CodingKey { case code, message; case durationMS = "duration_ms" }
}
private struct TurnInterruptedEventPayload: Codable, Sendable {
    let durationMS: Int64
    enum CodingKeys: String, CodingKey { case durationMS = "duration_ms" }
}
private struct TurnRejectedEventPayload: Codable, Sendable { let code: String; let message: String }

private extension JSONEncoder {
    static var relay: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var relay: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let rawValue = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let withoutFraction = ISO8601DateFormatter()
            withoutFraction.formatOptions = [.withInternetDateTime]
            if let date = withFraction.date(from: rawValue) ?? withoutFraction.date(from: rawValue) {
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
