import Foundation

@MainActor
final class MockRelayService: RelayServiceProtocol {
    private var continuation: AsyncStream<RelayEvent>.Continuation?
    private var playbackTask: Task<Void, Never>?
    private var activeProjectID = "project_codexremote"

    private let sampleProjects = [
        ProjectSummary(id: "project_codexremote", name: "codexremote", path: "/Users/leehooo/work/selftools/codexremote", threadCount: 4, updatedAt: Date()),
        ProjectSummary(id: "project_orders", name: "orders-api", path: "/Users/leehooo/work/orders-api", threadCount: 2, updatedAt: Date().addingTimeInterval(-3_600)),
        ProjectSummary(id: "project_storefront", name: "storefront", path: "/Users/leehooo/work/storefront", threadCount: 1, updatedAt: Date().addingTimeInterval(-8_000))
    ]

    func events() -> AsyncStream<RelayEvent> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    func connect() async {
        emit(.connection(.connecting))
        await pause(milliseconds: 350)
        emit(.connection(.connected))
        emit(.agent(name: "Lee's Mac Studio", state: .idle))
        emit(.projects(sampleProjects))
        emit(.output(LogEntry(stream: .system, text: "Relay connected. Three projects are available.")))
    }

    func configure(url _: String, reconnectAutomatically _: Bool) async {}

    func requestProjects() async { emit(.projects(sampleProjects)) }

    func requestThreads(projectID: String) async {
        activeProjectID = projectID
        let project = sampleProjects.first { $0.id == projectID }
        let threads = [
            ThreadSummary(id: "thread_recent", projectID: projectID, title: "Fix Relay reconnect policy", preview: "Review the reconnect behavior", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-420)),
            ThreadSummary(id: "thread_tests", projectID: projectID, title: "Stabilize integration tests", preview: "Run and repair failing tests", status: "idle", source: "cli", updatedAt: Date().addingTimeInterval(-7_200))
        ]
        emit(.threads(projectID: projectID, values: project == nil ? [] : threads))
    }

    func startTurn(projectID: String, threadID: String?, prompt _: String) async {
        activeProjectID = projectID
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()
            let selectedThreadID = threadID ?? "thread_\(UUID().uuidString.lowercased())"
            emit(.agent(name: "Lee's Mac Studio", state: .running))
            emit(.turnStarted(threadID: selectedThreadID, turnID: "turn_demo", startedAt: startedAt))
            emit(.output(LogEntry(stream: .system, text: "Codex opened \(projectName(projectID)).")))
            let script: [(LogStream, String, UInt64)] = [
                (.stdout, "Inspecting repository structure and active changes...", 420),
                (.stdout, "Reading project instructions and focused tests.", 520),
                (.assistant, "I found the reconnect state transition that needs correction.", 580),
                (.stdout, "Applying the change and running tests...", 620),
                (.assistant, "The focused tests pass and the change is ready for review.", 540)
            ]
            for (stream, text, delay) in script {
                guard !Task.isCancelled else { return }
                await pause(milliseconds: delay)
                guard !Task.isCancelled else { return }
                emit(.output(LogEntry(stream: stream, text: text)))
            }
            emit(.turnEnded(phase: .completed, result: TurnResult(title: "Turn completed", detail: "Tests pass and the reconnect behavior is corrected.", changedFiles: 3, duration: Date().timeIntervalSince(startedAt))))
            emit(.agent(name: "Lee's Mac Studio", state: .idle))
        }
    }

    func interruptTurn() async {
        playbackTask?.cancel()
        playbackTask = nil
        emit(.output(LogEntry(stream: .system, text: "Interruption requested.")))
        emit(.turnEnded(phase: .interrupted, result: TurnResult(title: "Turn interrupted", detail: "Codex stopped cleanly.", changedFiles: 0, duration: 12)))
        emit(.agent(name: "Lee's Mac Studio", state: .idle))
    }

    func loadScenario(_ scenario: DemoScenario) async {
        playbackTask?.cancel()
        emit(.reset)
        emit(.projects(sampleProjects))
        switch scenario {
        case .idle:
            emit(.connection(.connected)); emit(.agent(name: "Lee's Mac Studio", state: .idle))
        case .running:
            emit(.connection(.connected)); emit(.agent(name: "Lee's Mac Studio", state: .running)); emit(.turnStarted(threadID: "thread_recent", turnID: "turn_demo", startedAt: Date().addingTimeInterval(-74))); sampleLogs.forEach { emit(.output($0)) }
        case .completed:
            emit(.connection(.connected)); emit(.agent(name: "Lee's Mac Studio", state: .idle)); sampleLogs.forEach { emit(.output($0)) }; emit(.turnEnded(phase: .completed, result: TurnResult(title: "Turn completed", detail: "Tests pass and changes are ready.", changedFiles: 3, duration: 94)))
        case .failed:
            emit(.connection(.connected)); emit(.agent(name: "Lee's Mac Studio", state: .idle)); emit(.turnEnded(phase: .failed, result: TurnResult(title: "Turn failed", detail: "The build failed before completion.", changedFiles: 0, duration: 18)))
        case .offline:
            emit(.connection(.disconnected)); emit(.agent(name: "Lee's Mac Studio", state: .offline))
        }
    }

    private var sampleLogs: [LogEntry] {
        [LogEntry(stream: .system, text: "Codex opened codexremote."), LogEntry(stream: .stdout, text: "Inspecting repository structure..."), LogEntry(stream: .assistant, text: "I found the failing state transition.")]
    }

    private func projectName(_ id: String) -> String { sampleProjects.first { $0.id == id }?.name ?? "project" }
    private func emit(_ event: RelayEvent) { continuation?.yield(event) }
    private func pause(milliseconds: UInt64) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
}
