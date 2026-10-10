import Foundation

enum RuntimeAuthError: LocalizedError, Sendable {
    case invalidPairingInput
    case missingCredential
    case rejected(code: String, status: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidPairingInput: "Invalid pairing code or link."
        case .missingCredential: "This device is not paired."
        case .rejected(let code, _): code
        case .invalidResponse: "The authentication service returned an invalid response."
        }
    }
}

actor RuntimeAuthSession {
    private var baseURL: URL
    private let session: URLSession
    private let credentialStore: RuntimeCredentialStore
    private var accessToken = ""
    private var accessExpiresAt = Date.distantPast
    private var clientName = ""
    private var refreshTask: Task<String, Error>?

    init(baseURL: URL, session: URLSession, credentialStore: RuntimeCredentialStore = KeychainCredentialStore()) {
        self.baseURL = baseURL
        self.session = session
        self.credentialStore = credentialStore
    }

    func updateBaseURL(_ url: URL) {
        guard baseURL != url else { return }
        baseURL = url
        accessToken = ""
        accessExpiresAt = .distantPast
        clientName = ""
    }

    func bootstrap() async -> RuntimeAuthenticationState {
        do {
            guard let credential = try credentialStore.load(), credential.baseURL == normalizedBaseURL else {
                return .unauthenticated(message: nil)
            }
            clientName = credential.clientName
            _ = try await refresh(using: credential.refreshToken)
            return .authenticated(clientName: clientName)
        } catch let error as RuntimeAuthError {
            if case .rejected(_, let status) = error, status == 401 {
                try? credentialStore.remove()
                return .unauthenticated(message: "This device's access has expired or was revoked.")
            }
            return .unavailable(message: "Authentication service is unavailable.")
        } catch {
            return .unavailable(message: "Authentication service is unavailable.")
        }
    }

    func exchange(_ input: String) async throws -> RuntimeAuthenticationState {
        guard let code = Self.pairingCode(from: input) else { throw RuntimeAuthError.invalidPairingInput }
        let pair: RuntimeNativeTokenPair = try await tokenRequest(
            path: "/v1/auth/native/pairing-grants:exchange",
            body: ["code": code]
        )
        try accept(pair)
        return .authenticated(clientName: pair.client.name)
    }

    func validAccessToken(rejectedToken: String? = nil) async throws -> String {
        if let rejectedToken, !accessToken.isEmpty, rejectedToken != accessToken { return accessToken }
        if !accessToken.isEmpty, accessExpiresAt.timeIntervalSinceNow > 30 { return accessToken }
        if let refreshTask { return try await refreshTask.value }
        guard let credential = try credentialStore.load(), credential.baseURL == normalizedBaseURL else {
            throw RuntimeAuthError.missingCredential
        }
        let task = Task { try await self.refresh(using: credential.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch let error as RuntimeAuthError {
            if case .rejected(_, let status) = error, status == 401 {
                accessToken = ""
                accessExpiresAt = .distantPast
                clientName = ""
                try? credentialStore.remove()
            }
            throw error
        }
    }

    func signOut() async {
        let credential = try? credentialStore.load()
        if let credential, credential.baseURL == normalizedBaseURL {
            let request = try? makeRequest(
                path: "/v1/auth/native/sessions/current:revoke",
                body: ["refresh_token": credential.refreshToken]
            )
            if let request { _ = try? await session.data(for: request) }
        }
        try? credentialStore.remove()
        accessToken = ""
        accessExpiresAt = .distantPast
        clientName = ""
    }

    static func pairingCode(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let components = URLComponents(string: trimmed), let fragment = components.fragment {
            return URLComponents(string: "?\(fragment)")?.queryItems?
                .first(where: { $0.name == "code" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        if trimmed.contains("://") { return nil }
        return trimmed
    }

    static func pairingOrigin(from input: String) -> URL? {
        guard let inputURL = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(inputURL.scheme?.lowercased() ?? ""),
              inputURL.host != nil,
              var components = URLComponents(url: inputURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func refresh(using refreshToken: String) async throws -> String {
        let pair: RuntimeNativeTokenPair = try await tokenRequest(
            path: "/v1/auth/native/tokens:refresh",
            body: ["refresh_token": refreshToken]
        )
        try accept(pair)
        return pair.accessToken
    }

    private func accept(_ pair: RuntimeNativeTokenPair) throws {
        accessToken = pair.accessToken
        accessExpiresAt = pair.accessExpiresAt
        clientName = pair.client.name
        try credentialStore.save(RuntimeRefreshCredential(
            baseURL: normalizedBaseURL,
            refreshToken: pair.refreshToken,
            refreshExpiresAt: pair.refreshExpiresAt,
            clientName: pair.client.name
        ))
    }

    private func tokenRequest<Value: Decodable & Sendable>(path: String, body: [String: String]) async throws -> Value {
        let request = try makeRequest(path: path, body: body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RuntimeAuthError.invalidResponse }
        if (200..<300).contains(response.statusCode), let envelope = try? RuntimeCoding.decoder.decode(RuntimeEnvelope<Value>.self, from: data) {
            return envelope.data
        }
        let code = (try? RuntimeCoding.decoder.decode(RuntimeErrorEnvelope.self, from: data).error.code) ?? "HTTP_\(response.statusCode)"
        throw RuntimeAuthError.rejected(code: code, status: response.statusCode)
    }

    private func makeRequest(path: String, body: [String: String]) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw RuntimeAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-CodexRemote-Request")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private var normalizedBaseURL: String { baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum RuntimeCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            if let date = fractional.date(from: value) ?? standard.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RFC3339 date")
        }
        return decoder
    }()
}
