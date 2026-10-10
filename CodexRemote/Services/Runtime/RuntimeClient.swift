import Foundation

enum RuntimeAPIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case request(code: String, message: String, status: Int, retryable: Bool)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Runtime URL."
        case .invalidResponse: "Runtime returned an invalid response."
        case .request(_, let message, _, _): message
        }
    }
}

actor RuntimeCursorStore {
    private let defaults: UserDefaults
    private let prefix = "runtime.cursor."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func value(origin: String, kind: String, id: String) -> Int64 {
        Int64(defaults.integer(forKey: key(origin: origin, kind: kind, id: id)))
    }

    func advance(_ value: Int64, origin: String, kind: String, id: String) {
        guard value > self.value(origin: origin, kind: kind, id: id) else { return }
        defaults.set(value, forKey: key(origin: origin, kind: kind, id: id))
    }

    private func key(origin: String, kind: String, id: String) -> String {
        let raw = Data("\(origin)|\(kind)|\(id)".utf8).base64EncodedString()
        return prefix + raw
    }
}

actor RuntimeClient {
    private var baseURL: URL
    private let session: URLSession
    private let auth: RuntimeAuthSession

    init(baseURL: URL, session: URLSession? = nil, credentialStore: RuntimeCredentialStore = KeychainCredentialStore()) {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        let resolvedSession = session ?? URLSession(configuration: configuration)
        self.baseURL = baseURL
        self.session = resolvedSession
        auth = RuntimeAuthSession(baseURL: baseURL, session: resolvedSession, credentialStore: credentialStore)
    }

    func updateBaseURL(_ url: URL) async {
        baseURL = url
        await auth.updateBaseURL(url)
    }

    func bootstrapAuthentication() async -> RuntimeAuthenticationState { await auth.bootstrap() }
    func pair(_ input: String) async throws -> RuntimeAuthenticationState { try await auth.exchange(input) }
    func signOut() async { await auth.signOut() }

    func health() async throws {
        let _: [String: String] = try await get("/v1/runtime/healthz")
    }

    func projects() async throws -> RuntimeProjectList { try await get("/v1/runtime/projects") }

    func sessions(projectID: String? = nil) async throws -> [RuntimeSession] {
        var path = "/v1/runtime/sessions"
        if let projectID { path += "?project_id=\(projectID.urlPathEncoded)" }
        let result: RuntimeSessionList = try await get(path)
        return result.items
    }

    func createSession(projectID: String, title: String, idempotencyKey: String) async throws -> RuntimeSession {
        try await post("/v1/runtime/sessions", body: ["project_id": projectID, "title": title], idempotencyKey: idempotencyKey)
    }

    func sessionSnapshot(_ sessionID: String) async throws -> RuntimeSessionSnapshot {
        try await get("/v1/runtime/sessions/\(sessionID.urlPathEncoded)")
    }

    func sessionDetail(_ sessionID: String) async throws -> RuntimeSessionSnapshot {
        let snapshot = try await sessionSnapshot(sessionID)
        let runsByID = try await withThrowingTaskGroup(of: RuntimeRun.self, returning: [String: RuntimeRun].self) { group in
            for summary in snapshot.runs {
                group.addTask { try await self.run(summary.runID) }
            }
            var values: [String: RuntimeRun] = [:]
            for try await run in group { values[run.runID] = run }
            return values
        }
        return RuntimeSessionSnapshot(
            session: snapshot.session,
            runs: snapshot.runs.compactMap { runsByID[$0.runID] },
            snapshotSessionSequence: snapshot.snapshotSessionSequence,
            agentPresence: snapshot.agentPresence
        )
    }

    func run(_ runID: String) async throws -> RuntimeRun {
        try await get("/v1/runtime/runs/\(runID.urlPathEncoded)")
    }

    func createRun(sessionID: String, prompt: String, permissionProfileID: String?, idempotencyKey: String) async throws -> RuntimeCreatedRun {
        var body = ["prompt": prompt]
        if let permissionProfileID { body["permission_profile_id"] = permissionProfileID }
        return try await post("/v1/runtime/sessions/\(sessionID.urlPathEncoded)/runs", body: body, idempotencyKey: idempotencyKey)
    }

    func cancelRun(_ runID: String) async throws {
        let _: [String: JSONValue] = try await post("/v1/runtime/runs/\(runID.urlPathEncoded)/cancel", body: [String: String]())
    }

    func executionProfiles(projectID: String) async throws -> ExecutionProfileSnapshot {
        try await get("/v1/runtime/projects/\(projectID.urlPathEncoded)/execution-profiles")
    }

    func startBootstrap(idempotencyKey: String) async throws -> RuntimeSyncJob {
        try await post("/v1/runtime/bootstrap-syncs", body: [String: String](), idempotencyKey: idempotencyKey)
    }

    func bootstrap(_ syncID: String) async throws -> RuntimeSyncJob {
        try await get("/v1/runtime/bootstrap-syncs/\(syncID.urlPathEncoded)")
    }

    func eventStream(path: String, after: Int64) -> AsyncThrowingStream<RuntimeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try await self.authorizedRequest(path: "\(path)?after=\(max(0, after))", method: "GET")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    var attemptedToken = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
                    var (bytes, response) = try await self.session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                        let token = try await self.auth.validAccessToken(rejectedToken: attemptedToken)
                        attemptedToken = token
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        (bytes, response) = try await self.session.bytes(for: request)
                    }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw RuntimeAPIError.request(code: "SSE_HTTP_ERROR", message: "Runtime event stream is unavailable.", status: (response as? HTTPURLResponse)?.statusCode ?? 0, retryable: true)
                    }
                    var decoder = SSEDecoder()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        for packet in decoder.push(line + "\n") {
                            if let event = try Self.runtimeEvent(packet) { continuation.yield(event) }
                        }
                    }
                    for packet in decoder.finish() {
                        if let event = try Self.runtimeEvent(packet) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func get<Value: Decodable & Sendable>(_ path: String) async throws -> Value {
        try await request(path: path, method: "GET", body: Optional<[String: String]>.none, idempotencyKey: nil)
    }

    private func post<Value: Decodable & Sendable, Body: Encodable>(
        _ path: String,
        body: Body,
        idempotencyKey: String? = nil
    ) async throws -> Value {
        try await request(path: path, method: "POST", body: body, idempotencyKey: idempotencyKey)
    }

    private func request<Value: Decodable & Sendable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        idempotencyKey: String?
    ) async throws -> Value {
        var request = try await authorizedRequest(path: path, method: method)
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        let attemptedToken = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let token = try await auth.validAccessToken(rejectedToken: attemptedToken)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw RuntimeAPIError.invalidResponse }
        if (200..<300).contains(http.statusCode), let envelope = try? RuntimeCoding.decoder.decode(RuntimeEnvelope<Value>.self, from: data) {
            return envelope.data
        }
        let failure = try? RuntimeCoding.decoder.decode(RuntimeErrorEnvelope.self, from: data).error
        throw RuntimeAPIError.request(
            code: failure?.code ?? "HTTP_\(http.statusCode)",
            message: failure?.message ?? "Runtime request failed.",
            status: http.statusCode,
            retryable: failure?.retryable ?? (http.statusCode >= 500)
        )
    }

    private func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw RuntimeAPIError.invalidURL }
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = method == "GET" && path.contains("/events") ? 60 : 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-CodexRemote-Request")
        return request
    }

    private static func runtimeEvent(_ packet: ServerSentEvent) throws -> RuntimeStreamEvent? {
        guard !packet.data.isEmpty else { return nil }
        guard let data = packet.data.data(using: .utf8),
              case .object(let fields) = try RuntimeCoding.decoder.decode(JSONValue.self, from: data) else {
            throw RuntimeAPIError.invalidResponse
        }
        let id = Int64(packet.id ?? "") ?? fields["id"]?.int64Value ?? 0
        let type = packet.event ?? fields["type"]?.stringValue ?? "message"
        return RuntimeStreamEvent(id: id, type: type, fields: fields)
    }
}

private extension String {
    var urlPathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? self
    }
}
