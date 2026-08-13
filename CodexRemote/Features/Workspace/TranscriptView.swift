import SwiftUI

struct ThreadHistoryView: View {
    let transcript: ThreadTranscript?
    let loadState: ThreadDetailLoadState
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch (loadState, transcript) {
            case (.loading, nil), (.idle, nil):
                LoadingThreadDetailView()
            case (.failed, nil):
                ThreadDetailFailureView(onRetry: onRetry)
            case (.loaded, nil):
                EmptyThreadDetailView()
            case (_, let transcript?):
                if transcript.messages.isEmpty {
                    EmptyThreadDetailView()
                } else {
                    ChatTranscriptView(messages: transcript.messages)
                        .id("\(transcript.id):\(transcript.updatedAt.timeIntervalSinceReferenceDate)")
                }
            }
        }
        .accessibilityIdentifier("thread.detail")
    }
}
struct LoadingThreadDetailView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Loading session detail…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceMuted)
                    .frame(height: 74)
                    .redacted(reason: .placeholder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct ChatTranscriptView: View {
    @Environment(\.locale) private var locale
    private static let pageSize = 30

    let messages: [ThreadTranscriptMessage]
    @State private var visibleMessageCount = pageSize

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            if hasEarlierRetainedMessages {
                Button {
                    visibleMessageCount = min(messages.count, visibleMessageCount + Self.pageSize)
                } label: {
                    Label("Load earlier messages", systemImage: "arrow.up")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("thread.detail.loadEarlier")
            }

            if let date = visibleMessages.first?.occurredAt {
                DateDivider(date: date, locale: locale)
            }

            ForEach(visibleMessages) { message in
                ChatMessageRow(message: message)
            }
        }
        .accessibilityIdentifier("thread.detail.transcript")
        .accessibilityValue("\(visibleMessages.count)")
    }

    private var visibleMessages: ArraySlice<ThreadTranscriptMessage> {
        messages.suffix(visibleMessageCount)
    }

    private var hasEarlierRetainedMessages: Bool {
        visibleMessageCount < messages.count
    }
}

struct DateDivider: View {
    let date: Date
    let locale: Locale

    var body: some View {
        Text(dateLabel)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .accessibilityIdentifier("thread.detail.date")
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        if calendar.isDateInToday(date) {
            return time
        }
        if calendar.isDateInYesterday(date) {
            return "\(String(localized: "Yesterday")) \(time)"
        }
        return date.formatted(.dateTime.month().day().hour().minute().locale(locale))
    }
}

struct ChatMessageRow: View {
    let message: ThreadTranscriptMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .top) {
                Spacer(minLength: 48)
                Text(verbatim: message.text)
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityIdentifier("thread.detail.message.user")
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                MarkdownContentView(text: message.text, baseSize: 17, lineSpacing: 6)
                    .accessibilityIdentifier("thread.detail.message.assistant")

                if !message.detailItems.isEmpty {
                    ProcessDetailsDisclosure(items: message.detailItems)
                }
            }
        }
    }
}

struct ProcessDetailsDisclosure: View {
    let items: [ThreadHistoryItem]
    let identifierPrefix: String
    @State private var isExpanded = false

    init(items: [ThreadHistoryItem], identifierPrefix: String = "thread.detail.process") {
        self.items = items
        self.identifierPrefix = identifierPrefix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: summaryItem.compactActivityIcon)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16)

                    CompactActivityText(
                        text: summaryItem.compactActivityText,
                        isActive: summaryItem.isActivityInProgress
                    )

                    Spacer(minLength: 8)

                    if summaryItem.isActivityFailure {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(AppTheme.red)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifierPrefix).toggle")
            .accessibilityLabel(Text(verbatim: summaryItem.compactActivityText))
            .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(recentItems)) { item in
                        CompactProcessRow(item: item)
                    }

                    if items.count > recentItems.count {
                        Text("Only recent activity is shown")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                    }
                }
                .padding(.leading, 24)
                .accessibilityIdentifier("\(identifierPrefix).items")
            }
        }
    }

    private var summaryItem: ThreadHistoryItem {
        items.last(where: { $0.isActivityInProgress }) ?? items.last ?? .placeholder(id: "activity", field: "text")
    }

    private var recentItems: ArraySlice<ThreadHistoryItem> {
        items.suffix(6)
    }
}

