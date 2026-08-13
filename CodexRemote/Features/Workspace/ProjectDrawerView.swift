import SwiftUI

struct ProjectDrawer: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let screen: WorkspaceScreen
    let onSelectProject: (ProjectSummary) -> Void
    let onSelectThread: (ProjectSummary, ThreadSummary) -> Void
    let onNewTask: (ProjectSummary) -> Void
    let onActivity: () -> Void
    let onSettings: () -> Void
    @State private var searchText = ""
    @Binding var expandedProjectIDs: Set<String>

    private var filteredProjects: [ProjectSummary] {
        guard !searchText.isEmpty else { return viewModel.projects }
        return viewModel.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let projectListHeight = max(CGFloat(180), proxy.size.height - 286)

            VStack(spacing: 0) {
            HStack(spacing: 11) {
                CodexMark()
                Text("Codex Remote")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityIdentifier("projectManager.drawer")
                Spacer()
                if let project = viewModel.selectedProject ?? viewModel.projects.first {
                    Button {
                        onNewTask(project)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New task")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("Search projects", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(AppTheme.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            DrawerMacRow(
                name: viewModel.agentName,
                connection: viewModel.connectionState,
                state: viewModel.agentState
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 18)

            ScrollViewReader { scrollProxy in
                List {
                    HStack {
                        Text("Projects")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        if isProjectListLoading && !viewModel.projects.isEmpty {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityLabel("Loading projects…")
                        }
                        Text("\(filteredProjects.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 7, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .background(ProjectListScrollBoundaryConfiguration())

                    if isProjectListLoading && viewModel.projects.isEmpty && searchText.isEmpty {
                        ProjectListLoadingView()
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else if viewModel.projectLoadState == .failed && viewModel.projects.isEmpty && searchText.isEmpty {
                        ProjectListFailureView(onRetry: viewModel.refreshProjects)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else if filteredProjects.isEmpty {
                        Text(emptyProjectListMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.vertical, 20)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredProjects) { project in
                            let isExpanded = expandedProjectIDs.contains(project.id)
                            let projectThreads = viewModel.threads(for: project.id)
                            let threadLoadState = viewModel.threadLoadState(for: project.id)

                            Button {
                                toggleProject(project, scrollProxy: scrollProxy)
                            } label: {
                                DrawerProjectRow(
                                    project: project,
                                    isSelected: project.id == activeProjectID,
                                    isRunning: viewModel.isRunning && project.id == viewModel.selectedProjectID,
                                    isExpanded: isExpanded
                                )
                            }
                            .buttonStyle(.plain)
                            .id(project.id)
                            .accessibilityIdentifier("project.\(project.id)")
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                            if isExpanded {
                                if projectThreads.isEmpty {
                                    Text(emptyThreadListMessage(project: project, state: threadLoadState))
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(.leading, 58)
                                        .padding(.trailing, 14)
                                        .padding(.vertical, 8)
                                        .listRowInsets(EdgeInsets())
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                } else {
                                    ForEach(projectThreads) { thread in
                                        Button {
                                            onSelectThread(project, thread)
                                        } label: {
                                            DrawerThreadRow(
                                                thread: thread,
                                                isSelected: selectedThreadID == thread.id
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("thread.\(project.id).\(thread.id)")
                                        .padding(.leading, 34)
                                        .listRowInsets(EdgeInsets())
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: projectListHeight, alignment: .top)
                .frame(height: projectListHeight)
                .layoutPriority(1)
                .accessibilityIdentifier("projectManager.list")
            }

            Divider()

            VStack(spacing: 2) {
                DrawerDestinationRow(
                    title: "Activity",
                    systemImage: "clock",
                    isSelected: screen == .activity,
                    action: onActivity
                )
                .accessibilityIdentifier("projectManager.activity")
                DrawerDestinationRow(
                    title: "Settings",
                    systemImage: "gearshape",
                    isSelected: screen == .settings,
                    action: onSettings
                )
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .onAppear {
            expandActiveProjectIfNeeded()
            requestExpandedProjectThreads()
        }
        .onChange(of: viewModel.selectedProjectID) { _, _ in expandActiveProjectIfNeeded() }
        .onChange(of: expandedProjectIDs) { _, _ in requestExpandedProjectThreads() }
    }

    private var activeProjectID: String? {
        switch screen {
        case .project(let projectID): projectID ?? viewModel.selectedProjectID
        case .task(let projectID, _): projectID
        default: viewModel.selectedProjectID
        }
    }

    private var selectedThreadID: String? {
        guard case .task(_, let threadID) = screen else { return nil }
        return threadID
    }

    private var isProjectListLoading: Bool {
        viewModel.projectLoadState == .loading
            && viewModel.connectionState == .connected
            && viewModel.agentState != .offline
    }

    private var emptyProjectListMessage: LocalizedStringKey {
        if !searchText.isEmpty { return "No matching projects" }
        if viewModel.agentState == .offline { return "Connect your Mac Agent to load projects." }
        return "No projects found"
    }

    private func emptyThreadListMessage(project: ProjectSummary, state: ThreadListLoadState) -> LocalizedStringKey {
        if project.threadCount == 0 { return "No sessions yet" }
        switch state {
        case .idle, .loading:
            return "Loading sessions…"
        case .loaded:
            return "No sessions yet"
        case .failed:
            return "Unable to load sessions"
        }
    }

    private func toggleProject(_ project: ProjectSummary, scrollProxy: ScrollViewProxy) {
        onSelectProject(project)
        let isExpanding = !expandedProjectIDs.contains(project.id)
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
            if isExpanding {
                expandedProjectIDs.insert(project.id)
                viewModel.ensureThreadsLoaded(projectID: project.id)
            } else {
                expandedProjectIDs.remove(project.id)
            }
        }

        guard isExpanding else { return }
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
                scrollProxy.scrollTo(project.id, anchor: .top)
            }
        }
    }

    private func expandActiveProjectIfNeeded() {
        if let activeProjectID {
            expandedProjectIDs.insert(activeProjectID)
        } else if let selectedProjectID = viewModel.selectedProjectID {
            expandedProjectIDs.insert(selectedProjectID)
        }
    }

    private func requestExpandedProjectThreads() {
        for projectID in expandedProjectIDs {
            viewModel.ensureThreadsLoaded(projectID: projectID)
        }
    }
}

struct ProjectDetailView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @Environment(\.locale) private var locale
    let project: ProjectSummary
    let onNewTask: () -> Void
    let onSelectThread: (ThreadSummary) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 15) {
                    ProjectIcon(project: project, size: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: project.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(verbatim: compactPath(project.path))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.bottom, 24)

                HStack(spacing: 0) {
                    MetricCell(value: LocalizedStringKey("\(project.threadCount)"), label: "Sessions")
                    Divider().frame(height: 38)
                    MetricCell(value: LocalizedStringKey(updatedLabel(project.updatedAt, locale: locale)), label: "Updated")
                    Divider().frame(height: 38)
                    MetricCell(
                        value: viewModel.isRunning && viewModel.selectedProjectID == project.id ? "Working" : "Ready",
                        label: "Status"
                    )
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
                .padding(.bottom, 24)

                Button(action: onNewTask) {
                    Label("New task", systemImage: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workspace.newTask")
                .padding(.bottom, 30)

                HStack {
                    Text("Recent sessions")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text(verbatim: "\(viewModel.threads.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.bottom, 8)

                if viewModel.threads.isEmpty {
                    Text("No sessions in this project yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.vertical, 24)
                } else {
                    ForEach(viewModel.threads) { thread in
                        Button { onSelectThread(thread) } label: {
                            SessionRow(thread: thread, projectName: project.name)
                        }
                        .buttonStyle(.plain)
                        if thread.id != viewModel.threads.last?.id { Divider().padding(.leading, 32) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(AppTheme.background)
        .onAppear { viewModel.selectProject(project.id) }
    }
}
