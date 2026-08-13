import SwiftUI

struct NewSessionProjectPicker: View {
    @Environment(\.dismiss) private var dismiss

    let projects: [ProjectSummary]
    let onSelect: (ProjectSummary) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No projects available",
                        systemImage: "folder",
                        description: Text("Connect your Mac Agent to load projects.")
                    )
                } else {
                    List {
                        Section("Choose a project") {
                            ForEach(projects) { project in
                                Button {
                                    onSelect(project)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(verbatim: project.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(AppTheme.textPrimary)

                                            Text(verbatim: project.path)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }

                                        Spacer(minLength: 8)

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("newSession.project.\(project.id)")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("newSession.projectPicker")
    }
}

struct StartupLoadingOverlay: View {
    let statusKey: LocalizedStringKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.surface)
                        .frame(width: 92, height: 92)
                        .shadow(color: .black.opacity(0.08), radius: 24, y: 10)

                    Image(systemName: "hexagon.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .opacity(0.95)

                    Image(systemName: "terminal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.background)
                }
                .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.035 : 0.98))

                VStack(spacing: 7) {
                    Text("Codex Remote")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(statusKey)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                ProgressView()
                    .controlSize(.regular)
                    .tint(AppTheme.textPrimary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 32)
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("startup.overlay")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
