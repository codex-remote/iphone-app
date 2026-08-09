import SwiftUI

struct ConsoleView: View {
    let logs: [LogEntry]
    let isRunning: Bool
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Activity")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AppTheme.textSecondary)
                }

                Spacer()

                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
                .disabled(logs.isEmpty)
                .opacity(logs.isEmpty ? 0.35 : 1)
                .help("Clear activity")
            }

            VStack(alignment: .leading, spacing: 0) {
                if logs.isEmpty {
                    Text("Waiting for Codex to start")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(logs.suffix(8))) { entry in
                        ActivityRow(entry: entry)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ActivityRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(streamColor)
                .frame(width: 20, height: 20)
                .background(streamColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(entry.stream == .stderr ? AppTheme.red : AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamColor: Color {
        switch entry.stream {
        case .system: AppTheme.amber
        case .assistant: AppTheme.green
        case .stdout: AppTheme.blue
        case .stderr: AppTheme.red
        }
    }

    private var icon: String {
        switch entry.stream {
        case .system: "sparkles"
        case .assistant: "hexagon.fill"
        case .stdout:
            entry.text.localizedCaseInsensitiveContains("test") ? "checkmark.circle" : "doc.text.magnifyingglass"
        case .stderr: "exclamationmark.triangle"
        }
    }
}
