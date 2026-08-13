import SwiftUI

/// Owns the visual transition between workspace content, the composer, and the
/// system keyboard. PromptComposer intentionally owns no safe-area behavior.
struct ComposerDock: View {
    let isRunning: Bool
    let canStartTurn: Bool
    let projectName: String
    let executionProfiles: [ExecutionProfile]
    let selectedExecutionProfileID: String?
    let selectExecutionProfile: (String) -> Void
    let editorFocus: FocusState<Bool>.Binding
    let onSubmit: (String) -> Void
    let onInterrupt: () -> Void

    var body: some View {
        PromptComposer(
            isRunning: isRunning,
            canStartTurn: canStartTurn,
            projectName: projectName,
            executionProfiles: executionProfiles,
            selectedExecutionProfileID: selectedExecutionProfileID,
            selectExecutionProfile: selectExecutionProfile,
            editorFocus: editorFocus,
            onSubmit: onSubmit,
            onInterrupt: onInterrupt
        )
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                stops: [
                    .init(color: AppTheme.background.opacity(0), location: 0),
                    .init(color: AppTheme.background.opacity(0.96), location: 0.48),
                    .init(color: AppTheme.background, location: 0.72),
                    .init(color: AppTheme.keyboardBackdrop, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
