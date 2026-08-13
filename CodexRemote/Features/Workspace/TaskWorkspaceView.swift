import SwiftUI

struct TaskWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject var turnSession: TurnSessionStore
    let project: ProjectSummary
    let thread: ThreadSummary?
    let composerFocus: FocusState<Bool>.Binding
    @State private var didPrepare = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let thread {
                        ThreadHistoryView(
                            transcript: viewModel.threadTranscript(projectID: project.id, threadID: thread.id),
                            loadState: viewModel.threadDetailLoadState(projectID: project.id, threadID: thread.id),
                            onRetry: {
                                viewModel.refreshThreadDetail(projectID: project.id, threadID: thread.id)
                            }
                        )

                        if turnSession.phase != .idle || !turnSession.logs.isEmpty {
                            conversation
                        }
                    } else if turnSession.phase == .idle && turnSession.logs.isEmpty {
                        TaskLanding(project: project)
                            .containerRelativeFrame(.vertical, count: 10, span: 7, spacing: 0)
                    } else {
                        conversation
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .background(AppTheme.background)
            .contentShape(Rectangle())
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    composerFocus.wrappedValue = false
                }
            )
            .accessibilityIdentifier("task.transcriptScroll")
            .onChange(of: turnSession.phase) { _, phase in
                guard phase == .running else { return }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo("live-turn", anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerDock(
                isRunning: turnSession.isRunning,
                canStartTurn: viewModel.canStartTurn,
                projectName: project.name,
                executionProfiles: viewModel.availableExecutionProfiles,
                selectedExecutionProfileID: viewModel.selectedExecutionProfile?.id,
                selectExecutionProfile: viewModel.selectExecutionProfile,
                editorFocus: composerFocus,
                onSubmit: viewModel.startTurn,
                onInterrupt: viewModel.interruptTurn
            )
        }
        .onAppear {
            guard !didPrepare else { return }
            didPrepare = true
            if turnSession.isRunning, viewModel.selectedThreadID == thread?.id { return }
            if let thread {
                viewModel.prepareThread(projectID: project.id, threadID: thread.id)
            } else {
                viewModel.prepareNewTask(projectID: project.id)
            }
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let submittedPrompt = turnSession.submittedPrompt, !submittedPrompt.isEmpty {
                HStack {
                    Spacer(minLength: 42)
                    Text(verbatim: submittedPrompt)
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AppTheme.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                CodexHeading(phase: turnSession.phase, startedAt: turnSession.startedAt)
                LiveTurnContent(
                    items: turnSession.items,
                    fallbackLogs: turnSession.logs,
                    isRunning: turnSession.isRunning,
                    isTruncated: turnSession.itemsTruncated,
                    onClearLogs: viewModel.clearConsole
                )

                if turnSession.phase != .completed, let result = turnSession.result {
                    TurnTerminalNotice(phase: turnSession.phase, result: result)
                        .accessibilityIdentifier("turn.terminalNotice")
                }
            }
        }
        .id("live-turn")
    }
}

struct LiveTurnContent: View {
    let items: [ThreadHistoryItem]
    let fallbackLogs: [LogEntry]
    let isRunning: Bool
    let isTruncated: Bool
    let onClearLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !processItems.isEmpty {
                ProcessDetailsDisclosure(
                    items: processItems,
                    identifierPrefix: "turn.live.process"
                )
            }

            if !assistantText.isEmpty {
                LiveAssistantContent(text: assistantText, isRunning: isRunning)
                    .accessibilityIdentifier("turn.live.assistant")
            } else if items.isEmpty && !fallbackLogs.isEmpty {
                ConsoleView(logs: fallbackLogs, isRunning: isRunning, onClear: onClearLogs)
            } else if isRunning && processItems.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Codex is working")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            if isTruncated {
                Label("Live activity was truncated", systemImage: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleAssistantItems: [ThreadHistoryItem] {
        let agents = items.filter { $0.type == "agentMessage" && clean($0.text) != nil }
        let final = agents.filter { $0.phase == "final_answer" }
        if !final.isEmpty { return final }
        return agents.filter { $0.phase != "commentary" }
    }

    private var assistantText: String {
        visibleAssistantItems.compactMap { clean($0.text) }.joined(separator: "\n\n")
    }

    private var processItems: [ThreadHistoryItem] {
        let visibleIDs = Set(visibleAssistantItems.map(\.id))
        return items.filter { $0.type != "userMessage" && !visibleIDs.contains($0.id) }
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

private struct LiveAssistantContent: View {
    let text: String
    let isRunning: Bool

    var body: some View {
        if isRunning {
            Text(verbatim: text)
                .font(.system(size: 17))
                .lineSpacing(6)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            MarkdownContentView(text: text, baseSize: 17, lineSpacing: 6)
        }
    }
}
