import Foundation

@MainActor
final class RuntimeRelayService: RelayServiceProtocol {
    private let eventBuffer = RelayEventBuffer()
    private let cursorStore = RuntimeCursorStore()
    private var client: RuntimeClient
    private var baseURL: URL
    private var runWatchTask: Task<Void, Never>?
    private var sessionWatchTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var sessionsByProjectID: [String: [RuntimeSession]] = [:]
    private var selectedProjectID: String?
    private var selectedSessionID: String?
    private var activeRunID: String?
    private var legacyAssistantStartedRunIDs: Set<String> = []

    init() {
        let defaults = UserDefaults.standard
        let profile = defaults.string(forKey: "relayConnectionProfile")
            .flatMap(RelayConnectionProfile.init(rawValue:)) ?? .current
        let rawURL = defaults.string(forKey: profile.urlDefaultsKey) ?? profile.defaultURL
        baseURL = Self.validRuntimeURL(rawURL) ?? URL(string: "http://127.0.0.1:18874")!
        client = RuntimeClient(baseURL: baseURL)
    }

    func events() -> AsyncStream<RelayEvent> { eventBuffer.stream() }

    func connect() async {
        stopWatchers()
        emit(.authentication(.checking))
        emit(.connection(.connecting))
        let state = await client.bootstrapAuthentication()
        emit(.authentication(state))
        guard state.isAuthenticated else {
            emit(.connection(.disconnected))
            emit(.agent(name: "Mac Agent", state: .offline))
            return
        }
        do {
            try await client.health()
            emit(.connection(.connected))
            await requestProjects()
        } catch {
            publishConnectionFailure(error)
        }
    }

    func disconnect() async {
        stopWatchers()
        emit(.connection(.disconnected))
        emit(.agent(name: "Mac Agent", state: .offline))
    }

    func testConnection(url: String) async throws -> RelayConnectionTestResult {
        guard let resolved = Self.validRuntimeURL(url) else { throw RuntimeAPIError.invalidURL }
        var request = URLRequest(url: URL(string: "/gateway/healthz", relativeTo: resolved)!.absoluteURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw RuntimeAPIError.invalidResponse
        }
        baseURL = resolved
        await client.updateBaseURL(resolved)
        await connect()
        return RelayConnectionTestResult(agentConnected: true)
    }

    func pair(codeOrLink: String) async {
        emit(.authentication(.pairing))
        do {
            if let origin = RuntimeAuthSession.pairingOrigin(from: codeOrLink), origin != baseURL {
                baseURL = origin
                UserDefaults.standard.set(origin.absoluteString, forKey: RelayConnectionProfile.current.urlDefaultsKey)
                await client.updateBaseURL(origin)
                emit(.runtimeOrigin(origin.absoluteString))
            }
            let state = try await client.pair(codeOrLink)
            emit(.authentication(state))
            await connect()
        } catch {
            let message = pairingMessage(error)
            emit(.authentication(.unauthenticated(message: message)))
        }
    }

    func signOut() async {
        stopWatchers()
        await client.signOut()
        sessionsByProjectID.removeAll()
        selectedProjectID = nil
        selectedSessionID = nil
        activeRunID = nil
        emit(.reset)
        emit(.projects([]))
        emit(.connection(.disconnected))
        emit(.agent(name: "Mac Agent", state: .offline))
        emit(.authentication(.unauthenticated(message: "This device has signed out.")))
    }

    func suspend() async {
        stopWatchers()
    }

    func resume() async {
        let projectID = selectedProjectID
        let sessionID = selectedSessionID
        await connect()
        guard case .connected = currentConnectionState else { return }
        if let projectID { await requestThreads(projectID: projectID) }
        if let projectID, let sessionID { await requestThread(projectID: projectID, threadID: sessionID) }
    }

    func requestProjects() async {
        do {
            let projectList = try await client.projects()
            let sessions = try await client.sessions()
            sessionsByProjectID = Dictionary(grouping: sessions, by: \RuntimeSession.projectID)
            let projects = projectList.items.map { item in
                let values = sessionsByProjectID[item.projectID] ?? []
                return ProjectSummary(
                    id: item.projectID,
                    name: item.displayName,
                    path: "",
                    threadCount: values.count,
                    updatedAt: values.first?.updatedAt
                )
            }
            let agentState: AgentState = projectList.agentPresence == "online" ? (activeRunID == nil ? .idle : .running) : .offline
            emit(.agent(name: "Mac Agent", state: agentState))
            emit(.capabilities(runtimeCapabilities))
            emit(.projects(projects))
            if projects.isEmpty, projectList.agentPresence == "online" { startBootstrapIfNeeded() }
        } catch {
            emit(.projectsFailed(message: displayMessage(error)))
            publishConnectionFailure(error)
        }
    }

