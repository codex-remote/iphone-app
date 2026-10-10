import Foundation

@MainActor
final class RelayEventBuffer {
    private static let limit = 64
    private var continuation: AsyncStream<RelayEvent>.Continuation?

    func stream() -> AsyncStream<RelayEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(Self.limit)) { continuation in
            self.continuation = continuation
        }
    }

    func yield(_ event: RelayEvent) {
        guard case .dropped = continuation?.yield(event) else { return }
        MemoryDiagnostics.shared.recordDroppedRelayEvent()
    }
}

enum RelayConnectionProfile: String, CaseIterable, Identifiable, Sendable {
    case simulator
    case iPhone

    var id: String { rawValue }

    var defaultPort: Int {
        switch self {
        case .simulator, .iPhone: 18_874
        }
    }

    var defaultURL: String { "http://127.0.0.1:\(defaultPort)" }
    var urlDefaultsKey: String { "runtimeURL.\(rawValue)" }

    static var current: RelayConnectionProfile {
#if targetEnvironment(simulator)
        .simulator
#else
        .iPhone
#endif
    }
}

struct RelayConnectionTestResult: Equatable, Sendable {
    let agentConnected: Bool
}

struct RelayBootstrapState: Sendable {
    let connectionState: ConnectionState
    let agentName: String
    let agentState: AgentState
    let capabilities: ExecutionCapabilities?
    let projects: [ProjectSummary]
    let threads: [ThreadSummary]
    let selectedProjectID: String?
}

@MainActor
protocol RelayServiceProtocol: AnyObject {
    var bootstrapState: RelayBootstrapState? { get }
    func events() -> AsyncStream<RelayEvent>
    func connect() async
    func disconnect() async
    func testConnection(url: String) async throws -> RelayConnectionTestResult
    func requestProjects() async
    func requestExecutionProfiles(projectID: String) async
    func requestThreads(projectID: String) async
    func requestThread(projectID: String, threadID: String) async
    func selectContext(projectID: String, threadID: String?)
    func startTurn(projectID: String, threadID: String?, prompt: String, permissionProfileID: String?) async
    func interruptTurn() async
    func acknowledgeTurn(traceID: String, turnID: String, phase: TurnPhase) async
    func pair(codeOrLink: String) async
    func signOut() async
    func suspend() async
    func resume() async
}

extension RelayServiceProtocol {
    var bootstrapState: RelayBootstrapState? { nil }
    func pair(codeOrLink: String) async {}
    func signOut() async {}
    func selectContext(projectID: String, threadID: String?) {}
    func suspend() async {}
    func resume() async { await connect() }
}
