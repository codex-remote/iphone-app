import Foundation
import UIKit

enum ThreadListLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum ProjectListLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum ThreadDetailLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum ConnectionTestState: Equatable {
    case idle
    case testing
    case succeeded(RelayConnectionTestResult)
    case failed(String)
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    private static let transcriptCacheLimit = 2

    @Published var connectionState: ConnectionState = .connecting
    @Published var agentName = "Mac Agent"
    @Published var agentState: AgentState = .offline
    @Published private(set) var executionCapabilities: ExecutionCapabilities?
    @Published private(set) var executionProfilesByProjectID: [String: [ExecutionProfile]] = [:]
    @Published private(set) var executionProfileLoadStatesByProjectID: [String: ThreadListLoadState] = [:]
    @Published private(set) var selectedExecutionProfileIDByProjectID: [String: String] = [:]
    @Published var projects: [ProjectSummary] = []
    @Published private(set) var projectLoadState: ProjectListLoadState = .idle
    @Published var threads: [ThreadSummary] = []
    @Published private(set) var threadsByProjectID: [String: [ThreadSummary]] = [:]
    @Published private(set) var threadLoadStatesByProjectID: [String: ThreadListLoadState] = [:]
    @Published private(set) var threadTranscriptsByKey: [String: ThreadTranscript] = [:]
    @Published private(set) var threadDetailLoadStatesByKey: [String: ThreadDetailLoadState] = [:]
    @Published var selectedProjectID: String?
    @Published var selectedThreadID: String?
    @Published var connectionProfile: RelayConnectionProfile
    @Published var relayURL: String
    @Published var connectionEnabled: Bool {
        didSet {
            guard oldValue != connectionEnabled else { return }
            connectionEnabledDidChange()
        }
    }
    @Published private(set) var connectionTestState: ConnectionTestState = .idle
    @Published var consoleLimit = 500
    @Published private(set) var isTurnRunning = false

    let turnSession = TurnSessionStore()

    private let service: RelayServiceProtocol
    private var eventTask: Task<Void, Never>?
    private var connectionTestTask: Task<Void, Never>?
    private var pendingThreadReadKey: String?
    private var loadedThreadReadKey: String?
    private var transcriptCacheOrder: [String] = []
    private var memoryWarningObserver: NSObjectProtocol?