    func requestExecutionProfiles(projectID: String) async {
        do {
            emit(.executionProfiles(try await client.executionProfiles(projectID: projectID)))
        } catch {
            emit(.executionProfilesFailed(projectID: projectID, message: displayMessage(error)))
        }
    }

    func requestThreads(projectID: String) async {
        selectedProjectID = projectID
        do {
            let sessions = try await client.sessions(projectID: projectID)
            sessionsByProjectID[projectID] = sessions
            emit(.threads(projectID: projectID, values: sessions.map { $0.threadSummary() }))
        } catch {
            emit(.threadsFailed(projectID: projectID, message: displayMessage(error)))
        }
    }

    func requestThread(projectID: String, threadID: String) async {
        switchContext(projectID: projectID, sessionID: threadID)
        do {
            let snapshot = try await client.sessionDetail(threadID)
            await cursorStore.advance(snapshot.snapshotSessionSequence, origin: origin, kind: "session", id: threadID)
            for run in snapshot.runs {
                await cursorStore.advance(run.persistedThroughSequence, origin: origin, kind: "run", id: run.runID)
            }
            let active = snapshot.runs.last(where: { runtimeStatusIsActive($0.status) })
            emit(.threadDetail(projectID: projectID, value: snapshot.threadDetail(excludingRunID: activeRunID ?? active?.runID), truncated: false))
            startSessionWatcher(projectID: projectID, sessionID: threadID)
            if let active {
                restoreActiveRun(active)
                startRunWatcher(projectID: projectID, sessionID: threadID, runID: active.runID)
            }
        } catch {
            emit(.threadDetailFailed(projectID: projectID, threadID: threadID, message: displayMessage(error)))
        }
    }

    func selectContext(projectID: String, threadID: String?) {
        switchContext(projectID: projectID, sessionID: threadID)
    }

    func startTurn(projectID: String, threadID: String?, prompt: String, permissionProfileID: String?) async {
        do {
            let session: RuntimeSession
            if let threadID {
                let snapshot = try await client.sessionSnapshot(threadID)
                session = snapshot.session
            } else {
                session = try await client.createSession(
                    projectID: projectID,
                    title: Self.sessionTitle(from: prompt),
                    idempotencyKey: "ios-session-\(UUID().uuidString.lowercased())"
                )
            }
            selectedProjectID = projectID
            selectedSessionID = session.sessionID
            let run = try await client.createRun(
                sessionID: session.sessionID,
                prompt: prompt,
                permissionProfileID: permissionProfileID,
                idempotencyKey: "ios-run-\(UUID().uuidString.lowercased())"
            )
            activeRunID = run.runID
            emit(.turnStarted(threadID: session.sessionID, turnID: run.runID, startedAt: run.createdAt))
            emit(.agent(name: "Mac Agent", state: .running))
            await requestThreads(projectID: projectID)
            startSessionWatcher(projectID: projectID, sessionID: session.sessionID)
            startRunWatcher(projectID: projectID, sessionID: session.sessionID, runID: run.runID)
        } catch {
            emit(.turnEnded(
                traceID: nil,
                turnID: activeRunID,
                phase: .failed,
                result: TurnResult(title: String(localized: "Request rejected"), detail: displayMessage(error), changedFiles: 0, duration: 0)
            ))
            activeRunID = nil
        }
    }

    func interruptTurn() async {
        guard let activeRunID else { return }
        do { try await client.cancelRun(activeRunID) }
        catch { emit(.output(LogEntry(stream: .stderr, text: displayMessage(error)))) }
    }

    func acknowledgeTurn(traceID: String, turnID: String, phase: TurnPhase) async {}

