import Foundation

/// High-frequency Turn state isolated from project navigation and connection state.
/// Relay events are reduced here so streaming deltas only invalidate views that
/// explicitly observe this store.
@MainActor
final class TurnSessionStore: ObservableObject {
    private static let liveFieldLimit = 24_576
    private static let liveItemLimit = 80
    private static let liveChangeLimit = 20
    private static let logFieldLimit = 8_192

    @Published private(set) var phase: TurnPhase = .idle
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var items: [ThreadHistoryItem] = []
    @Published private(set) var itemsTruncated = false
    @Published private(set) var submittedPrompt: String?
    @Published private(set) var startedAt: Date?
    @Published private(set) var result: TurnResult?

    private(set) var activeTurnID: String?
    private var lastItemSequence: Int64 = 0
    private var hasStructuredItems = false

    var isRunning: Bool { phase == .running }
    var retainedCharacterCount: Int {
        items.reduce(0) { total, item in
            total + [item.text, item.name, item.command, item.cwd, item.output, item.path, item.query]
                .compactMap { $0?.count }
                .reduce(0, +)
        } + logs.reduce(0) { $0 + $1.text.count }
    }

    func prepareSubmission(_ prompt: String) {
        submittedPrompt = prompt
        items.removeAll()
        itemsTruncated = false
        logs.removeAll()
        result = nil
        activeTurnID = nil
        lastItemSequence = 0
        hasStructuredItems = false
    }

    func reset() {
        phase = .idle
        submittedPrompt = nil
        logs.removeAll()
        items.removeAll()
        itemsTruncated = false
        startedAt = nil
        result = nil
        activeTurnID = nil
        lastItemSequence = 0
        hasStructuredItems = false
    }

    func markConnectionLost() {
        guard isRunning else { return }
        phase = .failed
        result = TurnResult(
            title: String(localized: "Turn connection lost"),
            detail: String(localized: "The Mac Agent disconnected before the Turn completed."),
            changedFiles: 0,
            duration: startedAt.map { Date().timeIntervalSince($0) } ?? 0
        )
    }

    func started(turnID: String, at date: Date) {
        if activeTurnID != turnID {
            items.removeAll()
            itemsTruncated = false
            lastItemSequence = 0
            hasStructuredItems = false
        }
        phase = .running
        activeTurnID = turnID
        startedAt = date
        result = nil
    }

    func restored(
        turnID: String,
        at date: Date,
        items restoredItems: [ThreadHistoryItem],
        sequence: Int64,
        itemsTruncated: Bool,
        recentOutput: [String],
        consoleLimit: Int
    ) {
        phase = .running
        activeTurnID = turnID
        startedAt = date
        result = nil
        items = restoredItems.suffix(Self.liveItemLimit).map(Self.boundedItem)
        self.itemsTruncated = itemsTruncated || restoredItems.count > Self.liveItemLimit
        lastItemSequence = sequence
        hasStructuredItems = !restoredItems.isEmpty
        if restoredItems.isEmpty {
            logs = recentOutput.suffix(consoleLimit).map {
                LogEntry(stream: .stdout, text: Self.limitedLogText($0))
            }
        } else {
            logs.removeAll()
        }
    }

    func itemStarted(turnID: String, sequence: Int64, item: ThreadHistoryItem) {
        guard acceptsItemEvent(turnID: turnID, sequence: sequence) else { return }
        hasStructuredItems = true
        upsert(item)
    }

    func appendDelta(turnID: String, sequence: Int64, itemID: String, field: String, delta: String) {
        guard acceptsItemEvent(turnID: turnID, sequence: sequence), !delta.isEmpty else { return }
        hasStructuredItems = true
        let index: Int
        if let existing = items.firstIndex(where: { $0.id == itemID }) {
            index = existing
        } else {
            items.append(.placeholder(id: itemID, field: field))
            index = items.count - 1
        }
        if field == "output" {
            items[index].output = limitedAppend(current: items[index].output, delta: delta, itemIndex: index)
        } else {
            items[index].text = limitedAppend(current: items[index].text, delta: delta, itemIndex: index)
        }
    }

    func itemCompleted(turnID: String, sequence: Int64, item: ThreadHistoryItem) {
        guard acceptsItemEvent(turnID: turnID, sequence: sequence) else { return }
        hasStructuredItems = true
        upsert(item)
    }

    func appendOutput(_ entry: LogEntry, consoleLimit: Int) {
        if hasStructuredItems && (entry.stream == .assistant || entry.stream == .stdout) { return }
        logs.append(Self.boundedLogEntry(entry))
        if logs.count > consoleLimit {
            logs.removeFirst(logs.count - consoleLimit)
        }
    }

    func end(phase: TurnPhase, result: TurnResult?) {
        self.phase = phase
        self.result = phase == .completed ? nil : result
    }

    func reconcile(with detail: ThreadDetail, detailTruncated: Bool) {
        guard phase.isTerminal, let activeTurnID,
              let turn = detail.turns.first(where: { $0.id == activeTurnID }) else { return }
        items = turn.items.suffix(Self.liveItemLimit).map(Self.boundedItem)
        itemsTruncated = detailTruncated || turn.truncated || turn.items.count > Self.liveItemLimit
        hasStructuredItems = !turn.items.isEmpty
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func acceptsItemEvent(turnID: String, sequence: Int64) -> Bool {
        guard activeTurnID == nil || activeTurnID == turnID else { return false }
        guard sequence > lastItemSequence else { return false }
        activeTurnID = turnID
        lastItemSequence = sequence
        return true
    }

    private func upsert(_ item: ThreadHistoryItem) {
        let item = Self.boundedItem(item)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
            if items.count > Self.liveItemLimit {
                items.removeFirst(items.count - Self.liveItemLimit)
                itemsTruncated = true
            }
        }
    }

    private func limitedAppend(current: String?, delta: String, itemIndex: Int) -> String {
        let current = current ?? ""
        let remainingCapacity = Self.liveFieldLimit - current.count
        guard remainingCapacity > 0 else {
            items[itemIndex].truncated = true
            itemsTruncated = true
            return current
        }
        guard delta.count > remainingCapacity else { return current + delta }
        items[itemIndex].truncated = true
        itemsTruncated = true
        return current + delta.prefix(remainingCapacity)
    }

    private static func boundedItem(_ item: ThreadHistoryItem) -> ThreadHistoryItem {
        item.bounded(fieldCharacterLimit: liveFieldLimit, changeLimit: liveChangeLimit)
    }

    private static func boundedLogEntry(_ entry: LogEntry) -> LogEntry {
        LogEntry(id: entry.id, timestamp: entry.timestamp, stream: entry.stream, text: limitedLogText(entry.text))
    }

    private static func limitedLogText(_ text: String) -> String {
        text.count > logFieldLimit ? String(text.prefix(logFieldLimit)) : text
    }
}
