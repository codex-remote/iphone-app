import AVFAudio
import SwiftUI

struct PromptComposer: View {
    let isRunning: Bool
    let canStartTurn: Bool
    let projectName: String
    let executionProfiles: [ExecutionProfile]
    let selectedExecutionProfileID: String?
    let selectExecutionProfile: (String) -> Void
    let editorFocus: FocusState<Bool>.Binding
    let onSubmit: (String) -> Void
    let onInterrupt: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voiceInput = VoiceTranscriptionController()
    @State private var prompt = ""
    @State private var hasRequestedVoiceInput = false

    var body: some View {
        VStack(spacing: 2) {
            TextField("Ask Codex to work on something", text: $prompt, axis: .vertical)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1...6)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .padding(.horizontal, 11)
                .padding(.top, 11)
                .padding(.bottom, 6)
                .focused(editorFocus)
                .disabled(isRunning || voiceInput.phase != .idle)
                .accessibilityIdentifier("composer.prompt")

            HStack(spacing: 4) {
                if editorFocus.wrappedValue {
                    Button {
                        editorFocus.wrappedValue = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityLabel(Text("Dismiss keyboard"))
                    .help(Text("Dismiss keyboard"))
                }

                HStack(spacing: 6) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 12, weight: .medium))
                    Text(verbatim: projectName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

                if !executionProfiles.isEmpty {
                    Menu {
                        ForEach(executionProfiles) { profile in
                            Button {
                                selectExecutionProfile(profile.id)
                            } label: {
                                Label(profileTitle(profile.id), systemImage: profileIcon(profile.id))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: profileIcon(selectedExecutionProfileID))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selectedExecutionProfileID == ":danger-full-access" ? AppTheme.red : AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                    }
                    .disabled(isRunning)
                    .accessibilityIdentifier("composer.executionProfile")
                    .accessibilityLabel(Text("Execution profile"))
                    .accessibilityValue(Text(profileTitle(selectedExecutionProfileID)))
                }

                Button(action: toggleVoiceInput) {
                    Group {
                        if voiceInput.isRequestingPermission {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppTheme.textSecondary)
                        } else {
                            Image(systemName: voiceInput.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(voiceInput.isRecording ? .white : AppTheme.textPrimary)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(voiceInput.isRecording ? AppTheme.red : Color.clear)
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRunning || voiceInput.isRequestingPermission)
                .opacity(isRunning ? 0.24 : 1)
                .accessibilityIdentifier("composer.voiceInput")
                .accessibilityLabel(Text(LocalizedStringKey(voiceInput.isRecording ? "Stop voice input" : "Start voice input")))
                .accessibilityValue(Text(LocalizedStringKey(voiceInput.isRecording ? "Recording" : "Not recording")))
                .help(Text(LocalizedStringKey(voiceInput.isRecording ? "Stop voice input" : "Start voice input")))

                Button(action: performPrimaryAction) {
                    Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(isRunning ? AppTheme.red : AppTheme.textPrimary)
                        .clipShape(Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isRunning && !canSubmit)
                .opacity((isRunning || canSubmit) ? 1 : 0.24)
                .accessibilityIdentifier("composer.primaryAction")
                .accessibilityLabel(Text(isRunning ? LocalizedStringKey("Interrupt current turn") : LocalizedStringKey("Start turn")))
                .help(Text(isRunning ? LocalizedStringKey("Interrupt current turn") : LocalizedStringKey("Start turn")))
            }
            .padding(.trailing, 4)
            .padding(.bottom, 3)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
        .onChange(of: voiceInput.composedText) { _, text in
            guard let text else { return }
            prompt = text
        }
        .onChange(of: isRunning) { _, running in
            if running {
                editorFocus.wrappedValue = false
                voiceInput.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voiceInput.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard
                let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: rawValue) == .began
            else { return }
            voiceInput.stop()
        }
        .onDisappear {
            editorFocus.wrappedValue = false
            voiceInput.cancel()
        }
        .alert(
            Text("Voice input unavailable"),
            isPresented: Binding(
                get: { hasRequestedVoiceInput && voiceInput.failure != nil },
                set: { presented in
                    if !presented {
                        hasRequestedVoiceInput = false
                        voiceInput.dismissFailure()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                hasRequestedVoiceInput = false
                voiceInput.dismissFailure()
            }
        } message: {
            if let failure = voiceInput.failure {
                Text(LocalizedStringKey(failure.rawValue))
            }
        }
    }

    private func toggleVoiceInput() {
        if voiceInput.isRecording {
            voiceInput.stop()
        } else {
            editorFocus.wrappedValue = false
            hasRequestedVoiceInput = true
            Task {
                await voiceInput.start(locale: locale, existingText: prompt)
            }
        }
    }

    private var canSubmit: Bool {
        canStartTurn && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func performPrimaryAction() {
        if isRunning {
            editorFocus.wrappedValue = false
            onInterrupt()
            return
        }

        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canStartTurn, !instruction.isEmpty else { return }
        editorFocus.wrappedValue = false
        prompt = ""
        onSubmit(instruction)
    }

    private func profileTitle(_ profileID: String?) -> LocalizedStringKey {
        switch profileID {
        case ":read-only": "Read only"
        case ":workspace": "Workspace access"
        case ":danger-full-access": "Full access"
        default: "Execution profile"
        }
    }

    private func profileIcon(_ profileID: String?) -> String {
        switch profileID {
        case ":read-only": "lock.fill"
        case ":danger-full-access": "lock.open.fill"
        default: "folder.badge.gearshape"
        }
    }
}
