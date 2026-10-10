import SwiftUI

struct RuntimePairingView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)
            Image(systemName: "iphone.and.arrow.forward.inward")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Pair this iPhone")
                    .font(.title2.weight(.semibold))
                Text(pairingMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Pairing link or code", text: $viewModel.pairingInput, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                    .padding(13)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("auth.pairingInput")

                Button(action: viewModel.pairDevice) {
                    Group {
                        if case .pairing = viewModel.authenticationState {
                            ProgressView().tint(.white)
                        } else {
                            Label("Pair device", systemImage: "link")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.textPrimary)
                .disabled(viewModel.pairingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPairing)
                .accessibilityIdentifier("auth.pair")
            }
            .frame(maxWidth: 460)

            Spacer()
        }
        .padding(.horizontal, 28)
        .background(AppTheme.background)
    }

    private var isPairing: Bool {
        if case .pairing = viewModel.authenticationState { return true }
        return false
    }

    private var pairingMessage: LocalizedStringKey {
        switch viewModel.authenticationState {
        case .checking: "Checking this device's access…"
        case .pairing: "Exchanging the one-time pairing code…"
        case .unauthenticated(let message): LocalizedStringKey(message ?? "Paste the one-time link printed by codex-remote pair.")
        case .unavailable(let message): LocalizedStringKey(message)
        case .authenticated: "This iPhone is paired."
        }
    }
}

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

                                            if !project.path.isEmpty {
                                                Text(verbatim: project.path)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.textSecondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
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
