import SwiftUI

struct TaskLanding: View {
    let project: ProjectSummary

    var body: some View {
        VStack(spacing: 18) {
            ProjectIcon(project: project, size: 52)
            VStack(spacing: 7) {
                Text("Start a task")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Codex will work in \(project.name) on your Mac.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyWorkspaceView: View {
    var body: some View {
        VStack(spacing: 14) {
            CodexMark()
                .scaleEffect(1.35)
            Text("Codex Remote")
                .font(.system(size: 20, weight: .semibold))
            Text("Select a project from the sidebar to begin.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct MetricCell: View {
    let value: LocalizedStringKey
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProjectIcon: View {
    let project: ProjectSummary
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: min(8, size * 0.2), style: .continuous)
                .fill(projectColor(project.id).opacity(0.12))
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(projectColor(project.id))
        }
        .frame(width: size, height: size)
    }
}

struct CodexMark: View {
    var body: some View {
        Image(systemName: "hexagon")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
    }
}

struct CodexHeading: View {
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
                    Text(verbatim: elapsedString(from: startedAt, to: context.date))
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

struct TurnTerminalNotice: View {
    let phase: TurnPhase
    let result: TurnResult

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(verbatim: result.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        switch phase {
        case .failed: AppTheme.red
        case .interrupted: AppTheme.amber
        default: AppTheme.textSecondary
        }
    }

    private var icon: String {
        switch phase {
        case .failed: "exclamationmark.circle.fill"
        case .interrupted: "stop.circle.fill"
        default: "info.circle.fill"
        }
    }
}

func projectColor(_ id: String) -> Color {
    let palette = [AppTheme.blue, AppTheme.green, AppTheme.amber, Color(red: 0.48, green: 0.32, blue: 0.72)]
    let stableIndex = id.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
    return palette[stableIndex]
}

func compactPath(_ path: String) -> String {
    let components = path.split(separator: "/")
    if components.count > 2, components.first == "Users" {
        return "~/" + components.dropFirst(2).joined(separator: "/")
    }
    return path
}

func updatedLabel(_ date: Date?, locale: Locale) -> String {
    guard let date else { return localizedString("Never", locale: locale) }
    if abs(date.timeIntervalSinceNow) < 45 { return localizedString("Now", locale: locale) }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
