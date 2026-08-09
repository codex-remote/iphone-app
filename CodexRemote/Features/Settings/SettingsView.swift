import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Relay") {
                    TextField("WebSocket URL", text: $viewModel.relayURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .keyboardType(.URL)

                    Toggle("Reconnect automatically", isOn: $viewModel.reconnectAutomatically)
                }

                Section("Console") {
                    Stepper(value: $viewModel.consoleLimit, in: 100...2_000, step: 100) {
                        LabeledContent("Line limit", value: "\(viewModel.consoleLimit)")
                    }
                }

                Section("Build") {
                    LabeledContent("Data source", value: "Relay WebSocket")
                    LabeledContent("Protocol", value: "2.0")
                    LabeledContent("Version", value: "0.1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.applySettings()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
