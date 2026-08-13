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
        case .simulator: 18_767
        case .iPhone: 18_768
        }
    }

    var defaultURL: String { "ws://127.0.0.1:\(defaultPort)/ws/app" }
    var urlDefaultsKey: String { "relayURL.\(rawValue)" }

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
    func startTurn(projectID: String, threadID: String?, prompt: String, permissionProfileID: String?) async
    func interruptTurn() async
    func acknowledgeTurn(traceID: String, turnID: String, phase: TurnPhase) async
}

extension RelayServiceProtocol {
    var bootstrapState: RelayBootstrapState? { nil }
}
