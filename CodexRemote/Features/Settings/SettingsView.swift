import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    var body: some View {
        Form {
            Section("Language") {
                Picker("App language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.nativeName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                LabeledContent("Device access", value: authenticationLabel)
                    .accessibilityIdentifier("auth.status")
                if viewModel.authenticationState.isAuthenticated {
                    Button("Sign out", role: .destructive, action: viewModel.signOut)
                        .accessibilityIdentifier("auth.signOut")
                } else {
                    TextField("Pairing link or code", text: $viewModel.pairingInput, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button("Pair device", action: viewModel.pairDevice)
                        .disabled(viewModel.pairingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Refresh credentials are stored in this iPhone's Keychain and are never written to diagnostics.")
            }

            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionColor)
                            .frame(width: 7, height: 7)
                        Text(connectionLabel)
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                } label: {
                    Label("Mac Agent", systemImage: "desktopcomputer")
                }
                .accessibilityIdentifier(connectionStatusIdentifier)

                Picker("Test device", selection: Binding(
                    get: { viewModel.connectionProfile },
                    set: { viewModel.selectConnectionProfile($0) }
                )) {
                    Text("Simulator")
                        .tag(RelayConnectionProfile.simulator)
                        .accessibilityIdentifier("connection.profile.simulator")
                    Text("iPhone")
                        .tag(RelayConnectionProfile.iPhone)
                        .accessibilityIdentifier("connection.profile.iphone")
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.connectionTestState == .testing)
                .accessibilityIdentifier("connection.profile")

                TextField("Runtime URL", text: $viewModel.runtimeURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .keyboardType(.URL)
                    .accessibilityIdentifier("connection.url")
                    .disabled(viewModel.connectionTestState == .testing)
                    .onChange(of: viewModel.runtimeURL) { _, _ in
                        viewModel.connectionSettingsDidChange()
                    }

                Toggle(isOn: $viewModel.connectionEnabled) {
                    Label("Connection", systemImage: "network")
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("connection.toggle")

                connectionFeedback
            } header: {
                Text("Connection")
            } footer: {
                Text(connectionHelp)
            }

            Section("Activity") {
                Stepper(value: $viewModel.consoleLimit, in: 100...2_000, step: 100) {
                    LabeledContent("Event limit", value: "\(viewModel.consoleLimit)")
                }
            }

            Section {
                ShareLink(
                    item: DiagnosticsExport(),
                    preview: SharePreview("CodexRemote diagnostics")
                ) {
                    Label("Export diagnostics", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("diagnostics.export")
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Includes bounded structured events and Apple system diagnostics. Conversation content and credentials are never included.")
            }

            Section("About") {
                LabeledContent("Protocol", value: "Runtime v1")
                LabeledContent("Version", value: appVersion)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Settings")
        .preferredColorScheme(.light)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var authenticationLabel: String {
        switch viewModel.authenticationState {
        case .checking: "Checking"
        case .pairing: "Pairing"
        case .authenticated(let clientName): clientName
        case .unauthenticated: "Not paired"
        case .unavailable: "Unavailable"
        }
    }

    @ViewBuilder
    private var connectionFeedback: some View {
        switch viewModel.connectionTestState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Runtime status…")
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
            .accessibilityIdentifier("connection.test.testing")
        case .succeeded(let result):
            if !result.agentConnected {
                Label("Mac Agent is offline.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("connection.test.agentOffline")
            }
        case .failed(let message):
            Label {
                Text(message)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.red)
            .accessibilityIdentifier("connection.test.failed")
        }
    }

    private var connectionLabel: LocalizedStringKey {
        switch viewModel.connectionState {
        case .connecting: "Connecting"
        case .connected where viewModel.agentState == .offline: "Offline"
        case .connected: "Connected"
        case .disconnected: "Offline"
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connecting: AppTheme.amber
        case .connected where viewModel.agentState == .offline: AppTheme.red
        case .connected: AppTheme.green
        case .disconnected: AppTheme.red
        }
    }

    private var connectionStatusIdentifier: String {
        switch viewModel.connectionState {
        case .connecting:
            "connection.status.connecting"
        case .connected where viewModel.agentState != .offline:
            "connection.status.connected"
        case .connected, .disconnected:
            "connection.status.offline"
        }
    }

    private var connectionHelp: LocalizedStringKey {
        switch viewModel.connectionProfile {
        case .simulator:
            "Simulator uses the source Runtime Gateway on Mac loopback port 18874."
        case .iPhone:
            "Physical iPhone uses the Runtime Gateway. Replace 127.0.0.1 with this Mac's LAN IP or .local hostname."
        }
    }
}
