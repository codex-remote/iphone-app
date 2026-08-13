import Foundation

struct ThreadTranscript: Identifiable, Sendable {
    static let maximumRetainedMessages = 60

    let id: String
    let projectID: String
    let updatedAt: Date
    let messages: [ThreadTranscriptMessage]
    let hasEarlierMessages: Bool

    init(detail: ThreadDetail, sourceTruncated: Bool) {
        id = detail.id
        projectID = detail.projectID
        updatedAt = detail.updatedAt

        var retainedBatches: [[ThreadTranscriptMessage]] = []
        var retainedMessageCount = 0
        var omittedMessages = sourceTruncated

        for (reverseIndex, turn) in detail.turns.reversed().enumerated() {
            let remainingCapacity = Self.maximumRetainedMessages - retainedMessageCount
            guard remainingCapacity > 0 else {
                omittedMessages = true
                break
            }

            let batch = ThreadTranscriptMessage.messages(
                from: turn,
                fallbackDate: detail.updatedAt,
                limit: remainingCapacity
            )
            if batch.wasLimited {
                omittedMessages = true
            }
            if !batch.messages.isEmpty {
                retainedBatches.append(batch.messages)
                retainedMessageCount += batch.messages.count
            }

            if retainedMessageCount == Self.maximumRetainedMessages,
               reverseIndex < detail.turns.count - 1 {
                omittedMessages = true
                break
            }
        }

        messages = retainedBatches.reversed().flatMap { $0 }
        hasEarlierMessages = omittedMessages
    }
}

struct ThreadTranscriptMessage: Identifiable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    private static let maximumMessageCharacters = 24_576
    private static let maximumProcessItems = 8
    private static let maximumProcessFieldCharacters = 8_192
    private static let maximumFileChanges = 20

    let id: String
    let role: Role
    let text: String
    let occurredAt: Date?
    let detailItems: [ThreadHistoryItem]

    static func messages(
        from turn: ThreadHistoryTurn,
        fallbackDate: Date,
        limit: Int
    ) -> (messages: [ThreadTranscriptMessage], wasLimited: Bool) {
        guard limit > 0 else { return ([], true) }
        let occurredAt = turn.completedAt ?? turn.startedAt ?? fallbackDate
        let hasFinalAnswer = turn.items.contains { item in
            item.type == "agentMessage" && item.phase == "final_answer" && cleanText(item.text) != nil
        }

        var reversedMessages: [ThreadTranscriptMessage] = []
        var visibleAssistantIDs: Set<String> = []
        var foundAnotherMessage = false

        for item in turn.items.reversed() {
            let role: Role?
            if item.type == "userMessage" {
                role = .user
            } else if item.type == "agentMessage",
                      !hasFinalAnswer || item.phase == "final_answer" {
                role = .assistant
            } else {
                role = nil
            }

            guard let role, let text = cleanText(item.text) else { continue }
            guard reversedMessages.count < limit else {
                foundAnotherMessage = true
                break
            }

            if role == .assistant {
                visibleAssistantIDs.insert(item.id)
            }
            reversedMessages.append(
                ThreadTranscriptMessage(
                    id: item.id,
                    role: role,
                    text: limited(text, to: maximumMessageCharacters),
                    occurredAt: occurredAt,
                    detailItems: []
                )
            )
        }

        var messages = Array(reversedMessages.reversed())
        if let assistantIndex = messages.lastIndex(where: { $0.role == .assistant }) {
            let details = turn.items.reversed().lazy
                .filter { $0.type != "userMessage" && !visibleAssistantIDs.contains($0.id) }
                .prefix(maximumProcessItems)
                .map {
                    $0.bounded(
                        fieldCharacterLimit: maximumProcessFieldCharacters,
                        changeLimit: maximumFileChanges
                    )
                }
                .reversed()
            let assistant = messages[assistantIndex]
            messages[assistantIndex] = ThreadTranscriptMessage(
                id: assistant.id,
                role: assistant.role,
                text: assistant.text,
                occurredAt: assistant.occurredAt,
                detailItems: Array(details)
            )
        }

        return (messages, foundAnotherMessage)
    }

    private static func limited(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit))
    }

    private static func cleanText(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension ThreadHistoryItem {
    func bounded(fieldCharacterLimit: Int, changeLimit: Int) -> ThreadHistoryItem {
        let boundedChanges = changes.map { values in
            values.prefix(changeLimit).map { change in
                ThreadFileChange(
                    path: Self.limited(change.path, to: fieldCharacterLimit),
                    kind: change.kind,
                    diff: nil
                )
            }
        }
        let wasLimited = [text, name, command, cwd, output, path, query]
            .compactMap { $0 }
            .contains { $0.count > fieldCharacterLimit }
            || (changes?.count ?? 0) > changeLimit
            || (changes?.contains { $0.diff != nil } ?? false)

        return ThreadHistoryItem(
            id: id,
            type: type,
            role: role,
            phase: phase,
            status: status,
            text: Self.limitedOptional(text, to: fieldCharacterLimit),
            name: Self.limitedOptional(name, to: fieldCharacterLimit),
            command: Self.limitedOptional(command, to: fieldCharacterLimit),
            cwd: Self.limitedOptional(cwd, to: fieldCharacterLimit),
            output: Self.limitedOptional(output, to: fieldCharacterLimit),
            path: Self.limitedOptional(path, to: fieldCharacterLimit),
            query: Self.limitedOptional(query, to: fieldCharacterLimit),
            exitCode: exitCode,
            durationMS: durationMS,
            changes: boundedChanges,
            truncated: truncated || wasLimited
        )
    }

    private static func limitedOptional(_ value: String?, to limit: Int) -> String? {
        value.map { limited($0, to: limit) }
    }

    private static func limited(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit))
    }
}
