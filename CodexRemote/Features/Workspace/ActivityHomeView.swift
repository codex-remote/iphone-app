import SwiftUI

struct ActivityHomeView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @Environment(\.locale) private var locale
    let onSelectThread: (ProjectSummary, ThreadSummary) -> Void
    @State private var filter = 0

    private var visibleThreads: [ThreadSummary] {
        switch filter {
        case 1: viewModel.threads.filter { $0.status == "running" }
        case 2: viewModel.threads.filter { $0.status != "running" }
        default: viewModel.threads
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Picker("Activity filter", selection: $filter) {
                    Text("All").tag(0)
                    Text("Active").tag(1)
                    Text("Finished").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 24)

                if viewModel.isRunning {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Codex is working")
                                .font(.system(size: 15, weight: .semibold))
                            Text(verbatim: viewModel.selectedProject?.name ?? localizedProjectFallback)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.amber)
                    }
                    .padding(.bottom, 24)
                }

                Text("Recent")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.bottom, 8)

                if visibleThreads.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 24, weight: .light))
                        Text(emptyActivityLabel)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ForEach(visibleThreads) { thread in
                        if let project = viewModel.projects.first(where: { $0.id == thread.projectID }) {
                            Button { onSelectThread(project, thread) } label: {
                                SessionRow(thread: thread, projectName: project.name)
                            }
                            .buttonStyle(.plain)
                        } else {
                            SessionRow(thread: thread, projectName: localizedProjectFallback)
                        }
                        if thread.id != visibleThreads.last?.id { Divider().padding(.leading, 32) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(AppTheme.background)
    }

    private var localizedProjectFallback: String {
        localizedString("Project", locale: locale)
    }

    private var emptyActivityLabel: LocalizedStringKey {
        switch filter {
        case 1: "No active sessions"
        case 2: "No finished sessions"
        default: "No recent activity"
        }
    }
}

struct SessionRow: View {
    @Environment(\.locale) private var locale
    let thread: ThreadSummary
    let projectName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: thread.status == "running" ? "circle.dotted" : "checkmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(thread.status == "running" ? AppTheme.amber : AppTheme.textSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: thread.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                Text(verbatim: thread.recentContentPreview)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(verbatim: projectName)
                    Text("·")
                    Text(verbatim: updatedLabel(thread.updatedAt, locale: locale))
                }
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.85))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                .padding(.top, 4)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
