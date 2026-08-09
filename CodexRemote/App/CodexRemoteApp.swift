import SwiftUI

@main
struct CodexRemoteApp: App {
    @StateObject private var viewModel: WorkspaceViewModel

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let initialScenario: DemoScenario? = {
            if arguments.contains("--demo-running") { return .running }
            if arguments.contains("--demo-completed") { return .completed }
            if arguments.contains("--demo-failed") { return .failed }
            if arguments.contains("--demo-offline") { return .offline }
            return nil
        }()
        let service: RelayServiceProtocol = initialScenario == nil ? RelayClient() : MockRelayService()
        _viewModel = StateObject(wrappedValue: WorkspaceViewModel(service: service, initialScenario: initialScenario))
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(viewModel: viewModel)
                .preferredColorScheme(.light)
        }
    }
}
