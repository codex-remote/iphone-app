import Foundation

@MainActor
final class WorkspaceViewModel: ObservableObject {
    private static let samplePrompt = "Review the current changes, fix any issues, and run the relevant tests."

    @Published var connectionState: ConnectionState = .connecting
    @Published var agentName = "Mac Agent"
    @Published var agentState: AgentState = .offline
    @Published var turnPhase: TurnPhase = .idle
    @Published var projects: [ProjectSummary] = []
    @Published var threads: [ThreadSummary] = []
    @Published var selectedProjectID: String?
    @Published var selectedThreadID: String?
    @Published var logs: [LogEntry] = []
    @Published var prompt = WorkspaceViewModel.samplePrompt
    @Published var submittedPrompt: String?
    @Published var startedAt: Date?
    @Published var result: TurnResult?
    @Published var relayURL = UserDefaults.standard.string(forKey: "relayURL") ?? "ws://192.168.68.125:8080/ws/app"
    @Published var reconnectAutomatically = UserDefaults.standard.object(forKey: "reconnectAutomatically") as? Bool ?? true
    @Published var consoleLimit = 500

    private let service: RelayServiceProtocol
    private var eventTask: Task<Void, Never>?

    init(service: RelayServiceProtocol, initialScenario: DemoScenario? = nil) {
        self.service = service
        if let initialScenario, initialScenario != .idle {
            submittedPrompt = Self.samplePrompt
            prompt = ""
        }
        eventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in service.events() { apply(event) }
        }
        Task {
            if let initialScenario {
                await service.loadScenario(initialScenario)
            } else {
                await service.connect()
            }
        }
    }

    var canRun: Bool {
        connectionState == .connected && agentState == .idle && selectedProjectID != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isRunning: Bool { turnPhase == .running }
    var selectedProject: ProjectSummary? { projects.first { $0.id == selectedProjectID } }
    var selectedThread: ThreadSummary? { threads.first { $0.id == selectedThreadID } }

    func primaryAction() {
        Task {
            if isRunning {
                await service.interruptTurn()
            } else if canRun, let selectedProjectID {
                let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                submittedPrompt = instruction
                prompt = ""
                await service.startTurn(projectID: selectedProjectID, threadID: selectedThreadID, prompt: instruction)
            }
        }
    }

    func selectProject(_ projectID: String) {
        guard projectID != selectedProjectID else { return }
        selectedProjectID = projectID
        selectedThreadID = nil
        threads = []
        Task { await service.requestThreads(projectID: projectID) }
    }

    func selectThread(_ threadID: String?) { selectedThreadID = threadID }
    func refreshProjects() { Task { await service.requestProjects() } }
    func applySettings() { Task { await service.configure(url: relayURL, reconnectAutomatically: reconnectAutomatically) } }

    func loadScenario(_ scenario: DemoScenario) {
        if scenario == .idle {
            submittedPrompt = nil
            if prompt.isEmpty { prompt = Self.samplePrompt }
        } else {
            submittedPrompt = Self.samplePrompt
            prompt = ""
        }
        Task { await service.loadScenario(scenario) }
    }

    func clearConsole() { logs.removeAll() }

    private func apply(_ event: RelayEvent) {
        switch event {
        case .connection(let state):
            connectionState = state
        case .agent(let name, let state):
            agentName = name
            agentState = state
        case .projects(let values):
            projects = values
            let nextID = values.contains { $0.id == selectedProjectID } ? selectedProjectID : values.first?.id
            if nextID != selectedProjectID {
                selectedProjectID = nextID
                selectedThreadID = nil
            }
            if let nextID { Task { await service.requestThreads(projectID: nextID) } }
        case .threads(let projectID, let values):
            guard projectID == selectedProjectID else { return }
            threads = values
            if let selectedThreadID, !values.contains(where: { $0.id == selectedThreadID }) {
                self.selectedThreadID = nil
            }
        case .turnStarted(let threadID, _, let date):
            turnPhase = .running
            selectedThreadID = threadID
            startedAt = date
            result = nil
        case .output(let entry):
            logs.append(entry)
            if logs.count > consoleLimit { logs.removeFirst(logs.count - consoleLimit) }
        case .turnEnded(let phase, let turnResult):
            turnPhase = phase
            result = turnResult
            if let selectedProjectID { Task { await service.requestThreads(projectID: selectedProjectID) } }
        case .reset:
            turnPhase = .idle
            logs.removeAll()
            startedAt = nil
            result = nil
        }
    }
}
