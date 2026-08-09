import SwiftUI

struct PromptComposer: View {
    @Binding var prompt: String
    let isRunning: Bool
    let canRun: Bool
    let projectName: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Ask Codex to work on something")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $prompt)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .frame(minHeight: 52, maxHeight: 104)
                    .disabled(isRunning)
            }

            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11, weight: .medium))
                Text(projectName ?? "No project")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Button(action: action) {
                    Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(isRunning ? AppTheme.red : AppTheme.textPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isRunning && !canRun)
                .opacity((isRunning || canRun) ? 1 : 0.24)
                .help(isRunning ? "Interrupt current turn" : "Start turn")
            }
            .padding(.leading, 8)
            .padding(.trailing, 3)
        }
        .padding(8)
        .consolePanel()
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}
