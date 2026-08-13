import SwiftUI

struct ExecutionRestrictionBanner: View {
    let permissionProfileID: String?
    let showDetails: () -> Void

    var body: some View {
        Button(action: showDetails) {
            HStack(spacing: 10) {
                Image(systemName: permissionProfileID == ":danger-full-access" ? "lock.open.fill" : "lock.shield.fill")
                    .foregroundStyle(permissionProfileID == ":danger-full-access" ? AppTheme.red : AppTheme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permissionProfileID == ":danger-full-access" ? "Full access selected" : permissionProfileID == ":read-only" ? "Read-only execution" : "Restricted execution")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(permissionProfileID == ":danger-full-access" ? "This task can access Mac resources outside the selected project." : permissionProfileID == ":read-only" ? "This task can inspect project files but cannot modify them." : "Project files are writable; Mac and iPhone control is unavailable.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surfaceMuted)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(permissionProfileID == ":danger-full-access" ? "execution.fullAccess.banner" : "execution.restricted.banner")
    }
}

struct ExecutionAccessDetailsView: View {
    let capabilities: ExecutionCapabilities
    let permissionProfileID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if permissionProfileID == ":danger-full-access" {
                    Section {
                        Label("Full access is selected for this project.", systemImage: "lock.open")
                            .foregroundStyle(AppTheme.red)
                        Text("The profile is applied to both the Codex thread and each turn.")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Section("Policy") {
                        LabeledContent("Permission profile", value: permissionProfileID ?? "")
                    }
                } else {
                Section {
                    Label(permissionProfileID == ":read-only" ? "This task runs in a read-only Mac session." : "This task runs in a restricted Mac session.", systemImage: "lock.shield")
                }

                Section("Available") {
                    CapabilityRow(title: "Edit files in the selected project", available: true)
                }

                Section("Unavailable") {
                    CapabilityRow(title: "Network access", available: capabilities.networkAccess)
                    CapabilityRow(title: "Request additional approval", available: capabilities.canRequestApproval)
                    CapabilityRow(title: "Control Mac processes", available: capabilities.hostProcessControl)
                    CapabilityRow(title: "Write user Library files", available: capabilities.userLibraryWrite)
                    CapabilityRow(title: "Control Xcode devices", available: capabilities.xcodeDeviceControl)
                }

                Section("Policy") {
                    if let permissionProfileID {
                        LabeledContent("Permission profile", value: permissionProfileID)
                    }
                    LabeledContent("Sandbox", value: capabilities.sandboxMode)
                    LabeledContent("Approval", value: capabilities.approvalPolicy)
                }

                Section {
                    Text("Run tasks that need Mac or iPhone control from a full-access Codex session on your Mac.")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                }
            }
            .navigationTitle("Execution access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("execution.access.details")
    }
}

private struct CapabilityRow: View {
    let title: LocalizedStringKey
    let available: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? AppTheme.green : AppTheme.red)
                .accessibilityLabel(available ? "Available" : "Unavailable")
        }
    }
}
