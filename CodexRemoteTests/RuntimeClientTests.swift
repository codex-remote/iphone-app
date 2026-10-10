import XCTest
@testable import CodexRemote

final class RuntimeClientTests: XCTestCase {
    func testSSEDecoderHandlesChunkBoundariesCommentsAndMultilineData() {
        var decoder = SSEDecoder()
        XCTAssertTrue(decoder.push("id: 4\nevent: item.delta\ndata: {\"delta\":\"hel").isEmpty)
        let events = decoder.push("lo\",\ndata: \"type\":\"item.delta\"}\n: heartbeat\n\n")

        XCTAssertEqual(events, [ServerSentEvent(
            id: "4",
            event: "item.delta",
            data: "{\"delta\":\"hello\",\n\"type\":\"item.delta\"}"
        )])
    }

    func testPairingCodeAcceptsRawCodeAndFragmentLink() {
        XCTAssertEqual(RuntimeAuthSession.pairingCode(from: " opaque-code "), "opaque-code")
        XCTAssertEqual(
            RuntimeAuthSession.pairingCode(from: "http://192.0.2.1:18874/pair#code=one%20time"),
            "one time"
        )
        XCTAssertNil(RuntimeAuthSession.pairingCode(from: "http://192.0.2.1:18874/pair"))
        XCTAssertEqual(
            RuntimeAuthSession.pairingOrigin(from: "http://192.0.2.1:18874/pair#code=one")?.absoluteString,
            "http://192.0.2.1:18874"
        )
        XCTAssertNil(RuntimeAuthSession.pairingOrigin(from: "opaque-code"))
    }

    func testRuntimeRunMapsFinalAnswerAndToolIntoThreadHistory() throws {
        let data = Data(#"""
        {
          "run_id":"run-1","session_id":"session-1","status":"completed","state_version":4,
          "prompt":"Review it","permission_profile_id":":workspace","persisted_through_sequence":4,
          "final_sequence":4,"created_at":"2026-10-09T04:00:00Z","started_at":"2026-10-09T04:00:01Z",
          "finished_at":"2026-10-09T04:00:03Z","updated_at":"2026-10-09T04:00:03Z",
          "events":[
            {"agent_sequence":1,"type":"item.completed","occurred_at":"2026-10-09T04:00:01Z","payload":{"item":{"id":"cmd","type":"commandExecution","command":"git status","status":"completed","truncated":false}}},
            {"agent_sequence":2,"type":"item.started","occurred_at":"2026-10-09T04:00:02Z","payload":{"item":{"id":"answer","type":"agentMessage","role":"assistant","phase":"final_answer","text":"","truncated":false}}},
            {"agent_sequence":3,"type":"item.delta","occurred_at":"2026-10-09T04:00:02Z","payload":{"item_id":"answer","field":"text","delta":"Done"}},
            {"agent_sequence":4,"type":"turn.completed","occurred_at":"2026-10-09T04:00:03Z","payload":{}}
          ]
        }
        """#.utf8)
        let run = try RuntimeCoding.decoder.decode(RuntimeRun.self, from: data)
        let turn = run.threadHistoryTurn()

        XCTAssertEqual(turn.status, "completed")
        XCTAssertEqual(turn.items.first?.text, "Review it")
        XCTAssertEqual(turn.items.last?.text, "Done")
        XCTAssertEqual(turn.items.first(where: { $0.id == "cmd" })?.command, "git status")
        XCTAssertEqual(run.permissionProfileID, ":workspace")
    }

    func testCursorStoreOnlyAdvances() async {
        let suite = "RuntimeClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RuntimeCursorStore(defaults: defaults)

        await store.advance(9, origin: "http://runtime", kind: "run", id: "run-1")
        await store.advance(3, origin: "http://runtime", kind: "run", id: "run-1")

        let value = await store.value(origin: "http://runtime", kind: "run", id: "run-1")
        XCTAssertEqual(value, 9)
    }

    func testMemoryCredentialStoreReplacesAndRemovesRefreshCredential() {
        let store = MemoryCredentialStore()
        let first = RuntimeRefreshCredential(
            baseURL: "http://runtime",
            refreshToken: "secret-1",
            refreshExpiresAt: Date(timeIntervalSince1970: 100),
            clientName: "iPhone"
        )
        store.save(first)
        XCTAssertEqual(store.load(), first)
        store.remove()
        XCTAssertNil(store.load())
    }
}
