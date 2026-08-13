import SwiftUI
import UIKit

struct ProjectListScrollBoundaryConfiguration: UIViewRepresentable {
    func makeUIView(context _: Context) -> BoundaryConfigurationView {
        BoundaryConfigurationView()
    }

    func updateUIView(_ view: BoundaryConfigurationView, context _: Context) {
        view.applyToEnclosingScrollView()
    }

    final class BoundaryConfigurationView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyToEnclosingScrollView()
            DispatchQueue.main.async { [weak self] in
                self?.applyToEnclosingScrollView()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyToEnclosingScrollView()
        }

        func applyToEnclosingScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceVertical = false
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

struct ProjectListLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading projects…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.surfaceMuted)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 7) {
                        Capsule()
                            .fill(AppTheme.surfaceMuted)
                            .frame(width: 116, height: 10)
                        Capsule()
                            .fill(AppTheme.surfaceMuted.opacity(0.78))
                            .frame(maxWidth: 190)
                            .frame(height: 8)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectManager.projects.loading")
    }
}

struct ProjectListFailureView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unable to load projects", systemImage: "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            Button("Retry", action: onRetry)
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("projectManager.projects.retry")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("projectManager.projects.failed")
    }
}

struct DrawerMacRow: View {
    let name: String
    let connection: ConnectionState
    let state: AgentState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(statusKey)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Circle().fill(statusColor).frame(width: 7, height: 7)
        }
    }

    private var statusKey: LocalizedStringKey {
        if connection == .disconnected || state == .offline { return "Offline" }
        if state == .running { return "Working" }
        return "Online"
    }

    private var statusColor: Color {
        connection == .disconnected || state == .offline ? AppTheme.red : (state == .running ? AppTheme.amber : AppTheme.green)
    }
}

struct DrawerProjectRow: View {
    let project: ProjectSummary
    let isSelected: Bool
    let isRunning: Bool
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 11) {
            ProjectIcon(project: project, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: project.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if isRunning { Circle().fill(AppTheme.amber).frame(width: 6, height: 6) }
                }
                Text(verbatim: compactPath(project.path))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(verbatim: "\(project.threadCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(isSelected ? AppTheme.surfaceMuted : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

struct DrawerThreadRow: View {
    let thread: ThreadSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: thread.status == "running" ? "circle.dotted" : "bubble.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(thread.status == "running" ? AppTheme.amber : AppTheme.textSecondary)
                .frame(width: 30)
            Text(verbatim: thread.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(isSelected ? AppTheme.surfaceMuted : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

struct DrawerDestinationRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(title).font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(isSelected ? AppTheme.surfaceMuted : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