struct CompactProcessRow: View {
    let item: ThreadHistoryItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.compactActivityIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 16)

            CompactActivityText(
                text: item.compactActivityText,
                isActive: item.isActivityInProgress
            )

            Spacer(minLength: 8)
            statusView
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case "inProgress":
            ProgressView().controlSize(.mini)
        case "completed":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green)
        case "failed", "declined":
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(AppTheme.red)
        default:
            EmptyView()
        }
    }
}

struct CompactActivityText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let isActive: Bool

    var body: some View {
        let label = Text(verbatim: text)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)

        label
            .foregroundStyle(AppTheme.textSecondary)
            .overlay {
                if isActive && !reduceMotion {
                    ActivityShimmer()
                        .mask(label)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct ActivityShimmer: View {
    private let cycleDuration = 1.65

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let width = max(geometry.size.width, 1)
                let bandWidth = max(48, width * 0.32)
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let progress = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.42), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth)
                .offset(x: -bandWidth + (width + bandWidth) * CGFloat(progress))
            }
        }
        .clipped()
    }
}

extension ThreadHistoryItem {
    var isActivityInProgress: Bool {
        status == "inProgress"
    }

    var isActivityFailure: Bool {
        status == "failed" || status == "declined" || (exitCode.map { $0 != 0 } ?? false)
    }

    var compactActivityIcon: String {
        switch type {
        case "reasoning": return "magnifyingglass"
        case "agentMessage": return "bubble.left"
        case "webSearch": return "globe"
        case "commandExecution": return "terminal"
        case "fileChange": return "doc.text"
        case "toolCall", "mcpToolCall", "dynamicToolCall", "collabAgentToolCall": return "wrench.and.screwdriver"
        case "contextCompaction": return "tray.full"
        default: return "circle.grid.2x2"
        }
    }

    var compactActivityText: String {
        switch type {
        case "reasoning":
            if isActivityInProgress { return String(localized: "Reviewing context") }
            return cleanActivityValue(text) ?? String(localized: "Reviewed context")
        case "commandExecution":
            let value = cleanActivityValue(command) ?? String(localized: "command")
            if isActivityInProgress {
                return String(format: String(localized: "Running %@"), value)
            }
            if isActivityFailure {
                return String(format: String(localized: "Command failed: %@"), value)
            }
            return String(format: String(localized: "Ran %@"), value)
        case "webSearch":
            let value = cleanActivityValue(query) ?? String(localized: "the web")
            if isActivityInProgress {
                return String(format: String(localized: "Searching %@"), value)
            }
            return String(format: String(localized: "Searched %@"), value)
        case "fileChange":
            let value = cleanActivityValue(path) ?? changes?.first?.path ?? String(localized: "files")
            if isActivityInProgress {
                return String(format: String(localized: "Updating %@"), value)
            }
            return String(format: String(localized: "Updated %@"), value)
        case "toolCall", "mcpToolCall", "dynamicToolCall", "collabAgentToolCall":
            let value = cleanActivityValue(name) ?? String(localized: "tool")
            if isActivityInProgress {
                return String(format: String(localized: "Using %@"), value)
            }
            return String(format: String(localized: "Used %@"), value)
        case "contextCompaction":
            return isActivityInProgress ? String(localized: "Organizing context") : String(localized: "Organized context")
        default:
            return cleanActivityValue(text) ?? cleanActivityValue(name) ?? type
        }
    }

    private func cleanActivityValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

struct ThreadDetailFailureView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unable to load session detail", systemImage: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.red)
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct EmptyThreadDetailView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No message turns yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("This session has no persisted messages from thread.read yet.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
