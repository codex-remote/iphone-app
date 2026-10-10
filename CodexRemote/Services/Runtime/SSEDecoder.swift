import Foundation

struct ServerSentEvent: Equatable, Sendable {
    let id: String?
    let event: String?
    let data: String
}

struct SSEDecoder: Sendable {
    private var buffer = ""
    private var eventID: String?
    private var eventType: String?
    private var dataLines: [String] = []

    mutating func push(_ chunk: String) -> [ServerSentEvent] {
        buffer += chunk
        let normalized = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        buffer = lines.popLast() ?? ""
        return consume(lines)
    }

    mutating func finish() -> [ServerSentEvent] {
        let lines = buffer.isEmpty ? [""] : [buffer, ""]
        buffer = ""
        return consume(lines)
    }

    private mutating func consume(_ lines: [String]) -> [ServerSentEvent] {
        var result: [ServerSentEvent] = []
        for line in lines {
            if line.isEmpty {
                if !dataLines.isEmpty {
                    result.append(ServerSentEvent(id: eventID, event: eventType, data: dataLines.joined(separator: "\n")))
                }
                eventType = nil
                dataLines.removeAll(keepingCapacity: true)
                continue
            }
            if line.hasPrefix(":") { continue }
            let components = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let field = String(components[0])
            var value = components.count == 2 ? String(components[1]) : ""
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "id": eventID = value
            case "event": eventType = value
            case "data": dataLines.append(value)
            default: break
            }
        }
        return result
    }
}
