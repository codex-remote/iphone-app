import SwiftUI

struct StatusStrip: View {
    let connection: ConnectionState
    let agent: AgentState
    let turn: TurnPhase

    var body: some View {
        HStack(spacing: 0) {
            StatusCell(label: "LINK", value: connection.label, color: connectionColor)
            Divider().overlay(AppTheme.border)
            StatusCell(label: "AGENT", value: agent.label, color: agentColor)
            Divider().overlay(AppTheme.border)
            StatusCell(label: "TURN", value: turn.label, color: turnColor)
        }
        .frame(height: 62)
        .consolePanel()
        .accessibilityElement(children: .combine)
    }

    private var connectionColor: Color {
        switch connection {
        case .connected: AppTheme.green
        case .connecting: AppTheme.amber
        case .disconnected: AppTheme.red
        }
    }

    private var agentColor: Color {
        switch agent {
        case .idle: AppTheme.blue
        case .running: AppTheme.amber
        case .offline: AppTheme.red
        }
    }

    private var turnColor: Color {
        switch turn {
        case .completed: AppTheme.green
        case .running: AppTheme.amber
        case .failed: AppTheme.red
        case .interrupted: AppTheme.textSecondary
        case .idle: AppTheme.blue
        }
    }
}

private struct StatusCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.55), radius: 4)
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}
