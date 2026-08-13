import Foundation

@MainActor
final class RelayClient: RelayServiceProtocol {
    private static let specVersion = "2.0"
    private static let maximumIncomingMessageBytes = 1_048_576
    private let eventBuffer = RelayEventBuffer()
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var relayURL: String
    private var activeTraceID: String?
    private var activeThreadID: String?
    private var activeTurnID: String?
    private var projectListTraceIDs: Set<String> = []
    private var executionProfileProjectIDByTraceID: [String: String] = [:]
    private var threadListProjectIDByTraceID: [String: String] = [:]
    private var threadReadTargetByTraceID: [String: (projectID: String, threadID: String)] = [:]
    private var agentName = "Mac Agent"

    private let encoder = JSONEncoder.relay
    private let decoder = JSONDecoder.relay

    init() {
        let defaults = UserDefaults.standard
        let profile = defaults.string(forKey: "relayConnectionProfile")
            .flatMap(RelayConnectionProfile.init(rawValue:))
            ?? RelayConnectionProfile.current
        relayURL = defaults.string(forKey: profile.urlDefaultsKey) ?? profile.defaultURL
    }

    func events() -> AsyncStream<RelayEvent> {
        eventBuffer.stream()
    }

    func connect() async {
        stopCurrentConnection(emitDisconnectedState: false)
        emit(.capabilities(nil))
        emit(.connection(.connecting))
        Diagnostics.shared.record(
            .relayConnectStarted,
            category: .relay,
            fields: [.transport: .string(URL(string: relayURL)?.scheme?.lowercased() ?? "invalid")]
        )
        guard let url = URL(string: relayURL), ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else {
            emit(.connection(.disconnected))
            emit(.output(LogEntry(stream: .system, text: "Relay URL is invalid.")))
            Diagnostics.shared.record(.relayDisconnected, level: .error, category: .relay, fields: [.reason: .string("invalid_url")])
            return
        }
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = Self.maximumIncomingMessageBytes
        socket = task
        task.resume()
        emit(.connection(.connected))
        Diagnostics.shared.record(.relayConnected, level: .notice, category: .relay, fields: [.transport: .string(url.scheme ?? "unknown")])
        receiveTask = Task { @MainActor [weak self, weak task] in
            guard let self, let task else { return }
            await receiveLoop(task)
        }
        await requestProjects()
    }

    func disconnect() async {
        stopCurrentConnection(emitDisconnectedState: true)
        Diagnostics.shared.record(.relayDisconnected, level: .notice, category: .relay, fields: [.reason: .string("requested")])
    }

    func testConnection(url: String) async throws -> RelayConnectionTestResult {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        Diagnostics.shared.record(.relayConnectionTestStarted, category: .relay)
        guard let webSocketURL = Self.validWebSocketURL(from: normalized),
              let statusURL = Self.statusURL(from: webSocketURL) else {
            throw RelayConnectionError.invalidURL
        }

        stopCurrentConnection(emitDisconnectedState: true)

        var request = URLRequest(url: statusURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayConnectionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RelayConnectionError.httpStatus(httpResponse.statusCode)
        }
        guard let status = try? decoder.decode(RelayHTTPStatus.self, from: data) else {
            throw RelayConnectionError.invalidResponse
        }

        relayURL = normalized
        await connect()
        Diagnostics.shared.record(
            .relayConnectionTestCompleted,
            level: .notice,
            category: .relay,
            fields: [
                .statusCode: .integer(httpResponse.statusCode),
                .agentConnected: .boolean(status.agentConnected)
            ]
        )
        return RelayConnectionTestResult(agentConnected: status.agentConnected)
    }

    func requestProjects() async {
        let traceID = newID()
        projectListTraceIDs.insert(traceID)
        await send(type: "project.list", traceID: traceID, payload: EmptyPayload())
    }

    func requestExecutionProfiles(projectID: String) async {
        let traceID = newID()
        executionProfileProjectIDByTraceID[traceID] = projectID
        await send(type: "execution.profile.list", traceID: traceID, payload: ExecutionProfileListPayload(projectID: projectID))
    }

    func requestThreads(projectID: String) async {
        let traceID = newID()
        threadListProjectIDByTraceID[traceID] = projectID
        await send(type: "thread.list", traceID: traceID, payload: ThreadListPayload(projectID: projectID))
    }

    func requestThread(projectID: String, threadID: String) async {
        let traceID = newID()
        threadReadTargetByTraceID[traceID] = (projectID, threadID)
        await send(type: "thread.read", traceID: traceID, payload: ThreadReadPayload(projectID: projectID, threadID: threadID))
    }

    func startTurn(projectID: String, threadID: String?, prompt: String, permissionProfileID: String?) async {
        let traceID = newID()
        activeTraceID = traceID
        activeThreadID = threadID
        activeTurnID = nil
        Diagnostics.shared.record(
            .turnStarted,
            level: .notice,
            category: .turn,
            traceID: traceID,
            fields: [.promptCharacters: .integer(prompt.count)]
        )
        await send(type: "turn.start", traceID: traceID, payload: TurnStartPayload(projectID: projectID, threadID: threadID, prompt: prompt, permissionProfileID: permissionProfileID))
    }

