import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: summarize-diagnostics.swift INPUT OUTPUT\n".utf8))
    exit(64)
}

let fileManager = FileManager.default
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
var events: [[String: Any]] = []

func readJSONL(_ url: URL) {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
    for line in contents.split(separator: "\n") {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
        events.append(object)
    }
}

var isDirectory: ObjCBool = false
if fileManager.fileExists(atPath: input.path, isDirectory: &isDirectory), isDirectory.boolValue {
    let enumerator = fileManager.enumerator(at: input, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
        if url.pathExtension == "jsonl" {
            readJSONL(url)
        }
    }
} else if let data = try? Data(contentsOf: input),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let exportedEvents = root["events"] as? [[String: Any]] {
    events = exportedEvents
} else {
    readJSONL(input)
}

events.sort {
    let left = $0["timestamp"] as? String ?? ""
    let right = $1["timestamp"] as? String ?? ""
    if left != right { return left < right }
    return ($0["sequence"] as? UInt64 ?? 0) < ($1["sequence"] as? UInt64 ?? 0)
}

let eventCounts = Dictionary(grouping: events, by: { $0["event"] as? String ?? "unknown" })
    .mapValues(\.count)
let levelCounts = Dictionary(grouping: events, by: { $0["level"] as? String ?? "unknown" })
    .mapValues(\.count)
let sessionCounts = Dictionary(grouping: events, by: { $0["session_id"] as? String ?? "unknown" })
    .mapValues(\.count)
let notable = events.filter {
    guard let level = $0["level"] as? String else { return false }
    return ["warning", "error", "fault"].contains(level)
}.suffix(100)

let summary: [String: Any] = [
    "format": "codexremote-diagnostics-summary",
    "event_count": events.count,
    "first_timestamp": events.first?["timestamp"] ?? NSNull(),
    "last_timestamp": events.last?["timestamp"] ?? NSNull(),
    "events_by_name": eventCounts,
    "events_by_level": levelCounts,
    "events_by_session": sessionCounts,
    "notable_events": Array(notable)
]

let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: output, options: .atomic)
