import XCTest
@testable import CodexRemote

@MainActor
final class TurnSessionStoreTests: XCTestCase {
    func testRejectsDuplicateAndOutOfOrderDeltas() {
        let store = TurnSessionStore()
        store.started(turnID: "turn-1", at: Date())

        store.appendDelta(turnID: "turn-1", sequence: 2, itemID: "answer", field: "text", delta: "Hello")
        store.appendDelta(turnID: "turn-1", sequence: 2, itemID: "answer", field: "text", delta: " duplicate")
        store.appendDelta(turnID: "turn-1", sequence: 1, itemID: "answer", field: "text", delta: " stale")

        XCTAssertEqual(store.items.first?.text, "Hello")
    }

    func testBoundsLiveTextAndMarksTruncation() {
        let store = TurnSessionStore()
        store.started(turnID: "turn-1", at: Date())

        store.appendDelta(
            turnID: "turn-1",
            sequence: 1,
            itemID: "answer",
            field: "text",
            delta: String(repeating: "a", count: 30_000)
        )

        XCTAssertEqual(store.items.first?.text?.count, 24_576)
        XCTAssertEqual(store.items.first?.truncated, true)
        XCTAssertTrue(store.itemsTruncated)

        store.appendDelta(
            turnID: "turn-1",
            sequence: 2,
            itemID: "answer",
            field: "text",
            delta: String(repeating: "b", count: 30_000)
        )
        XCTAssertEqual(store.items.first?.text?.count, 24_576)
    }

    func testResetClearsTurnState() {
        let store = TurnSessionStore()
        store.prepareSubmission("Review this")
        store.started(turnID: "turn-1", at: Date())
        store.appendDelta(turnID: "turn-1", sequence: 1, itemID: "answer", field: "text", delta: "Done")

        store.reset()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertNil(store.submittedPrompt)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.logs.isEmpty)
        XCTAssertNil(store.activeTurnID)
    }

    func testRetainedCharacterCountReflectsBoundedContent() {
        let store = TurnSessionStore()
        store.started(turnID: "turn-1", at: Date())
        store.appendDelta(
            turnID: "turn-1",
            sequence: 1,
            itemID: "answer",
            field: "text",
            delta: String(repeating: "a", count: 30_000)
        )
        store.appendOutput(LogEntry(stream: .stderr, text: "failure"), consoleLimit: 500)

        XCTAssertEqual(store.retainedCharacterCount, 24_576 + 7)
    }

    func testRelayDecoderAcceptsFractionalAndWholeSecondDates() throws {
        struct Payload: Decodable { let date: Date }

        let withFraction = try JSONDecoder.relay.decode(
            Payload.self,
            from: Data(#"{"date":"2026-08-12T08:34:43.123Z"}"#.utf8)
        )
        let withoutFraction = try JSONDecoder.relay.decode(
            Payload.self,
            from: Data(#"{"date":"2026-08-12T08:34:43Z"}"#.utf8)
        )

        XCTAssertEqual(withFraction.date.timeIntervalSince(withoutFraction.date), 0.123, accuracy: 0.001)
    }

    func testVoiceRecognitionDurationStaysBelowFrameworkLimit() {
        XCTAssertEqual(VoiceTranscriptionController.maximumRecordingDuration, .seconds(55))
    }

    func testRelayEventBufferKeepsNewestEventsWhenProducerOutrunsConsumer() async {
        let buffer = RelayEventBuffer()
        let stream = buffer.stream()
        for index in 0..<70 {
            buffer.yield(.output(LogEntry(stream: .system, text: "event-\(index)")))
        }

        var iterator = stream.makeAsyncIterator()
        var received: [String] = []
        for _ in 0..<64 {
            guard case .output(let entry) = await iterator.next() else {
                return XCTFail("Expected a buffered output event")
            }
            received.append(entry.text)
        }

        XCTAssertEqual(received.first, "event-6")
        XCTAssertEqual(received.last, "event-69")
    }

    func testDiagnosticRecordUsesStableMachineReadableKeys() throws {
        let record = DiagnosticRecord(
            schemaVersion: 1,
            timestamp: "2026-08-12T08:34:43.123Z",
            uptimeMS: 12_345,
            sessionID: "session-test",
            sequence: 9,
            level: .warning,
            category: .memory,
            event: .memoryWarning,
            traceID: "trace-test",
            turnRef: "turn-reference",
            fields: ["available_mb": .integer(128)]
        )

        let data = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["session_id"] as? String, "session-test")
        XCTAssertEqual(object["trace_id"] as? String, "trace-test")
        XCTAssertEqual(object["turn_ref"] as? String, "turn-reference")
        XCTAssertEqual(object["event"] as? String, "memory.warning")
        XCTAssertEqual((object["fields"] as? [String: Any])?["available_mb"] as? Int, 128)
    }

    func testDiagnosticFileStoreRotatesAndPreservesValidJSONLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "diagnostic-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticFileStore(directory: directory, eventFileBytes: 90, eventFileLimit: 2)

        for sequence in 1...5 {
            let line = try JSONSerialization.data(withJSONObject: [
                "sequence": sequence,
                "event": "memory.snapshot",
                "fields": ["value": sequence]
            ], options: [.sortedKeys])
            try store.appendSynchronously(line)
        }

        let files = store.eventFileURLs()
        XCTAssertLessThanOrEqual(files.count, 2)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for line in contents.split(separator: "\n") {
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
            }
        }
    }
}
