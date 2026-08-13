import Foundation
import MetricKit

final class MetricKitDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitDiagnostics()

    private var started = false

    private override init() {}

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Task { @MainActor in
                Diagnostics.shared.saveMetricKitPayload(data, kind: .metric)
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Task { @MainActor in
                Diagnostics.shared.saveMetricKitPayload(data, kind: .diagnostic)
            }
        }
    }
}
