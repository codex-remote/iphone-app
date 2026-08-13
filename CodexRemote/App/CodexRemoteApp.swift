import SwiftUI
import UIKit

@main
struct CodexRemoteApp: App {
    @UIApplicationDelegateAdaptor(CodexRemoteAppDelegate.self) private var appDelegate
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            CodexRemoteRootView()
                .preferredColorScheme(.light)
                .environment(\.locale, selectedLanguage.locale)
                .background(AppTheme.keyboardBackdrop.ignoresSafeArea())
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .system
    }
}

private final class CodexRemoteAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UIWindow.appearance().backgroundColor = UIColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1)
        Diagnostics.shared.record(.appLaunched, level: .notice, category: .lifecycle)
        MetricKitDiagnostics.shared.start()
        MemoryDiagnostics.shared.start()
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        MemoryDiagnostics.shared.recordMemoryWarning()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Diagnostics.shared.record(.appEnteredBackground, category: .lifecycle)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Diagnostics.shared.record(.appEnteredForeground, category: .lifecycle)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Diagnostics.shared.record(.appWillTerminate, level: .notice, category: .lifecycle)
    }
}

private struct CodexRemoteRootView: View {
    @State private var viewModel: WorkspaceViewModel?

    var body: some View {
        Group {
            if let viewModel {
                WorkspaceView(viewModel: viewModel)
            } else {
                StartupLoadingOverlay(statusKey: "Preparing Codex Remote…")
            }
        }
        .background(AppTheme.background)
        .task {
            guard viewModel == nil else { return }
            await Task.yield()
            await MainActor.run {
                viewModel = AppBootstrap.makeWorkspaceViewModel()
            }
        }
    }
}

private enum AppBootstrap {
    @MainActor
    static func makeWorkspaceViewModel() -> WorkspaceViewModel {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        if arguments.contains("--reset-connection-settings") {
            [
                "relayURL.simulator",
                "relayURL.iPhone",
                "relayConnectionProfile",
                "relayConnectionEnabled"
            ].forEach { defaults.removeObject(forKey: $0) }
        }
        if arguments.contains("--reset-execution-profiles") {
            defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("executionPermissionProfile.") }
                .forEach { defaults.removeObject(forKey: $0) }
        }
        applyRelayURLLaunchArgument(arguments, defaults: defaults)
        let service: RelayServiceProtocol = arguments.contains { $0.hasPrefix("--demo-") }
            ? MockRelayService()
            : RelayClient()
        return WorkspaceViewModel(service: service)
    }

    private static func applyRelayURLLaunchArgument(_ arguments: [String], defaults: UserDefaults) {
        guard let optionIndex = arguments.firstIndex(of: "--relay-url"),
              arguments.indices.contains(optionIndex + 1) else { return }

        let rawValue = arguments[optionIndex + 1]
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.path == "/ws/app",
              url.query == nil,
              url.fragment == nil else { return }

        let profile = RelayConnectionProfile.iPhone
        defaults.set(url.absoluteString, forKey: profile.urlDefaultsKey)
        defaults.set(profile.rawValue, forKey: "relayConnectionProfile")
        defaults.set(true, forKey: "relayConnectionEnabled")
    }
}
