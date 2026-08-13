import CryptoKit
import CoreTransferable
import Foundation
import OSLog
import UniformTypeIdentifiers

enum DiagnosticLevel: String, Codable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

enum DiagnosticCategory: String, Codable, Sendable {
    case lifecycle
    case relay
    case turn
    case memory
    case speech
    case diagnostics
}

enum DiagnosticEvent: String, Codable, Sendable {
    case appLaunched = "app.launched"
    case appEnteredBackground = "app.entered_background"
    case appEnteredForeground = "app.entered_foreground"
    case appWillTerminate = "app.will_terminate"
    case memorySnapshot = "memory.snapshot"
    case memoryWarning = "memory.warning"
    case memoryCleanup = "memory.cleanup"
    case relayBufferDropped = "relay.buffer_dropped"
    case relayConnectStarted = "relay.connect_started"
    case relayConnected = "relay.connected"
    case relayDisconnected = "relay.disconnected"
    case relayReconnectScheduled = "relay.reconnect_scheduled"
    case relayRequestSent = "relay.request_sent"
    case relayResponseReceived = "relay.response_received"
    case relayDecodeFailed = "relay.decode_failed"
    case relaySendFailed = "relay.send_failed"
    case relayConnectionTestStarted = "relay.connection_test_started"
    case relayConnectionTestCompleted = "relay.connection_test_completed"
    case turnStarted = "turn.started"
    case turnEnded = "turn.ended"
    case speechStarted = "speech.started"
    case speechEnded = "speech.ended"
    case speechFailed = "speech.failed"
    case metricPayloadReceived = "diagnostics.metric_payload_received"
    case diagnosticPayloadReceived = "diagnostics.diagnostic_payload_received"
}

enum DiagnosticField: String, Codable, Hashable, Sendable {
    case reason
    case availableMB = "available_mb"
    case projects
    case threads
    case cachedTranscripts = "cached_transcripts"
    case transcriptMessages = "transcript_messages"
    case liveItems = "live_items"
    case liveCharacters = "live_characters"
    case consoleEntries = "console_entries"
    case relayMessages = "relay_messages"
    case relayMB = "relay_mb"
    case droppedEvents = "dropped_events"
    case durationMS = "duration_ms"
    case bytes
    case messageType = "message_type"
    case phase
    case promptCharacters = "prompt_characters"
    case errorDomain = "error_domain"
    case errorCode = "error_code"
    case transport
    case statusCode = "status_code"
    case agentConnected = "agent_connected"
    case reportType = "report_type"
    case reportBytes = "report_bytes"
    case reportCount = "report_count"
    case reportAccepted = "report_accepted"
    case delayMS = "delay_ms"
}

enum DiagnosticValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }

    var logDescription: String {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .double(let value): String(format: "%.3f", value)
        case .boolean(let value): String(value)
        }
    }
}

struct DiagnosticRecord: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let timestamp: String
    let uptimeMS: Int64
    let sessionID: String
    let sequence: UInt64
    let level: DiagnosticLevel
    let category: DiagnosticCategory
    let event: DiagnosticEvent
    let traceID: String?
    let turnRef: String?
    let fields: [String: DiagnosticValue]

    enum CodingKeys: String, CodingKey {
        case fields, level, sequence
        case schemaVersion = "schema_version"
        case timestamp
        case uptimeMS = "uptime_ms"
        case sessionID = "session_id"
        case category, event
        case traceID = "trace_id"
        case turnRef = "turn_ref"
    }
}

struct DiagnosticsExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { _ in
            let url = try await MainActor.run {
                try Diagnostics.shared.makeExport()
            }
            return SentTransferredFile(url)
        }
    }
}

@MainActor
final class Diagnostics {
    static let shared = Diagnostics()
    static let schemaVersion = 1

    let sessionID = UUID().uuidString.lowercased()

    private let store: DiagnosticFileStore
    private let encoder: JSONEncoder
    private var sequence: UInt64 = 0

    private init() {
        store = DiagnosticFileStore()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func record(
        _ event: DiagnosticEvent,
        level: DiagnosticLevel = .info,
        category: DiagnosticCategory,
        traceID: String? = nil,
        turnID: String? = nil,
        fields: [DiagnosticField: DiagnosticValue] = [:]
    ) {
        sequence += 1
        let record = DiagnosticRecord(
            schemaVersion: Self.schemaVersion,
            timestamp: Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .colon)),
            uptimeMS: Int64(ProcessInfo.processInfo.systemUptime * 1_000),
            sessionID: sessionID,
            sequence: sequence,
            level: level,
            category: category,
            event: event,
            traceID: traceID,
            turnRef: turnID.map(correlationReference),
            fields: Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0.value) })
        )

        writeUnifiedLog(record)
        if let data = try? encoder.encode(record) {
            store.append(data)
        }
    }

    func saveMetricKitPayload(_ data: Data, kind: DiagnosticFileStore.ReportKind) {
        let accepted = store.saveReport(data, kind: kind)
        record(
            kind == .metric ? .metricPayloadReceived : .diagnosticPayloadReceived,
            level: accepted ? .notice : .warning,
            category: .diagnostics,
            fields: [
                .reportType: .string(kind.rawValue),
                .reportBytes: .integer(data.count),
                .reportAccepted: .boolean(accepted)
            ]
        )
    }

    func makeExport() throws -> URL {
        let url = try store.makeExport(
            sessionID: sessionID,
            schemaVersion: Self.schemaVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )
        return url
    }

    private func correlationReference(_ value: String) -> String {
        let digest = SHA256.hash(data: Data("\(sessionID):\(value)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func writeUnifiedLog(_ record: DiagnosticRecord) {
        let fields = record.fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.logDescription)" }
            .joined(separator: " ")
        let trace = record.traceID ?? "-"
        let turn = record.turnRef ?? "-"
        let logger = Self.logger(for: record.category)
        let message = "event=\(record.event.rawValue) session=\(record.sessionID) seq=\(record.sequence) trace=\(trace) turn=\(turn) \(fields)"

        switch record.level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        case .fault: logger.fault("\(message, privacy: .public)")
        }
    }

    private static func logger(for category: DiagnosticCategory) -> Logger {
        let subsystem = Bundle.main.bundleIdentifier ?? "CodexRemote"
        return Logger(subsystem: subsystem, category: category.rawValue)
    }
}