    private func startBootstrapIfNeeded() {
        guard bootstrapTask == nil else { return }
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { bootstrapTask = nil }
            do {
                var job = try await client.startBootstrap(idempotencyKey: "ios-bootstrap-\(UUID().uuidString.lowercased())")
                while job.status == "queued" || job.status == "running" {
                    try await Task.sleep(for: .milliseconds(700))
                    job = try await client.bootstrap(job.syncID)
                }
                if job.status == "completed" { await requestProjects() }
                else { emit(.projectsFailed(message: job.errorMessage ?? "History sync failed.")) }
            } catch {
                emit(.projectsFailed(message: displayMessage(error)))
            }
        }
    }

    private func startSessionWatcher(projectID: String, sessionID: String) {
        sessionWatchTask?.cancel()
        sessionWatchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var cursor = await cursorStore.value(origin: origin, kind: "session", id: sessionID)
            while !Task.isCancelled, selectedSessionID == sessionID {
                do {
                    let stream = await client.eventStream(path: "/v1/runtime/sessions/\(sessionID)/events", after: cursor)
                    for try await event in stream {
                        guard !Task.isCancelled, selectedSessionID == sessionID else { return }
                        cursor = max(cursor, event.id)
                        await cursorStore.advance(cursor, origin: origin, kind: "session", id: sessionID)
                        await refreshSelectedSession(projectID: projectID, sessionID: sessionID, discoveredRunID: event.runID)
                    }
                } catch {
                    if Task.isCancelled { return }
                    if handleAuthenticationFailure(error) { return }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func startRunWatcher(projectID: String, sessionID: String, runID: String) {
        runWatchTask?.cancel()
        activeRunID = runID
        runWatchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var cursor = await cursorStore.value(origin: origin, kind: "run", id: runID)
            while !Task.isCancelled, activeRunID == runID {
                do {
                    let stream = await client.eventStream(path: "/v1/runtime/runs/\(runID)/events", after: cursor)
                    for try await event in stream {
                        guard !Task.isCancelled, activeRunID == runID else { return }
                        cursor = max(cursor, event.id)
                        await cursorStore.advance(cursor, origin: origin, kind: "run", id: runID)
                        if applyRunEvent(event, runID: runID) {
                            await finishRun(projectID: projectID, sessionID: sessionID, runID: runID)
                            return
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    if handleAuthenticationFailure(error) { return }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func refreshSelectedSession(projectID: String, sessionID: String, discoveredRunID: String?) async {
        guard selectedSessionID == sessionID else { return }
        do {
            let snapshot = try await client.sessionDetail(sessionID)
            let active = snapshot.runs.last(where: { runtimeStatusIsActive($0.status) })
            emit(.threadDetail(projectID: projectID, value: snapshot.threadDetail(excludingRunID: active?.runID), truncated: false))
            await requestThreads(projectID: projectID)
            guard let runID = discoveredRunID,
                  runID != activeRunID,
                  let run = snapshot.runs.first(where: { $0.runID == runID }),
                  runtimeStatusIsActive(run.status) else { return }
            restoreActiveRun(run)
            startRunWatcher(projectID: projectID, sessionID: sessionID, runID: runID)
        } catch {
            emit(.output(LogEntry(stream: .system, text: displayMessage(error))))
        }
    }

    private func restoreActiveRun(_ run: RuntimeRun) {
        activeRunID = run.runID
        let turn = run.threadHistoryTurn()
        emit(.turnSnapshot(
            threadID: run.sessionID,
            turnID: run.runID,
            startedAt: run.startedAt ?? run.createdAt,
            items: turn.items,
            lastSequence: run.persistedThroughSequence,
            itemsTruncated: turn.truncated,
            recentOutput: []
        ))
        emit(.agent(name: "Mac Agent", state: .running))
    }

    private func applyRunEvent(_ event: RuntimeStreamEvent, runID: String) -> Bool {
        switch event.type {
        case "turn.started":
            emit(.turnStarted(
                threadID: selectedSessionID ?? "",
                turnID: runID,
                startedAt: event.fields["started_at"]?.stringValue.flatMap(Self.date) ?? Date()
            ))
        case "assistant.delta":
            let delta = event.fields["text"]?.stringValue ?? event.fields["delta"]?.stringValue ?? ""
            if legacyAssistantStartedRunIDs.insert(runID).inserted {
                emit(.turnItemStarted(
                    turnID: runID,
                    sequence: event.id,
                    item: ThreadHistoryItem(
                        id: "assistant-\(runID)", type: "agentMessage", role: "assistant", phase: "final_answer",
                        status: "inProgress", text: delta, name: nil, command: nil, cwd: nil, output: nil,
                        path: nil, query: nil, exitCode: nil, durationMS: nil, changes: nil, truncated: false
                    )
                ))
                break
            }
            emit(.turnItemDelta(turnID: runID, sequence: event.id, itemID: "assistant-\(runID)", field: "text", delta: delta))
        case "item.started":
            if let value = event.fields["item"], let item = decodeHistoryItem(value) {
                emit(.turnItemStarted(turnID: runID, sequence: event.id, item: item))
            }
        case "item.delta":
            emit(.turnItemDelta(
                turnID: runID,
                sequence: event.id,
                itemID: event.fields["item_id"]?.stringValue ?? "",
                field: event.fields["field"]?.stringValue ?? "text",
                delta: event.fields["delta"]?.stringValue ?? ""
            ))
        case "item.completed":
            if let value = event.fields["item"], let item = decodeHistoryItem(value) {
                emit(.turnItemCompleted(turnID: runID, sequence: event.id, item: item))
            }
        case "turn.completed":
            emit(.turnEnded(traceID: nil, turnID: runID, phase: .completed, result: nil))
            return true
        case "turn.failed":
            let message = event.fields["message"]?.stringValue ?? "Runtime execution failed."
            emit(.turnEnded(traceID: nil, turnID: runID, phase: .failed, result: TurnResult(title: String(localized: "Turn failed"), detail: message, changedFiles: 0, duration: 0)))
            return true
        case "turn.interrupted":
            emit(.turnEnded(traceID: nil, turnID: runID, phase: .interrupted, result: TurnResult(title: String(localized: "Turn interrupted"), detail: String(localized: "Codex stopped cleanly."), changedFiles: 0, duration: 0)))
            return true
        default:
            break
        }
        return false
    }

    private func finishRun(projectID: String, sessionID: String, runID: String) async {
        guard activeRunID == runID else { return }
        activeRunID = nil
        legacyAssistantStartedRunIDs.remove(runID)
        emit(.agent(name: "Mac Agent", state: .idle))
        do {
            let snapshot = try await client.sessionDetail(sessionID)
            emit(.threadDetail(projectID: projectID, value: snapshot.threadDetail(), truncated: false))
            emit(.reset)
            await requestThreads(projectID: projectID)
        } catch {
            emit(.output(LogEntry(stream: .system, text: displayMessage(error))))
        }
    }

    private func publishConnectionFailure(_ error: Error) {
        if handleAuthenticationFailure(error) { return }
        emit(.connection(.disconnected))
        emit(.agent(name: "Mac Agent", state: .offline))
        emit(.output(LogEntry(stream: .system, text: displayMessage(error))))
    }

    private func handleAuthenticationFailure(_ error: Error) -> Bool {
        guard let authError = error as? RuntimeAuthError else { return false }
        switch authError {
        case .missingCredential:
            emit(.authentication(.unauthenticated(message: "This device is not paired.")))
        case .rejected(_, let status) where status == 401:
            emit(.authentication(.unauthenticated(message: "This device's access has expired or was revoked.")))
        default:
            emit(.authentication(.unavailable(message: "Authentication service is unavailable.")))
        }
        emit(.connection(.disconnected))
        emit(.agent(name: "Mac Agent", state: .offline))
        return true
    }

    private func stopWatchers() {
        runWatchTask?.cancel()
        sessionWatchTask?.cancel()
        bootstrapTask?.cancel()
        runWatchTask = nil
        sessionWatchTask = nil
        bootstrapTask = nil
    }

    private func switchContext(projectID: String, sessionID: String?) {
        if selectedSessionID != sessionID {
            runWatchTask?.cancel()
            sessionWatchTask?.cancel()
            runWatchTask = nil
            sessionWatchTask = nil
            activeRunID = nil
            legacyAssistantStartedRunIDs.removeAll()
        }
        selectedProjectID = projectID
        selectedSessionID = sessionID
    }

    private var currentConnectionState: ConnectionState = .disconnected
    private func emit(_ event: RelayEvent) {
        if case .connection(let state) = event { currentConnectionState = state }
        eventBuffer.yield(event)
    }
    private var origin: String { baseURL.absoluteString }

    private var runtimeCapabilities: ExecutionCapabilities {
        ExecutionCapabilities(
            restricted: false,
            sandboxMode: "runtime-profile",
            approvalPolicy: "runtime-profile",
            writableScope: "selected-project",
            networkAccess: false,
            canRequestApproval: false,
            hostProcessControl: false,
            userLibraryWrite: false,
            xcodeDeviceControl: false,
            supportsPermissionProfiles: true
        )
    }

    private func displayMessage(_ error: Error) -> String {
        if let value = error as? RuntimeAPIError { return value.localizedDescription }
        if let value = error as? RuntimeAuthError { return value.localizedDescription }
        return error.localizedDescription
    }

    private func pairingMessage(_ error: Error) -> String {
        guard case .rejected(let code, _) = error as? RuntimeAuthError else { return displayMessage(error) }
        switch code {
        case "AUTH_PAIRING_ALREADY_USED": return "This pairing link has already been used."
        case "AUTH_CREDENTIAL_EXPIRED": return "This pairing link has expired."
        default: return "This pairing code is invalid."
        }
    }

    private static func sessionTitle(from prompt: String) -> String {
        let compact = prompt.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(compact.prefix(80))
    }

    private static func date(_ value: String) -> Date? {
        guard let data = "\"\(value)\"".data(using: .utf8) else { return nil }
        return try? RuntimeCoding.decoder.decode(Date.self, from: data)
    }

    private static func validRuntimeURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else { return nil }
        return url
    }
}

private func runtimeStatusIsActive(_ status: String) -> Bool {
    ["queued", "dispatching", "accepted", "running", "waiting_agent", "recovering", "finalizing"].contains(status)
}