    func interruptTurn() async {
        guard let traceID = activeTraceID, let threadID = activeThreadID, let turnID = activeTurnID else {
            emit(.output(LogEntry(stream: .system, text: "Codex has not started the turn yet.")))
            return
        }
        await send(type: "turn.interrupt", traceID: traceID, payload: TurnInterruptPayload(threadID: threadID, turnID: turnID))
    }

    func acknowledgeTurn(traceID: String, turnID: String, phase: TurnPhase) async {
        guard phase.isTerminal else { return }
        await send(
            type: "turn.acknowledged",
            traceID: traceID,
            payload: TurnAcknowledgedPayload(turnID: turnID, status: phase.rawValue)
        )
    }

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
            emit(.capabilities(nil))
            emit(.output(LogEntry(stream: .system, text: "Relay connection ended: \(error.localizedDescription)")))
            let nsError = error as NSError
            Diagnostics.shared.record(
                .relayDisconnected,
                level: .error,
                category: .relay,
                fields: [
                    .reason: .string("receive_failed"),
                    .errorDomain: .string(nsError.domain),
                    .errorCode: .integer(nsError.code)
                ]
            )
            scheduleReconnect()
        }
    }

    private func handle(_ data: Data) {
        MemoryDiagnostics.shared.recordRelayMessage(byteCount: data.count)
        guard let header = try? decoder.decode(RelayEnvelopeHeader.self, from: data), header.specVersion == Self.specVersion else {
            emit(.output(LogEntry(stream: .system, text: "Relay sent an unsupported message.")))
            Diagnostics.shared.record(
                .relayDecodeFailed,
                level: .error,
                category: .relay,
                fields: [.bytes: .integer(data.count)]
            )
            return
        }
        if Self.lowVolumeMessageTypes.contains(header.type) {
            Diagnostics.shared.record(
                .relayResponseReceived,
                category: .relay,
                traceID: header.traceID,
                turnID: activeTurnID,
                fields: [
                    .messageType: .string(header.type),
                    .bytes: .integer(data.count)
                ]
            )
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
        case "agent.capabilities":
            if let payload: ExecutionCapabilities = payload(data) {
                emit(.capabilities(payload))
            }
        case "execution.profile.snapshot":
            if let payload: ExecutionProfileSnapshot = payload(data) {
                executionProfileProjectIDByTraceID.removeValue(forKey: header.traceID)
                emit(.executionProfiles(payload))
            }
        case "project.snapshot":
            if let payload: ProjectSnapshotPayload = payload(data) {
                projectListTraceIDs.remove(header.traceID)
                emit(.projects(payload.projects))
            }
        case "thread.snapshot":
            if let payload: ThreadSnapshotPayload = payload(data) {
                threadListProjectIDByTraceID.removeValue(forKey: header.traceID)
                emit(.threads(projectID: payload.projectID, values: payload.threads))
            }
        case "thread.detail":
            if let payload: ThreadDetailEventPayload = payload(data) {
                threadReadTargetByTraceID.removeValue(forKey: header.traceID)
                emit(.threadDetail(projectID: payload.projectID, value: payload.thread, truncated: payload.truncated))
            }
        case "turn.started":
            if let payload: TurnStartedEventPayload = payload(data) {
                activeThreadID = payload.threadID
                activeTurnID = payload.turnID
                emit(.turnStarted(threadID: payload.threadID, turnID: payload.turnID, startedAt: payload.startedAt))
            }
        case "turn.item.started":
            if let payload: TurnItemStartedEventPayload = payload(data) {
                emit(.turnItemStarted(turnID: payload.turnID, sequence: payload.sequence, item: payload.item))
            }
        case "turn.item.delta":
            if let payload: TurnItemDeltaEventPayload = payload(data) {
                emit(.turnItemDelta(turnID: payload.turnID, sequence: payload.sequence, itemID: payload.itemID, field: payload.field, delta: payload.delta))
            }
        case "turn.item.completed":
            if let payload: TurnItemCompletedEventPayload = payload(data) {
                emit(.turnItemCompleted(turnID: payload.turnID, sequence: payload.sequence, item: payload.item))
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
                emit(.turnSnapshot(
                    threadID: payload.threadID,
                    turnID: payload.turnID,
                    startedAt: payload.startedAt,
                    items: payload.liveItems ?? [],
                    lastSequence: payload.lastSequence ?? 0,
                    itemsTruncated: payload.liveItemsTruncated ?? false,
                    recentOutput: payload.recentOutput
                ))
            }
        case "turn.completed":
            if let payload: TurnCompletedEventPayload = payload(data) {
                Diagnostics.shared.record(.turnEnded, level: .notice, category: .turn, traceID: header.traceID, turnID: payload.turnID, fields: [.phase: .string("completed")])
                emit(.turnEnded(traceID: header.traceID, turnID: payload.turnID, phase: .completed, result: nil))
                clearActiveTurn()
            }
        case "turn.failed":
            if let payload: TurnFailedEventPayload = payload(data) {
                Diagnostics.shared.record(.turnEnded, level: .error, category: .turn, traceID: header.traceID, turnID: payload.turnID ?? activeTurnID, fields: [.phase: .string("failed"), .durationMS: .integer(Int(payload.durationMS ?? 0))])
                emit(.turnEnded(traceID: header.traceID, turnID: payload.turnID ?? activeTurnID, phase: .failed, result: TurnResult(title: String(localized: "Turn failed"), detail: payload.message, changedFiles: 0, duration: Double(payload.durationMS ?? 0) / 1_000)))
                clearActiveTurn()
            }
        case "turn.interrupted":
            if let payload: TurnInterruptedEventPayload = payload(data) {
                Diagnostics.shared.record(.turnEnded, level: .notice, category: .turn, traceID: header.traceID, turnID: payload.turnID ?? activeTurnID, fields: [.phase: .string("interrupted"), .durationMS: .integer(Int(payload.durationMS))])
                emit(.turnEnded(traceID: header.traceID, turnID: payload.turnID ?? activeTurnID, phase: .interrupted, result: TurnResult(title: String(localized: "Turn interrupted"), detail: String(localized: "Codex stopped cleanly."), changedFiles: 0, duration: Double(payload.durationMS) / 1_000)))
                clearActiveTurn()
            }
        case "turn.rejected":
            if let payload: TurnRejectedEventPayload = payload(data) {
                if let context = payload.executionContext {
                    emit(.capabilities(context))
                }
                emit(.output(LogEntry(stream: .stderr, text: "\(payload.code): \(payload.message)")))
                let rejectionDetail = [payload.message, payload.recoveryAction].compactMap { $0 }.joined(separator: "\n\n")
                if projectListTraceIDs.remove(header.traceID) != nil {
                    emit(.projectsFailed(message: payload.message))
                } else if let projectID = executionProfileProjectIDByTraceID.removeValue(forKey: header.traceID) {
                    emit(.executionProfilesFailed(projectID: projectID, message: payload.message))
                } else if let projectID = threadListProjectIDByTraceID.removeValue(forKey: header.traceID) {
                    emit(.threadsFailed(projectID: projectID, message: payload.message))
                } else if let target = threadReadTargetByTraceID.removeValue(forKey: header.traceID) {
                    emit(.threadDetailFailed(projectID: target.projectID, threadID: target.threadID, message: payload.message))
                } else if header.traceID == activeTraceID {
                    emit(.turnEnded(traceID: nil, turnID: nil, phase: .failed, result: TurnResult(title: String(localized: "Request rejected"), detail: rejectionDetail, changedFiles: 0, duration: 0)))
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
            Diagnostics.shared.record(
                .relayRequestSent,
                category: .relay,
                traceID: traceID,
                turnID: activeTurnID,
                fields: [
                    .messageType: .string(type),
                    .bytes: .integer(data.count)
                ]
            )
        } catch {
            emit(.output(LogEntry(stream: .system, text: "Relay send failed: \(error.localizedDescription)")))
            let nsError = error as NSError
            Diagnostics.shared.record(
                .relaySendFailed,
                level: .error,
                category: .relay,
                traceID: traceID,
                turnID: activeTurnID,
                fields: [
                    .messageType: .string(type),
                    .errorDomain: .string(nsError.domain),
                    .errorCode: .integer(nsError.code)
                ]
            )
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        Diagnostics.shared.record(.relayReconnectScheduled, category: .relay, fields: [.delayMS: .integer(2_000)])
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }

    private func stopCurrentConnection(emitDisconnectedState: Bool) {
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        projectListTraceIDs.removeAll()
        executionProfileProjectIDByTraceID.removeAll()
        threadListProjectIDByTraceID.removeAll()
        threadReadTargetByTraceID.removeAll()
        clearActiveTurn()
        if emitDisconnectedState {
            emit(.connection(.disconnected))
            emit(.agent(name: agentName, state: .offline))
            emit(.capabilities(nil))
        }
    }

    private static func validWebSocketURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }

    private static func statusURL(from webSocketURL: URL) -> URL? {
        guard var components = URLComponents(url: webSocketURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = webSocketURL.scheme?.lowercased() == "wss" ? "https" : "http"
        components.path = "/status"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func clearActiveTurn() {
        activeTraceID = nil
        activeThreadID = nil
        activeTurnID = nil
    }

    private func emit(_ event: RelayEvent) { eventBuffer.yield(event) }
    private func newID() -> String { UUID().uuidString.lowercased() }

    private static let lowVolumeMessageTypes: Set<String> = [
        "agent.hello",
        "agent.status",
        "agent.capabilities",
        "execution.profile.snapshot",
        "project.snapshot",
        "thread.snapshot",
        "thread.detail",
        "turn.started",
        "turn.snapshot",
        "turn.completed",
        "turn.failed",
        "turn.interrupted",
        "turn.rejected"
    ]
}
