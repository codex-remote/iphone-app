import SwiftUI

struct MarkdownContentView: View {
    let text: String
    let baseSize: CGFloat
    let lineSpacing: CGFloat
    @State private var blocks: [Block]

    init(text: String, baseSize: CGFloat, lineSpacing: CGFloat) {
        self.text = text
        self.baseSize = baseSize
        self.lineSpacing = lineSpacing
        _blocks = State(initialValue: Self.parseBlocks(text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let value):
                    inlineText(value)
                case .heading(let level, let value):
                    inlineText(value)
                        .font(.system(size: headingSize(for: level), weight: .semibold))
                        .padding(.top, level == 1 ? 8 : 4)
                case .unorderedList(let values):
                    listStack(values: values) { _ in
                        Text("•")
                            .font(.system(size: baseSize, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                case .orderedList(let values):
                    listStack(values: values.map(\.text)) { index in
                        Text(verbatim: "\(values[index].number).")
                            .font(.system(size: baseSize, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .monospacedDigit()
                    }
                case .quote(let value):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(AppTheme.border)
                            .frame(width: 3)
                        inlineText(value)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                case .code(let value, let language):
                    CodeBlockView(code: value, language: language)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { _, value in
            blocks = Self.parseBlocks(value)
        }
    }

    private enum Block {
        case paragraph(AttributedString)
        case heading(level: Int, AttributedString)
        case unorderedList([AttributedString])
        case orderedList([(number: Int, text: AttributedString)])
        case quote(AttributedString)
        case code(String, language: String?)
    }

    private static func parseBlocks(_ text: String) -> [Block] {
        var result: [Block] = []
        var paragraphLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [(number: Int, text: String)] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var insideCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(.paragraph(markdown(paragraphLines.joined(separator: "\n"))))
            paragraphLines.removeAll()
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            result.append(.unorderedList(unorderedItems.map(markdown)))
            unorderedItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            result.append(.orderedList(orderedItems.map { ($0.number, markdown($0.text)) }))
            orderedItems.removeAll()
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            result.append(.quote(markdown(quoteLines.joined(separator: "\n"))))
            quoteLines.removeAll()
        }

        func flushTextBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushQuote()
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if insideCodeBlock {
                    result.append(.code(codeLines.joined(separator: "\n"), language: codeLanguage))
                    codeLines.removeAll()
                    codeLanguage = nil
                    insideCodeBlock = false
                } else {
                    flushTextBlocks()
                    codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if codeLanguage?.isEmpty == true { codeLanguage = nil }
                    insideCodeBlock = true
                }
                continue
            }

            if insideCodeBlock {
                codeLines.append(line)
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    flushTextBlocks()
                } else if let heading = Self.heading(from: trimmed) {
                    flushTextBlocks()
                    result.append(.heading(level: heading.level, markdown(heading.text)))
                } else if let item = Self.unorderedListItem(from: line) {
                    flushParagraph()
                    flushOrderedList()
                    flushQuote()
                    unorderedItems.append(item)
                } else if let item = Self.orderedListItem(from: line) {
                    flushParagraph()
                    flushUnorderedList()
                    flushQuote()
                    orderedItems.append(item)
                } else if let value = Self.quoteLine(from: line) {
                    flushParagraph()
                    flushUnorderedList()
                    flushOrderedList()
                    quoteLines.append(value)
                } else {
                    flushUnorderedList()
                    flushOrderedList()
                    flushQuote()
                    paragraphLines.append(line)
                }
            }
        }

        if insideCodeBlock {
            result.append(.code(codeLines.joined(separator: "\n"), language: codeLanguage))
        } else {
            flushTextBlocks()
        }

        return result
    }

    @ViewBuilder
    private func listStack<Marker: View>(
        values: [AttributedString],
        @ViewBuilder marker: @escaping (Int) -> Marker
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    marker(index)
                        .frame(width: 22, alignment: .trailing)
                    inlineText(values[index])
                }
            }
        }
    }

    private func inlineText(_ value: AttributedString) -> some View {
        Text(value)
            .font(.system(size: baseSize))
            .lineSpacing(lineSpacing)
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: baseSize + 7
        case 2: baseSize + 4
        default: baseSize + 2
        }
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(markerCount) else { return nil }
        let remainder = line.dropFirst(markerCount)
        guard remainder.first == " " else { return nil }
        return (markerCount, String(remainder.dropFirst()))
    }

    private static func unorderedListItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2 else { return nil }
        guard ["-", "*", "•"].contains(String(trimmed.prefix(1))) else { return nil }
        let remainder = trimmed.dropFirst()
        guard remainder.first == " " else { return nil }
        return String(remainder.dropFirst())
    }

    private static func orderedListItem(from line: String) -> (number: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix(while: { $0.isNumber })
        guard let number = Int(digits), !digits.isEmpty else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let marker = afterDigits.first, marker == "." || marker == ")" else { return nil }
        let remainder = afterDigits.dropFirst()
        guard remainder.first == " " else { return nil }
        return (number, String(remainder.dropFirst()))
    }

    private static func quoteLine(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == ">" else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func markdown(_ value: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: value,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(value)
    }
}
struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language {
                Text(verbatim: language)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Text(verbatim: code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
