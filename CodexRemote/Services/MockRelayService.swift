import Foundation

@MainActor
final class MockRelayService: RelayServiceProtocol {
    private let eventBuffer = RelayEventBuffer()
    private var playbackTask: Task<Void, Never>?
    private var activeProjectID = "project_codexremote"

    private let sampleCapabilities = ExecutionCapabilities(
        restricted: true,
        sandboxMode: "workspace-write",
        approvalPolicy: "never",
        writableScope: "selected_project",
        networkAccess: false,
        canRequestApproval: false,
        hostProcessControl: false,
        userLibraryWrite: false,
        xcodeDeviceControl: false,
        supportsPermissionProfiles: true
    )

    private let sampleProfiles = [
        ExecutionProfile(id: ":read-only", description: nil, allowed: true),
        ExecutionProfile(id: ":workspace", description: nil, allowed: true),
        ExecutionProfile(id: ":danger-full-access", description: nil, allowed: true)
    ]

    private let sampleProjects = [
        ProjectSummary(id: "project_codexremote", name: "codexremote", path: "/Users/leehooo/work/selftools/codexremote", threadCount: 8, updatedAt: Date()),
        ProjectSummary(id: "project_orders", name: "orders-api", path: "/Users/leehooo/work/orders-api", threadCount: 2, updatedAt: Date().addingTimeInterval(-3_600)),
        ProjectSummary(id: "project_storefront", name: "storefront", path: "/Users/leehooo/work/storefront", threadCount: 1, updatedAt: Date().addingTimeInterval(-8_000)),
        ProjectSummary(id: "project_design_system", name: "design-system", path: "/Users/leehooo/work/design-system", threadCount: 3, updatedAt: Date().addingTimeInterval(-14_400)),
        ProjectSummary(id: "project_mobile_agent", name: "mobile-agent", path: "/Users/leehooo/work/mobile-agent", threadCount: 5, updatedAt: Date().addingTimeInterval(-21_600)),
        ProjectSummary(id: "project_relay_server", name: "relay-server", path: "/Users/leehooo/work/relay-server", threadCount: 4, updatedAt: Date().addingTimeInterval(-32_000)),
        ProjectSummary(id: "project_docs", name: "docs", path: "/Users/leehooo/work/docs", threadCount: 2, updatedAt: Date().addingTimeInterval(-44_000)),
        ProjectSummary(id: "project_lab", name: "experiments-lab", path: "/Users/leehooo/work/experiments-lab", threadCount: 6, updatedAt: Date().addingTimeInterval(-62_000))
    ]

    var bootstrapState: RelayBootstrapState? {
        if ProcessInfo.processInfo.arguments.contains("--demo-offline") {
            return RelayBootstrapState(
                connectionState: .disconnected,
                agentName: "Lee's Mac Studio",
                agentState: .offline,
                capabilities: nil,
                projects: [],
                threads: [],
                selectedProjectID: nil
            )
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-project-loading") {
            return RelayBootstrapState(
                connectionState: .connected,
                agentName: "Lee's Mac Studio",
                agentState: .idle,
                capabilities: sampleCapabilities,
                projects: [],
                threads: [],
                selectedProjectID: nil
            )
        }
        let projectID = sampleProjects[0].id
        return RelayBootstrapState(
            connectionState: .connected,
            agentName: "Lee's Mac Studio",
            agentState: .idle,
            capabilities: sampleCapabilities,
            projects: sampleProjects,
            threads: sampleThreads(projectID: projectID),
            selectedProjectID: projectID
        )
    }

    func events() -> AsyncStream<RelayEvent> {
        eventBuffer.stream()
    }

    func connect() async {
        if ProcessInfo.processInfo.arguments.contains("--demo-offline") {
            emit(.connection(.disconnected))
            emit(.agent(name: "Lee's Mac Studio", state: .offline))
            emit(.capabilities(nil))
            return
        }
        emit(.connection(.connecting))
        await pause(milliseconds: 350)
        emit(.connection(.connected))
        emit(.agent(name: "Lee's Mac Studio", state: .idle))
        emit(.capabilities(sampleCapabilities))
        if ProcessInfo.processInfo.arguments.contains("--demo-project-loading") {
            await pause(milliseconds: 5_000)
        }
        emit(.projects(sampleProjects))
        emit(.output(LogEntry(stream: .system, text: "Relay connected. Three projects are available.")))
    }