    init(service: RelayServiceProtocol) {
        let defaults = UserDefaults.standard
        let rawSavedProfile = defaults.string(forKey: "relayConnectionProfile")
        let savedProfile = rawSavedProfile.flatMap(RelayConnectionProfile.init(rawValue:)) ?? RelayConnectionProfile.current
        connectionProfile = savedProfile
        relayURL = defaults.string(forKey: savedProfile.urlDefaultsKey) ?? savedProfile.defaultURL
        connectionEnabled = defaults.object(forKey: "relayConnectionEnabled") as? Bool ?? true
        self.service = service
        if let bootstrapState = service.bootstrapState {
            connectionState = bootstrapState.connectionState
            agentName = bootstrapState.agentName
            agentState = bootstrapState.agentState
            executionCapabilities = bootstrapState.capabilities
            projects = bootstrapState.projects
            threads = bootstrapState.threads
            selectedProjectID = bootstrapState.selectedProjectID
            if bootstrapState.projects.isEmpty {
                projectLoadState = bootstrapState.connectionState == .connected
                    && bootstrapState.agentState != .offline
                    ? .loading
                    : .idle
            } else {
                projectLoadState = .loaded
            }
            if let selectedProjectID {
                threadsByProjectID[selectedProjectID] = bootstrapState.threads
                threadLoadStatesByProjectID[selectedProjectID] = .loaded
            }
        }
        let events = service.events()
        eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                apply(event)
            }
        }
        MemoryDiagnostics.shared.setSnapshotProvider { [weak self] in
            self?.memoryDiagnosticSnapshot() ?? MemoryDiagnostics.Snapshot(
                projects: 0,
                threads: 0,
                cachedTranscripts: 0,
                transcriptMessages: 0,
                liveItems: 0,
                liveCharacters: 0,
                consoleEntries: 0
            )
        }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.releaseRecreatableMemory() }
        }
        Task {
            await Task.yield()
            if connectionEnabled {
                await service.connect()
            } else {
                await service.disconnect()
            }
        }
    }

    var canStartTurn: Bool {
        connectionState == .connected
            && agentState == .idle
            && selectedProjectID != nil
            && executionProfileSelectionIsReady
    }

    var isRunning: Bool { isTurnRunning }
    var selectedProject: ProjectSummary? { projects.first { $0.id == selectedProjectID } }
    var selectedExecutionProfile: ExecutionProfile? {
        guard let selectedProjectID,
              let profileID = selectedExecutionProfileIDByProjectID[selectedProjectID] else { return nil }
        return executionProfilesByProjectID[selectedProjectID]?.first { $0.id == profileID }
    }
    var availableExecutionProfiles: [ExecutionProfile] {
        guard let selectedProjectID else { return [] }
        return executionProfilesByProjectID[selectedProjectID] ?? []
    }
    func threads(for projectID: String) -> [ThreadSummary] { threadsByProjectID[projectID] ?? [] }
    func threadLoadState(for projectID: String) -> ThreadListLoadState { threadLoadStatesByProjectID[projectID] ?? .idle }
    func threadTranscript(projectID: String, threadID: String) -> ThreadTranscript? {
        threadTranscriptsByKey[threadDetailKey(projectID: projectID, threadID: threadID)]
    }
    func threadDetailLoadState(projectID: String, threadID: String) -> ThreadDetailLoadState { threadDetailLoadStatesByKey[threadDetailKey(projectID: projectID, threadID: threadID)] ?? .idle }

    func startTurn(prompt submittedPrompt: String) {
        Task {
            if canStartTurn, let selectedProjectID {
                let instruction = submittedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else { return }
                turnSession.prepareSubmission(instruction)
                let profileID = executionCapabilities?.supportsPermissionProfiles == true
                    ? selectedExecutionProfileIDByProjectID[selectedProjectID]
                    : nil
                await service.startTurn(
                    projectID: selectedProjectID,
                    threadID: selectedThreadID,
                    prompt: instruction,
                    permissionProfileID: profileID
                )
            }
        }
    }

    func interruptTurn() {
        guard isRunning else { return }
        Task { await service.interruptTurn() }
    }

    func selectProject(_ projectID: String) {
        if projectID != selectedProjectID {
            selectedProjectID = projectID
            selectedThreadID = nil
            threads = threadsByProjectID[projectID] ?? []
        }
        ensureThreadsLoaded(projectID: projectID)
        ensureExecutionProfilesLoaded(projectID: projectID)
    }

    func selectExecutionProfile(_ profileID: String) {
        guard let projectID = selectedProjectID,
              executionProfilesByProjectID[projectID]?.contains(where: { $0.id == profileID && $0.allowed }) == true else { return }
        selectedExecutionProfileIDByProjectID[projectID] = profileID
        UserDefaults.standard.set(profileID, forKey: executionProfileDefaultsKey(projectID))
    }

    func selectThread(_ threadID: String?) { selectedThreadID = threadID }
    func refreshProjects() {
        guard connectionState == .connected, agentState != .offline else {
            projectLoadState = .idle
            return
        }
        projectLoadState = .loading
        Task { await service.requestProjects() }
    }

    func selectConnectionProfile(_ profile: RelayConnectionProfile) {
        guard profile != connectionProfile else { return }
        let defaults = UserDefaults.standard
        defaults.set(relayURL, forKey: connectionProfile.urlDefaultsKey)
        connectionProfile = profile
        defaults.set(profile.rawValue, forKey: "relayConnectionProfile")
        relayURL = defaults.string(forKey: profile.urlDefaultsKey) ?? profile.defaultURL
        disableConnection()
    }

    func connectionSettingsDidChange() {
        guard connectionTestState != .testing else { return }
        connectionTestState = .idle
        if connectionEnabled || connectionState != .disconnected {
            disableConnection()
        }
    }

    private func connectionEnabledDidChange() {
        if connectionEnabled {
            testConnection()
        } else {
            let preservesFailure: Bool
            if case .failed = connectionTestState {
                preservesFailure = true
            } else {
                preservesFailure = false
            }
            disconnectConnection(preservingFeedback: preservesFailure)
        }
    }

    private func testConnection() {
        guard connectionTestState != .testing else { return }
        connectionTestTask?.cancel()
        clearConnectionData()
        connectionTestState = .testing
        let url = relayURL
        connectionTestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await service.testConnection(url: url)
                guard !Task.isCancelled else { return }
                saveConnectionSettings()
                UserDefaults.standard.set(true, forKey: "relayConnectionEnabled")
                connectionTestState = .succeeded(result)
            } catch {
                guard !Task.isCancelled else { return }
                let nsError = error as NSError
                Diagnostics.shared.record(
                    .relayConnectionTestCompleted,
                    level: .error,
                    category: .relay,
                    fields: [
                        .errorDomain: .string(nsError.domain),
                        .errorCode: .integer(nsError.code)
                    ]
                )
                connectionTestState = .failed(error.localizedDescription)
                connectionEnabled = false
            }
        }
    }

    private func disableConnection() {
        if connectionEnabled {
            connectionEnabled = false
        } else {
            disconnectConnection()
        }
    }

    private func disconnectConnection(preservingFeedback: Bool = false) {
        connectionTestTask?.cancel()
        connectionTestTask = nil
        UserDefaults.standard.set(false, forKey: "relayConnectionEnabled")
        if !preservingFeedback {
            connectionTestState = .idle
        }
        clearConnectionData()
        Task { await service.disconnect() }
    }

    func refreshThreads(projectID: String) {
        ensureThreadsLoaded(projectID: projectID, force: true)
    }

    func refreshThreadDetail(projectID: String, threadID: String) {
        ensureThreadDetailLoaded(projectID: projectID, threadID: threadID, force: true)
    }

    func ensureThreadsLoaded(projectID: String, force: Bool = false) {
        guard projects.contains(where: { $0.id == projectID }) else { return }
        let currentState = threadLoadState(for: projectID)
        guard force || (currentState != .loading && currentState != .loaded) else { return }
        threadLoadStatesByProjectID[projectID] = .loading
        Task { await service.requestThreads(projectID: projectID) }
    }

    func ensureExecutionProfilesLoaded(projectID: String, force: Bool = false) {
        guard executionCapabilities?.supportsPermissionProfiles == true,
              projects.contains(where: { $0.id == projectID }) else { return }
        let state = executionProfileLoadStatesByProjectID[projectID] ?? .idle
        guard force || (state != .loading && state != .loaded) else { return }
        executionProfileLoadStatesByProjectID[projectID] = .loading
        Task { await service.requestExecutionProfiles(projectID: projectID) }
    }

    func prepareNewTask(projectID: String) {
        if selectedProjectID != projectID { selectProject(projectID) }
        selectedThreadID = nil
        pendingThreadReadKey = nil
        loadedThreadReadKey = nil
        resetTurn()
    }

    func prepareThread(projectID: String, threadID: String) {
        if selectedProjectID != projectID { selectProject(projectID) }
        let key = "\(projectID):\(threadID)"
        selectedThreadID = threadID
        resetTurn()
        if threadTranscriptsByKey[key] != nil {
            touchTranscript(key)
            loadedThreadReadKey = key
        }
        ensureThreadDetailLoaded(projectID: projectID, threadID: threadID)
    }

    func clearConsole() { turnSession.clearLogs() }

    private func saveConnectionSettings() {
        let defaults = UserDefaults.standard
        defaults.set(connectionProfile.rawValue, forKey: "relayConnectionProfile")
        defaults.set(relayURL, forKey: connectionProfile.urlDefaultsKey)
    }

    private func clearConnectionData() {
        connectionState = .disconnected
        agentState = .offline
        projects.removeAll()
        projectLoadState = .idle
        threads.removeAll()
        threadsByProjectID.removeAll()
        threadLoadStatesByProjectID.removeAll()
        threadTranscriptsByKey.removeAll()
        transcriptCacheOrder.removeAll()
        threadDetailLoadStatesByKey.removeAll()
        executionProfilesByProjectID.removeAll()
        executionProfileLoadStatesByProjectID.removeAll()
        selectedExecutionProfileIDByProjectID.removeAll()
        selectedProjectID = nil
        selectedThreadID = nil
        pendingThreadReadKey = nil
        loadedThreadReadKey = nil
        resetTurn()
    }

    private func resetTurn() {
        turnSession.reset()
        isTurnRunning = false
    }

    private func releaseRecreatableMemory() {
        let currentKey = selectedProjectID.flatMap { projectID in
            selectedThreadID.map { threadDetailKey(projectID: projectID, threadID: $0) }
        }
        threadTranscriptsByKey = threadTranscriptsByKey.filter { $0.key == currentKey }
        transcriptCacheOrder = currentKey.flatMap { threadTranscriptsByKey[$0] == nil ? nil : [$0] } ?? []
        threadDetailLoadStatesByKey = threadDetailLoadStatesByKey.filter {
            $0.key == currentKey || $0.value == .loading
        }
        turnSession.clearLogs()
        MemoryDiagnostics.shared.checkpoint("memory-warning-cleanup")
    }

    private func memoryDiagnosticSnapshot() -> MemoryDiagnostics.Snapshot {
        MemoryDiagnostics.Snapshot(
            projects: projects.count,
            threads: threadsByProjectID.values.reduce(0) { $0 + $1.count },
            cachedTranscripts: threadTranscriptsByKey.count,
            transcriptMessages: threadTranscriptsByKey.values.reduce(0) { $0 + $1.messages.count },
            liveItems: turnSession.items.count,
            liveCharacters: turnSession.retainedCharacterCount,
            consoleEntries: turnSession.logs.count
        )
    }

    private func apply(_ event: RelayEvent) {
        switch event {
        case .connection(let state):
            connectionState = state
            switch state {
            case .connecting:
                projectLoadState = .idle
            case .connected where projects.isEmpty && agentState != .offline:
                projectLoadState = .loading
            case .disconnected where projects.isEmpty:
                projectLoadState = .idle
            default:
                break
            }
        case .agent(let name, let state):
            agentName = name
            agentState = state
            if state == .offline {
                projectLoadState = .idle
            } else if connectionState == .connected && projects.isEmpty {
                projectLoadState = .loading
            }
            if state == .offline, isTurnRunning {
                turnSession.markConnectionLost()
                isTurnRunning = false
            }
        case .capabilities(let value):
            executionCapabilities = value
            if value?.supportsPermissionProfiles == true, let selectedProjectID {
                ensureExecutionProfilesLoaded(projectID: selectedProjectID)
            }
        case .executionProfiles(let snapshot):
            let allowedProfiles = snapshot.profiles.filter(\.allowed)
            executionProfilesByProjectID[snapshot.projectID] = allowedProfiles
            executionProfileLoadStatesByProjectID[snapshot.projectID] = .loaded
            let saved = UserDefaults.standard.string(forKey: executionProfileDefaultsKey(snapshot.projectID))
            let selectedID: String?
            if let saved, allowedProfiles.contains(where: { $0.id == saved }) {
                selectedID = saved
            } else if allowedProfiles.contains(where: { $0.id == snapshot.defaultProfileID }) {
                selectedID = snapshot.defaultProfileID
            } else {
                selectedID = allowedProfiles.first?.id
            }
            if let selectedID {
                selectedExecutionProfileIDByProjectID[snapshot.projectID] = selectedID
            } else {
                selectedExecutionProfileIDByProjectID.removeValue(forKey: snapshot.projectID)
            }
        case .executionProfilesFailed(let projectID, let message):
            executionProfileLoadStatesByProjectID[projectID] = .failed
            executionProfilesByProjectID.removeValue(forKey: projectID)
            selectedExecutionProfileIDByProjectID.removeValue(forKey: projectID)
            turnSession.appendOutput(LogEntry(stream: .stderr, text: message), consoleLimit: consoleLimit)
        case .projects(let values):
            projects = values
            projectLoadState = .loaded
            let validProjectIDs = Set(values.map(\.id))
            threadsByProjectID = threadsByProjectID.filter { validProjectIDs.contains($0.key) }
            threadLoadStatesByProjectID = threadLoadStatesByProjectID.filter { validProjectIDs.contains($0.key) }
            threadTranscriptsByKey = threadTranscriptsByKey.filter { validProjectIDs.contains(projectID(fromThreadDetailKey: $0.key)) }
            transcriptCacheOrder.removeAll { threadTranscriptsByKey[$0] == nil }
            threadDetailLoadStatesByKey = threadDetailLoadStatesByKey.filter { validProjectIDs.contains(projectID(fromThreadDetailKey: $0.key)) }
            executionProfilesByProjectID = executionProfilesByProjectID.filter { validProjectIDs.contains($0.key) }
            executionProfileLoadStatesByProjectID = executionProfileLoadStatesByProjectID.filter { validProjectIDs.contains($0.key) }
            selectedExecutionProfileIDByProjectID = selectedExecutionProfileIDByProjectID.filter { validProjectIDs.contains($0.key) }
            let nextID = values.contains { $0.id == selectedProjectID } ? selectedProjectID : values.first?.id
            if nextID != selectedProjectID {
                selectedProjectID = nextID
                selectedThreadID = nil
            }
            if let nextID {
                threads = threadsByProjectID[nextID] ?? []
                ensureThreadsLoaded(projectID: nextID)
                ensureExecutionProfilesLoaded(projectID: nextID)
            } else {
                threads = []
            }
        case .projectsFailed(let message):
            projectLoadState = .failed
            turnSession.appendOutput(LogEntry(stream: .stderr, text: message), consoleLimit: consoleLimit)
        case .threads(let projectID, let values):
            threadsByProjectID[projectID] = values
            threadLoadStatesByProjectID[projectID] = .loaded
            if projectID == selectedProjectID {
                threads = values
                if let selectedThreadID, !values.contains(where: { $0.id == selectedThreadID }) {
                    self.selectedThreadID = nil
                }
            }
        case .threadsFailed(let projectID, let message):
            threadLoadStatesByProjectID[projectID] = .failed
            turnSession.appendOutput(LogEntry(stream: .stderr, text: message), consoleLimit: consoleLimit)
        case .threadDetail(let projectID, let value, let truncated):
            let key = threadDetailKey(projectID: projectID, threadID: value.id)
            if pendingThreadReadKey == key { pendingThreadReadKey = nil }
            cacheTranscript(ThreadTranscript(detail: value, sourceTruncated: truncated), for: key)
            threadDetailLoadStatesByKey[key] = .loaded
            guard projectID == selectedProjectID, value.id == selectedThreadID else { return }
            loadedThreadReadKey = key
            turnSession.reconcile(with: value, detailTruncated: truncated)
        case .threadDetailFailed(let projectID, let threadID, let message):
            let key = threadDetailKey(projectID: projectID, threadID: threadID)
            if pendingThreadReadKey == key { pendingThreadReadKey = nil }
            if loadedThreadReadKey == key { loadedThreadReadKey = nil }
            threadDetailLoadStatesByKey[key] = .failed
            guard projectID == selectedProjectID, threadID == selectedThreadID else { return }
            turnSession.appendOutput(LogEntry(stream: .stderr, text: message), consoleLimit: consoleLimit)
        case .turnStarted(let threadID, let turnID, let date):
            selectedThreadID = threadID
            turnSession.started(turnID: turnID, at: date)
            isTurnRunning = true
        case .turnSnapshot(let threadID, let turnID, let date, let items, let sequence, let itemsTruncated, let recentOutput):
            selectedThreadID = threadID
            turnSession.restored(
                turnID: turnID,
                at: date,
                items: items,
                sequence: sequence,
                itemsTruncated: itemsTruncated,
                recentOutput: recentOutput,
                consoleLimit: consoleLimit
            )
            isTurnRunning = true
        case .turnItemStarted(let turnID, let sequence, let item):
            turnSession.itemStarted(turnID: turnID, sequence: sequence, item: item)
        case .turnItemDelta(let turnID, let sequence, let itemID, let field, let delta):
            turnSession.appendDelta(turnID: turnID, sequence: sequence, itemID: itemID, field: field, delta: delta)
        case .turnItemCompleted(let turnID, let sequence, let item):
            turnSession.itemCompleted(turnID: turnID, sequence: sequence, item: item)
        case .output(let entry):
            turnSession.appendOutput(entry, consoleLimit: consoleLimit)
        case .turnEnded(let traceID, let turnID, let phase, let turnResult):
            turnSession.end(phase: phase, result: turnResult)
            isTurnRunning = false
            if let traceID, let turnID {
                Task { await service.acknowledgeTurn(traceID: traceID, turnID: turnID, phase: phase) }
            }
            if let selectedProjectID { refreshThreads(projectID: selectedProjectID) }
            if let selectedProjectID, let selectedThreadID {
                refreshThreadDetail(projectID: selectedProjectID, threadID: selectedThreadID)
            }
        case .reset:
            resetTurn()
        }
    }

    private var executionProfileSelectionIsReady: Bool {
        guard executionCapabilities?.supportsPermissionProfiles == true else { return true }
        guard let selectedProjectID else { return false }
        return selectedExecutionProfileIDByProjectID[selectedProjectID] != nil
    }

    private func executionProfileDefaultsKey(_ projectID: String) -> String {
        "executionPermissionProfile.\(projectID)"
    }

    private func ensureThreadDetailLoaded(projectID: String, threadID: String, force: Bool = false) {
        let key = threadDetailKey(projectID: projectID, threadID: threadID)
        let currentState = threadDetailLoadStatesByKey[key] ?? .idle
        guard force || (currentState != .loading && currentState != .loaded) else { return }
        pendingThreadReadKey = key
        threadDetailLoadStatesByKey[key] = .loading
        Task { await service.requestThread(projectID: projectID, threadID: threadID) }
    }

    private func threadDetailKey(projectID: String, threadID: String) -> String {
        "\(projectID):\(threadID)"
    }

    private func projectID(fromThreadDetailKey key: String) -> String {
        key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
    }

    private func cacheTranscript(_ transcript: ThreadTranscript, for key: String) {
        threadTranscriptsByKey[key] = transcript
        touchTranscript(key)

        while transcriptCacheOrder.count > Self.transcriptCacheLimit {
            let evictedKey = transcriptCacheOrder.removeFirst()
            threadTranscriptsByKey.removeValue(forKey: evictedKey)
            threadDetailLoadStatesByKey[evictedKey] = .idle
        }
    }

    private func touchTranscript(_ key: String) {
        transcriptCacheOrder.removeAll { $0 == key }
        transcriptCacheOrder.append(key)
    }

}
