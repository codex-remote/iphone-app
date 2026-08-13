import Foundation
import UIKit
import os

@MainActor
final class MemoryDiagnostics {
    struct Snapshot {
        let projects: Int
        let threads: Int
        let cachedTranscripts: Int
        let transcriptMessages: Int
        let liveItems: Int
        let liveCharacters: Int
        let consoleEntries: Int
    }

    static let shared = MemoryDiagnostics()

    private var samplingTask: Task<Void, Never>?
    private var snapshotProvider: (() -> Snapshot)?
    private var relayMessageCount = 0
    private var relayBytesReceived = 0
    private var droppedRelayEventCount = 0

    private init() {}

    func start() {
        guard samplingTask == nil else { return }
        logSnapshot(reason: "launch")
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                logSnapshot(reason: "periodic")
            }
        }
    }

    func setSnapshotProvider(_ provider: @escaping () -> Snapshot) {
        snapshotProvider = provider
    }

    func recordRelayMessage(byteCount: Int) {
        relayMessageCount += 1
        relayBytesReceived += max(byteCount, 0)
    }

    func recordDroppedRelayEvent() {
        droppedRelayEventCount += 1
        guard droppedRelayEventCount == 1 || droppedRelayEventCount.isMultiple(of: 100) else { return }
        Diagnostics.shared.record(
            .relayBufferDropped,
            level: .warning,
            category: .relay,
            fields: [.droppedEvents: .integer(droppedRelayEventCount)]
        )
    }

    func recordMemoryWarning() {
        Diagnostics.shared.record(.memoryWarning, level: .fault, category: .memory)
        logSnapshot(reason: "memory-warning")
    }

    func recordVoiceRecognition(started: Bool, duration: TimeInterval? = nil) {
        Diagnostics.shared.record(
            started ? .speechStarted : .speechEnded,
            category: .speech,
            fields: started ? [:] : [.durationMS: .integer(Int((duration ?? 0) * 1_000))]
        )
    }

    func checkpoint(_ reason: String) {
        logSnapshot(reason: reason)
    }

    private func logSnapshot(reason: String) {
        let availableMB = os_proc_available_memory() / 1_048_576
        var fields: [DiagnosticField: DiagnosticValue] = [
            .reason: .string(reason),
            .availableMB: .integer(availableMB),
            .relayMessages: .integer(relayMessageCount),
            .relayMB: .integer(relayBytesReceived / 1_048_576),
            .droppedEvents: .integer(droppedRelayEventCount)
        ]
        guard let snapshot = snapshotProvider?() else {
            Diagnostics.shared.record(.memorySnapshot, category: .memory, fields: fields)
            return
        }

        fields[.projects] = .integer(snapshot.projects)
        fields[.threads] = .integer(snapshot.threads)
        fields[.cachedTranscripts] = .integer(snapshot.cachedTranscripts)
        fields[.transcriptMessages] = .integer(snapshot.transcriptMessages)
        fields[.liveItems] = .integer(snapshot.liveItems)
        fields[.liveCharacters] = .integer(snapshot.liveCharacters)
        fields[.consoleEntries] = .integer(snapshot.consoleEntries)
        Diagnostics.shared.record(
            reason == "memory-warning-cleanup" ? .memoryCleanup : .memorySnapshot,
            category: .memory,
            fields: fields
        )
    }
}