    func disconnect() async {
        playbackTask?.cancel()
        emit(.connection(.disconnected))
        emit(.agent(name: "Lee's Mac Studio", state: .offline))
        emit(.capabilities(nil))
    }

    func testConnection(url _: String) async throws -> RelayConnectionTestResult {
        emit(.connection(.disconnected))
        emit(.agent(name: "Lee's Mac Studio", state: .offline))
        emit(.capabilities(nil))
        await pause(milliseconds: 300)
        emit(.connection(.connecting))
        await pause(milliseconds: 150)
        emit(.connection(.connected))
        emit(.agent(name: "Lee's Mac Studio", state: .idle))
        emit(.capabilities(sampleCapabilities))
        emit(.projects(sampleProjects))
        return RelayConnectionTestResult(agentConnected: true)
    }

    func requestProjects() async { emit(.projects(sampleProjects)) }

    func requestExecutionProfiles(projectID: String) async {
        emit(.executionProfiles(ExecutionProfileSnapshot(projectID: projectID, defaultProfileID: ":workspace", profiles: sampleProfiles)))
    }

    func requestThreads(projectID: String) async {
        activeProjectID = projectID
        let project = sampleProjects.first { $0.id == projectID }
        let threads = sampleThreads(projectID: projectID)
        emit(.threads(projectID: projectID, values: project == nil ? [] : threads))
    }

    func requestThread(projectID: String, threadID: String) async {
        let now = Date()
        let items = [
            ThreadHistoryItem(id: "item-user", type: "userMessage", role: "user", phase: nil, status: nil, text: "Review the reconnect behavior.", name: nil, command: nil, cwd: nil, output: nil, path: nil, query: nil, exitCode: nil, durationMS: nil, changes: nil, truncated: false),
            ThreadHistoryItem(id: "item-reasoning", type: "reasoning", role: "assistant", phase: nil, status: nil, text: "Checked the reconnect state machine and found a stale transition.", name: nil, command: nil, cwd: nil, output: nil, path: nil, query: nil, exitCode: nil, durationMS: nil, changes: nil, truncated: false),
            ThreadHistoryItem(id: "item-tool", type: "commandExecution", role: nil, phase: nil, status: "completed", text: nil, name: nil, command: "xcodebuild build", cwd: "/Users/leehooo/work/selftools/codexremote/iphone-app", output: "Build succeeded.", path: nil, query: nil, exitCode: 0, durationMS: 12_000, changes: nil, truncated: false),
            ThreadHistoryItem(id: "item-agent", type: "agentMessage", role: "assistant", phase: "final_answer", status: nil, text: "The reconnect transition is corrected and tests pass.", name: nil, command: nil, cwd: nil, output: nil, path: nil, query: nil, exitCode: nil, durationMS: nil, changes: nil, truncated: false)
        ]
        let turn = ThreadHistoryTurn(id: "turn-demo", status: "completed", startedAt: now.addingTimeInterval(-30), completedAt: now, durationMS: 30_000, error: nil, items: items, truncated: false)
        let summary = sampleThreads(projectID: projectID).first { $0.id == threadID }
        let turns = ProcessInfo.processInfo.arguments.contains("--demo-long-history")
            ? longHistoryTurns(endingAt: now)
            : [turn]
        let detail = ThreadDetail(id: threadID, projectID: projectID, title: summary?.title ?? "Session", preview: summary?.preview ?? "", status: summary?.status ?? "idle", source: summary?.source ?? "appServer", createdAt: now.addingTimeInterval(-3_600), updatedAt: now, turns: turns)
        emit(.threadDetail(projectID: projectID, value: detail, truncated: false))
    }

