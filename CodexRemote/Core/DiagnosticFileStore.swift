import Foundation

final class DiagnosticFileStore: @unchecked Sendable {
    enum ReportKind: String, Sendable {
        case metric
        case diagnostic
    }

    static let eventFileLimit = 4
    static let eventFileBytes = 512 * 1_024
    static let reportFileLimit = 8
    static let reportFileBytes = 4 * 1_024 * 1_024
    static let exportFileLimit = 3

    private let fileManager: FileManager
    private let directory: URL
    private let queue = DispatchQueue(label: "com.leehooo.codexremote.diagnostics.store", qos: .utility)
    private let eventFileBytes: Int
    private let eventFileLimit: Int

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        eventFileBytes: Int = DiagnosticFileStore.eventFileBytes,
        eventFileLimit: Int = DiagnosticFileStore.eventFileLimit
    ) {
        self.fileManager = fileManager
        self.eventFileBytes = eventFileBytes
        self.eventFileLimit = eventFileLimit
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = applicationSupport.appending(path: "Diagnostics", directoryHint: .isDirectory)
        }
    }

    func append(_ encodedRecord: Data) {
        queue.async { [self] in
            try? appendSynchronously(encodedRecord)
        }
    }

    func appendSynchronously(_ encodedRecord: Data) throws {
        try ensureDirectory()
        var line = encodedRecord
        line.append(0x0A)
        let current = eventURL(index: 0)
        let currentSize = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if currentSize + line.count > eventFileBytes {
            try rotateEvents()
        }

        if !fileManager.fileExists(atPath: current.path) {
            fileManager.createFile(atPath: current.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: current)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()
    }

    @discardableResult
    func saveReport(_ payload: Data, kind: ReportKind) -> Bool {
        guard payload.count <= Self.reportFileBytes else { return false }
        queue.async { [self] in
            try? ensureDirectory()
            let timestamp = Int(Date.now.timeIntervalSince1970 * 1_000)
            let url = directory.appending(path: "metrickit-\(kind.rawValue)-\(timestamp)-\(UUID().uuidString.lowercased()).json")
            try? payload.write(to: url, options: .atomic)
            trimReports()
        }
        return true
    }

    func makeExport(sessionID: String, schemaVersion: Int, appVersion: String, appBuild: String) throws -> URL {
        try queue.sync {
            try ensureDirectory()
            let records = try readEventRecords()
            let reports = try readReports()
            let root: [String: Any] = [
                "manifest": [
                    "format": "codexremote-diagnostics",
                    "schema_version": schemaVersion,
                    "exported_at": ISO8601DateFormatter().string(from: .now),
                    "session_id": sessionID,
                    "app_version": appVersion,
                    "app_build": appBuild,
                    "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                    "event_count": records.count,
                    "metrickit_report_count": reports.count,
                    "privacy": "No prompts, responses, credentials, relay URLs, or full file paths are recorded."
                ],
                "schema": [
                    "ordering": "Sort by timestamp, then session_id and sequence. uptime_ms is monotonic only within one boot.",
                    "correlation": "trace_id joins Relay request/response events. turn_ref joins Turn events within one app session without exposing the raw Turn ID.",
                    "levels": [
                        "debug": "development detail",
                        "info": "normal lifecycle or measurement",
                        "notice": "meaningful state transition",
                        "warning": "degraded behavior with recovery",
                        "error": "operation failed",
                        "fault": "termination risk or invariant failure"
                    ],
                    "content_policy": "fields contains allowlisted metadata only; user and conversation content is prohibited."
                ],
                "events": records,
                "metrickit_reports": reports
            ]
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            let exportDirectory = fileManager.temporaryDirectory.appending(path: "CodexRemoteDiagnostics", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            trimExports(in: exportDirectory)
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            let url = exportDirectory.appending(path: "codexremote-diagnostics-\(stamp).json")
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    func eventFileURLs() -> [URL] {
        queue.sync {
            (0..<eventFileLimit).map(eventURL).filter { fileManager.fileExists(atPath: $0.path) }
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func rotateEvents() throws {
        guard eventFileLimit > 1 else {
            try? fileManager.removeItem(at: eventURL(index: 0))
            return
        }
        try? fileManager.removeItem(at: eventURL(index: eventFileLimit - 1))
        for index in stride(from: eventFileLimit - 2, through: 0, by: -1) {
            let source = eventURL(index: index)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: eventURL(index: index + 1))
        }
    }

    private func eventURL(index: Int) -> URL {
        let name = index == 0 ? "events.jsonl" : "events.\(index).jsonl"
        return directory.appending(path: name)
    }

    private func readEventRecords() throws -> [Any] {
        var records: [Any] = []
        for index in stride(from: eventFileLimit - 1, through: 0, by: -1) {
            let url = eventURL(index: index)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else { continue }
                records.append(object)
            }
        }
        return records
    }

    private func readReports() throws -> [Any] {
        let urls = reportURLs()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return ["file": url.lastPathComponent, "payload": payload]
        }
    }

    private func reportURLs() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("metrickit-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    private func trimReports() {
        let reports = reportURLs()
        guard reports.count > Self.reportFileLimit else { return }
        for url in reports.prefix(reports.count - Self.reportFileLimit) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func trimExports(in exportDirectory: URL) {
        let exports = ((try? fileManager.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
        let retainedBeforeWriting = max(Self.exportFileLimit - 1, 0)
        guard exports.count > retainedBeforeWriting else { return }
        for url in exports.prefix(exports.count - retainedBeforeWriting) {
            try? fileManager.removeItem(at: url)
        }
    }
}
