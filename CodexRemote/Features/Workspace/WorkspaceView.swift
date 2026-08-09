import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ProjectContextBar(viewModel: viewModel)
                            .padding(.bottom, 18)

                        if viewModel.turnPhase == .idle {
                            EmptyTaskView(
                                isOffline: viewModel.connectionState == .disconnected,
                                projectName: viewModel.selectedProject?.name,
                                projectCount: viewModel.projects.count
                            )
                                .containerRelativeFrame(.vertical, count: 10, span: 7, spacing: 0)
                        } else {
                            conversation
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .background(AppTheme.background)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.logs.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.turnPhase) { _, phase in
                    guard phase.isTerminal else { return }
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo("run-result", anchor: .bottom)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PromptComposer(
                    prompt: $viewModel.prompt,
                    isRunning: viewModel.isRunning,
                    canRun: viewModel.canRun,
                    projectName: viewModel.selectedProject?.name,
                    action: viewModel.primaryAction
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(AppTheme.background.opacity(0.97))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "hexagon")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("Codex")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Remote")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    previewMenu
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("Settings")
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .tint(AppTheme.textPrimary)
    }

    private var previewMenu: some View {
        Menu {
            Section("Preview state") {
                ForEach(DemoScenario.allCases) { scenario in
                    Button {
                        viewModel.loadScenario(scenario)
                    } label: {
                        Label(scenario.label, systemImage: scenario.symbol)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .help("Preview state")
    }

    private var conversation: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            WorkspaceHeader(
                agentName: viewModel.agentName,
                projectName: viewModel.selectedProject?.name ?? "No project",
                connection: viewModel.connectionState,
                agent: viewModel.agentState
            )

            HStack {
                Spacer(minLength: 42)
                Text(viewModel.submittedPrompt ?? viewModel.prompt)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 14) {
                CodexHeading(phase: viewModel.turnPhase, startedAt: viewModel.startedAt)

                ConsoleView(
                    logs: viewModel.logs.filter { !$0.text.localizedCaseInsensitiveContains("relay session") && !$0.text.localizedCaseInsensitiveContains("handshake") },
                    isRunning: viewModel.isRunning,
                    onClear: viewModel.clearConsole
                )

                if let result = viewModel.result {
                    TurnResultView(phase: viewModel.turnPhase, result: result)
                        .id("run-result")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if viewModel.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Codex is working")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.turnPhase)
    }
}

private struct ProjectContextBar: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(viewModel.projects) { project in
                    Button { viewModel.selectProject(project.id) } label: {
                        Label(project.name, systemImage: project.id == viewModel.selectedProjectID ? "checkmark" : "folder")
                    }
                }
            } label: {
                ContextLabel(icon: "folder", title: viewModel.selectedProject?.name ?? "Select project")
            }
            .disabled(viewModel.projects.isEmpty || viewModel.isRunning)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.65))

            Menu {
                Button { viewModel.selectThread(nil) } label: {
                    Label("New session", systemImage: viewModel.selectedThreadID == nil ? "checkmark" : "plus.bubble")
                }
                if !viewModel.threads.isEmpty { Divider() }
                ForEach(viewModel.threads) { thread in
                    Button { viewModel.selectThread(thread.id) } label: {
                        Label(thread.title, systemImage: thread.id == viewModel.selectedThreadID ? "checkmark" : "bubble.left")
                    }
                }
            } label: {
                ContextLabel(icon: "bubble.left", title: viewModel.selectedThread?.title ?? "New session")
            }
            .disabled(viewModel.selectedProjectID == nil || viewModel.isRunning)

            Spacer(minLength: 0)

            Button(action: viewModel.refreshProjects) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .disabled(viewModel.isRunning)
            .help("Refresh projects")
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
    }
}

private struct ContextLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 122, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(AppTheme.textPrimary)
    }
}

private struct EmptyTaskView: View {
    let isOffline: Bool
    let projectName: String?
    let projectCount: Int

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.surfaceMuted)
                    .frame(width: 54, height: 54)
                Image(systemName: isOffline ? "wifi.slash" : "hexagon")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            VStack(spacing: 7) {
                Text(isOffline ? "Mac is offline" : (projectName == nil ? "Choose a project" : "Start a task"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detail: String {
        if isOffline { return "Codex Remote will reconnect automatically." }
        if let projectName { return "Codex will work in \(projectName) on your Mac." }
        return projectCount == 0 ? "No Git projects were found in the configured workspace roots." : "Select one of \(projectCount) available projects."
    }
}

private struct WorkspaceHeader: View {
    let agentName: String
    let projectName: String
    let connection: ConnectionState
    let agent: AgentState

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(AppTheme.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(projectName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(agentName)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var statusColor: Color {
        connection == .disconnected || agent == .offline ? AppTheme.red : (agent == .running ? AppTheme.amber : AppTheme.green)
    }

    private var statusText: String {
        connection == .disconnected || agent == .offline ? "Offline" : (agent == .running ? "Working" : "Online")
    }
}

private struct CodexHeading: View {
    let phase: TurnPhase
    let startedAt: Date?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "hexagon.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Codex")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            if phase == .running, let startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedString(from: startedAt, to: context.date))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private func elapsedString(from start: Date, to end: Date) -> String {
        let elapsed = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

private struct TurnResultView: View {
    let phase: TurnPhase
    let result: TurnResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(result.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(result.detail)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Label("\(result.changedFiles) files", systemImage: "doc.on.doc")
                Label("\(Int(result.duration))s", systemImage: "clock")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var color: Color {
        switch phase {
        case .completed: AppTheme.green
        case .failed: AppTheme.red
        case .interrupted: AppTheme.amber
        default: AppTheme.blue
        }
    }

    private var icon: String {
        switch phase {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .interrupted: "stop.circle.fill"
        default: "circle"
        }
    }
}