    func startTurn(projectID: String, threadID: String?, prompt _: String, permissionProfileID _: String?) async {
        activeProjectID = projectID
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()
            let selectedThreadID = threadID ?? "thread_\(UUID().uuidString.lowercased())"
            emit(.agent(name: "Lee's Mac Studio", state: .running))
            emit(.turnStarted(threadID: selectedThreadID, turnID: "turn_demo", startedAt: startedAt))
            var sequence: Int64 = 1
            let reasoning = liveItem(id: "item-reasoning", type: "reasoning", status: "inProgress")
            emit(.turnItemStarted(turnID: "turn_demo", sequence: sequence, item: reasoning))
            sequence += 1
            emit(.turnItemDelta(turnID: "turn_demo", sequence: sequence, itemID: reasoning.id, field: "text", delta: "Inspecting repository structure and active changes."))
            await pause(milliseconds: turnPlaybackDelay(420))
            var completedReasoning = reasoning
            completedReasoning.status = "completed"
            completedReasoning.text = "Inspecting repository structure and active changes."
            sequence += 1
            emit(.turnItemCompleted(turnID: "turn_demo", sequence: sequence, item: completedReasoning))

            let command = liveItem(id: "item-command", type: "commandExecution", status: "inProgress", command: "xcodebuild -scheme CodexRemote build")
            sequence += 1
            emit(.turnItemStarted(turnID: "turn_demo", sequence: sequence, item: command))
            let commandChunks = ["Reading project instructions...\n", "Building CodexRemote...\n", "Build succeeded.\n"]
            for chunk in commandChunks {
                guard !Task.isCancelled else { return }
                await pause(milliseconds: turnPlaybackDelay(360))
                guard !Task.isCancelled else { return }
                sequence += 1
                emit(.turnItemDelta(turnID: "turn_demo", sequence: sequence, itemID: command.id, field: "output", delta: chunk))
            }
            var completedCommand = command
            completedCommand.status = "completed"
            completedCommand.output = commandChunks.joined()
            completedCommand.exitCode = 0
            sequence += 1
            emit(.turnItemCompleted(turnID: "turn_demo", sequence: sequence, item: completedCommand))

            let assistant = liveItem(id: "item-agent", type: "agentMessage", phase: "final_answer")
            sequence += 1
            emit(.turnItemStarted(turnID: "turn_demo", sequence: sequence, item: assistant))
            let assistantChunks = [
                "I found the reconnect state transition ",
                "that needed correction. ",
                "The focused tests pass and the change is ready for review."
            ]
            for chunk in assistantChunks {
                guard !Task.isCancelled else { return }
                await pause(milliseconds: turnPlaybackDelay(260))
                sequence += 1
                emit(.turnItemDelta(turnID: "turn_demo", sequence: sequence, itemID: assistant.id, field: "text", delta: chunk))
            }
            var completedAssistant = assistant
            completedAssistant.text = assistantChunks.joined()
            sequence += 1
            emit(.turnItemCompleted(turnID: "turn_demo", sequence: sequence, item: completedAssistant))
            emit(.turnEnded(traceID: "mock-trace", turnID: "turn_demo", phase: .completed, result: nil))
            emit(.agent(name: "Lee's Mac Studio", state: .idle))
        }
    }

    func interruptTurn() async {
        playbackTask?.cancel()
        playbackTask = nil
        emit(.output(LogEntry(stream: .system, text: "Interruption requested.")))
        emit(.turnEnded(traceID: "mock-trace", turnID: "turn_demo", phase: .interrupted, result: TurnResult(title: "Turn interrupted", detail: "Codex stopped cleanly.", changedFiles: 0, duration: 12)))
        emit(.agent(name: "Lee's Mac Studio", state: .idle))
    }

    func acknowledgeTurn(traceID _: String, turnID _: String, phase _: TurnPhase) async {}

    private func longHistoryTurns(endingAt endDate: Date) -> [ThreadHistoryTurn] {
        (1...120).map { index in
            let completedAt = endDate.addingTimeInterval(Double(index - 120) * 60)
            let items = [
                ThreadHistoryItem(id: "long-user-\(index)", type: "userMessage", role: "user", phase: nil, status: nil, text: "Long history prompt \(index)", name: nil, command: nil, cwd: nil, output: nil, path: nil, query: nil, exitCode: nil, durationMS: nil, changes: nil, truncated: false),
                ThreadHistoryItem(id: "long-tool-\(index)", type: "commandExecution", role: nil, phase: nil, status: "completed", text: nil, name: nil, command: "check-history \(index)", cwd: nil, output: "History check completed.", path: nil, query: nil, exitCode: 0, durationMS: 100, changes: nil, truncated: false),
                ThreadHistoryItem(id: "long-agent-\(index)", type: "agentMessage", role: "assistant", phase: "final_answer", status: nil, text: "Long history response \(index)", name: nil, command: nil, cwd: nil, output: nil, path: nil, query: nil, exitCode: nil, durationMS: nil, changes: nil, truncated: false)
            ]
            return ThreadHistoryTurn(
                id: "long-turn-\(index)",
                status: "completed",
                startedAt: completedAt.addingTimeInterval(-5),
                completedAt: completedAt,
                durationMS: 5_000,
                error: nil,
                items: items,
                truncated: false
            )
        }
    }

    private func liveItem(
        id: String,
        type: String,
        phase: String? = nil,
        status: String? = nil,
        command: String? = nil
    ) -> ThreadHistoryItem {
        ThreadHistoryItem(
            id: id,
            type: type,
            role: type == "agentMessage" || type == "reasoning" ? "assistant" : nil,
            phase: phase,
            status: status,
            text: nil,
            name: nil,
            command: command,
            cwd: nil,
            output: nil,
            path: nil,
            query: nil,
            exitCode: nil,
            durationMS: nil,
            changes: nil,
            truncated: false
        )
    }

    private func sampleThreads(projectID: String) -> [ThreadSummary] {
        if projectID == "project_codexremote" {
            return [
                ThreadSummary(id: "thread_recent", projectID: projectID, title: "Fix Relay reconnect policy", preview: "Review the reconnect behavior", latestMessagePreview: "The reconnect transition is corrected and tests pass.", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-420)),
                ThreadSummary(id: "thread_tests", projectID: projectID, title: "Stabilize integration tests", preview: "Run and repair failing tests", status: "idle", source: "cli", updatedAt: Date().addingTimeInterval(-7_200)),
                ThreadSummary(id: "thread_ui_review", projectID: projectID, title: "Review mobile UI structure", preview: "Check layout, gestures, and copy", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-18_000)),
                ThreadSummary(id: "thread_extra_4", projectID: projectID, title: "Improve drawer polish", preview: "Tune shadows, corners, and motion", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-21_000)),
                ThreadSummary(id: "thread_extra_5", projectID: projectID, title: "Audit localization", preview: "Check Chinese and English strings", status: "idle", source: "cli", updatedAt: Date().addingTimeInterval(-25_000)),
                ThreadSummary(id: "thread_extra_6", projectID: projectID, title: "Connect real project data", preview: "Verify relay snapshots in the app", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-28_000)),
                ThreadSummary(id: "thread_extra_7", projectID: projectID, title: "Add UI regression coverage", preview: "Protect the project manager shell", status: "idle", source: "cli", updatedAt: Date().addingTimeInterval(-31_000)),
                ThreadSummary(id: "thread_extra_8", projectID: projectID, title: "Review session focus behavior", preview: "Close the drawer after session selection", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-34_000))
            ]
        }
        if projectID == "project_lab" {
            return (1...8).map { index in
                ThreadSummary(
                    id: "thread_lab_\(index)",
                    projectID: projectID,
                    title: "Lab session \(index)",
                    preview: "Explore experiment workflow \(index)",
                    status: index == 2 ? "running" : "idle",
                    source: index.isMultiple(of: 2) ? "appServer" : "cli",
                    updatedAt: Date().addingTimeInterval(Double(-index * 1_800))
                )
            }
        }
        return [
            ThreadSummary(id: "thread_recent", projectID: projectID, title: "Fix Relay reconnect policy", preview: "Review the reconnect behavior", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-420)),
            ThreadSummary(id: "thread_tests", projectID: projectID, title: "Stabilize integration tests", preview: "Run and repair failing tests", status: "idle", source: "cli", updatedAt: Date().addingTimeInterval(-7_200)),
            ThreadSummary(id: "thread_ui_review", projectID: projectID, title: "Review mobile UI structure", preview: "Check layout, gestures, and copy", status: "idle", source: "appServer", updatedAt: Date().addingTimeInterval(-18_000))
        ]
    }

    private func projectName(_ id: String) -> String { sampleProjects.first { $0.id == id }?.name ?? "project" }
    private func emit(_ event: RelayEvent) { eventBuffer.yield(event) }
    private func turnPlaybackDelay(_ milliseconds: UInt64) -> UInt64 {
        ProcessInfo.processInfo.arguments.contains("--demo-slow-turn") ? milliseconds * 10 : milliseconds
    }
    private func pause(milliseconds: UInt64) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
}
