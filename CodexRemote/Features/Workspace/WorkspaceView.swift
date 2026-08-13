import SwiftUI
import UIKit

enum WorkspaceScreen: Equatable {
    case project(String?)
    case task(projectID: String, threadID: String?)
    case activity
    case settings
}

struct WorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var screen: WorkspaceScreen
    @State private var isDrawerOpen = false
    @State private var expandedProjectIDs: Set<String> = []
    @State private var startupMinimumElapsed = false
    @State private var startupTimeoutElapsed = false
    @State private var isExecutionDetailsPresented = false
    @State private var isNewSessionPickerPresented = false
    @FocusState private var isComposerFocused: Bool

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        let arguments = ProcessInfo.processInfo.arguments
        let projectID = arguments.contains("--demo-project") ? "project_codexremote" : nil
        let startsOpen = arguments.contains("--demo-drawer")
        let initialScreen: WorkspaceScreen
        if arguments.contains("--demo-settings") {
            initialScreen = .settings
        } else {
            initialScreen = .project(projectID)
        }
        _screen = State(initialValue: initialScreen)
        _isDrawerOpen = State(initialValue: startsOpen)
    }

    var body: some View {
        GeometryReader { proxy in
            let drawerReveal = min(proxy.size.width * 0.76, 324)
            let fallbackCornerRadius: CGFloat = 44
            let panelCornerRadius = isDrawerOpen ? fallbackCornerRadius : 0
            let panelBorderOpacity = isDrawerOpen ? 0.1 : 0
            let safeAreaInsets = activeWindowSafeAreaInsets

            SlidingWorkspaceContainer(
                isProjectManagerVisible: $isDrawerOpen,
                projectManagerWidth: drawerReveal,
                projectManager: {
                    ProjectDrawer(
                        viewModel: viewModel,
                        screen: screen,
                        onSelectProject: { project in
                            viewModel.selectProject(project.id)
                        },
                        onSelectThread: { project, thread in
                            focusThread(project: project, thread: thread)
                        },
                        onNewTask: { project in
                            focusNewTask(project: project)
                        },
                        onActivity: {
                            isComposerFocused = false
                            screen = .activity
                            closeProjectManager()
                        },
                        onSettings: {
                            isComposerFocused = false
                            screen = .settings
                            closeProjectManager()
                        },
                        expandedProjectIDs: $expandedProjectIDs
                    )
                    .padding(.top, safeAreaInsets.top)
                    .padding(.bottom, safeAreaInsets.bottom)
                    .frame(width: drawerReveal, height: proxy.size.height, alignment: .topLeading)
                    .background(AppTheme.background)
                },
                workspace: {
                    NavigationStack {
                        VStack(spacing: 0) {
                            if let capabilities = viewModel.executionCapabilities, capabilities.restricted {
                                ExecutionRestrictionBanner(permissionProfileID: viewModel.selectedExecutionProfile?.id) {
                                    isExecutionDetailsPresented = true
                                }
                            }
                            screenContent
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppTheme.background)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        toggleProjectManager()
                                    } label: {
                                        Image(systemName: "sidebar.left")
                                    }
                                    .accessibilityLabel(isDrawerOpen ? "Close sidebar" : "Open sidebar")
                                    .accessibilityIdentifier("workspace.sidebar.toggle")
                                }

                                ToolbarItem(placement: .principal) { navigationTitle }
                                ToolbarItemGroup(placement: .topBarTrailing) {
                                    Button {
                                        isComposerFocused = false
                                        isNewSessionPickerPresented = true
                                    } label: {
                                        Image(systemName: "square.and.pencil")
                                    }
                                    .accessibilityLabel("New session")
                                    .accessibilityIdentifier("workspace.newSession")

                                    trailingToolbar
                                }
                            }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(AppTheme.background)
                    .accessibilityIdentifier("workspace.content")
                    .modifier(
                        DeviceConcentricSurface(
                            fallbackRadius: panelCornerRadius,
                            borderOpacity: panelBorderOpacity
                        )
                    )
                    .overlay(alignment: .leading) {
                        if isDrawerOpen {
                            Rectangle()
                                .fill(Color.black.opacity(0.13))
                                .frame(width: 1)
                                .padding(.vertical, fallbackCornerRadius + 18)
                                .offset(x: -2)
                                .blur(radius: 9)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        if isDrawerOpen {
                            Color.white.opacity(0.48)
                                .allowsHitTesting(false)
                        }
                    }
                }
            )
            .background(AppTheme.background)
            .clipped()
            .accessibilityAction(.escape) {
                if isDrawerOpen { closeProjectManager() }
            }
            .animation(.snappy(duration: 0.32, extraBounce: 0.04), value: isDrawerOpen)
        }
        .ignoresSafeArea(.container)
        .tint(AppTheme.textPrimary)
        .overlay {
            if shouldShowStartupOverlay {
                StartupLoadingOverlay(statusKey: startupStatusKey)
                    .transition(.opacity)
            }
        }
        .task {
            await runStartupOverlayTiming()
        }
        .sheet(isPresented: $isNewSessionPickerPresented) {
            NewSessionProjectPicker(projects: viewModel.projects) { project in
                isNewSessionPickerPresented = false
                focusNewTask(project: project)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isExecutionDetailsPresented) {
            if let capabilities = viewModel.executionCapabilities {
                ExecutionAccessDetailsView(capabilities: capabilities, permissionProfileID: viewModel.selectedExecutionProfile?.id)
            }
        }
    }

    private var shouldShowStartupOverlay: Bool {
        !startupMinimumElapsed || (isStartupLoading && !startupTimeoutElapsed)
    }

    private var isStartupLoading: Bool {
        guard viewModel.connectionEnabled else { return false }
        if viewModel.connectionState == .connecting { return true }
        if viewModel.connectionState == .connected
            && viewModel.agentState != .offline
            && viewModel.projects.isEmpty { return true }
        return false
    }

    private var startupStatusKey: LocalizedStringKey {
        if viewModel.connectionState == .connecting { return "Connecting to Mac Agent…" }
        if viewModel.connectionState == .connected
            && viewModel.agentState != .offline
            && viewModel.projects.isEmpty { return "Loading projects…" }
        return "Preparing Codex Remote…"
    }

    private func runStartupOverlayTiming() async {
        try? await Task.sleep(nanoseconds: 650_000_000)
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.24)) {
                startupMinimumElapsed = true
            }
        }

        try? await Task.sleep(nanoseconds: 1_350_000_000)
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.24)) {
                startupTimeoutElapsed = true
            }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch screen {
        case .project(let projectID):
            if let project = resolvedProject(projectID) {
                ProjectDetailView(
                    viewModel: viewModel,
                    project: project,
                    onNewTask: { focusNewTask(project: project) },
                    onSelectThread: { thread in
                        focusThread(project: project, thread: thread)
                    }
                )
                .id("project-\(project.id)")
            } else {
                EmptyWorkspaceView()
            }
        case .task(let projectID, let threadID):
            if let project = viewModel.projects.first(where: { $0.id == projectID }) {
                TaskWorkspaceView(
                    viewModel: viewModel,
                    turnSession: viewModel.turnSession,
                    project: project,
                    thread: viewModel.threads.first(where: { $0.id == threadID }),
                    composerFocus: $isComposerFocused
                )
                .id("task-\(projectID)-\(threadID ?? "new")")
            } else {
                EmptyWorkspaceView()
            }
        case .activity:
            ActivityHomeView(viewModel: viewModel) { project, thread in
                focusThread(project: project, thread: thread)
            }
        case .settings:
            SettingsView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var navigationTitle: some View {
        switch screen {
        case .project(let projectID):
            Text(verbatim: resolvedProject(projectID)?.name ?? "Codex Remote")
                .font(.system(size: 15, weight: .semibold))
        case .task(let projectID, let threadID):
            let project = viewModel.projects.first(where: { $0.id == projectID })
            let thread = viewModel.threads.first(where: { $0.id == threadID })
            Text(verbatim: thread?.title ?? project?.name ?? "Codex Remote")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        case .activity:
            Text("Activity").font(.system(size: 15, weight: .semibold))
        case .settings:
            Text("Settings").font(.system(size: 15, weight: .semibold))
        }
    }

    @ViewBuilder
    private var trailingToolbar: some View {
        switch screen {
        case .project(let projectID):
            if let project = resolvedProject(projectID) {
                Menu {
                    Button(action: viewModel.refreshProjects) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        UIPasteboard.general.string = project.path
                    } label: {
                        Label("Copy path", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        case .task:
            EmptyView()
        case .activity:
            Button(action: viewModel.refreshProjects) {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh projects")
        case .settings:
            EmptyView()
        }
    }

    private func resolvedProject(_ projectID: String?) -> ProjectSummary? {
        if let projectID, let project = viewModel.projects.first(where: { $0.id == projectID }) {
            return project
        }
        return viewModel.selectedProject ?? viewModel.projects.first
    }

    private func toggleProjectManager() {
        isComposerFocused = false
        if isDrawerOpen {
            closeProjectManager()
        } else {
            openProjectManager()
        }
    }

    private func openProjectManager() {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0.04)) {
            isDrawerOpen = true
        }
    }

    private func closeProjectManager() {
        withAnimation(.snappy(duration: 0.25)) {
            isDrawerOpen = false
        }
    }

    private func focusThread(project: ProjectSummary, thread: ThreadSummary) {
        isComposerFocused = false
        viewModel.prepareThread(projectID: project.id, threadID: thread.id)
        screen = .task(projectID: project.id, threadID: thread.id)
        closeProjectManager()
    }

    private func focusNewTask(project: ProjectSummary) {
        isComposerFocused = false
        viewModel.prepareNewTask(projectID: project.id)
        screen = .task(projectID: project.id, threadID: nil)
        closeProjectManager()
    }

    private var activeWindowSafeAreaInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }
}
