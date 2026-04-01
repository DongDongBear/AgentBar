import SwiftUI

/// Renders agent plan content with basic Markdown formatting
struct PlanViewerView: View {
    let markdown: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)

                    Text("Plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.purple)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Rendered markdown content
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(parseMarkdown(markdown).enumerated()), id: \.offset) { _, element in
                            markdownLine(element)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            } else {
                // Preview — first 2 lines
                let preview = markdown.components(separatedBy: .newlines)
                    .prefix(2)
                    .joined(separator: "\n")
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Markdown Parsing

    private enum MarkdownElement {
        case heading(level: Int, text: String)
        case listItem(text: String)
        case codeBlock(text: String)
        case paragraph(text: String)
        case empty
    }

    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        var inCodeBlock = false
        var codeBlockLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    elements.append(.codeBlock(text: codeBlockLines.joined(separator: "\n")))
                    codeBlockLines = []
                }
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                elements.append(.empty)
            } else if trimmed.hasPrefix("### ") {
                elements.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                elements.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                elements.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                elements.append(.listItem(text: String(trimmed.dropFirst(2))))
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                elements.append(.listItem(text: String(trimmed[match.upperBound...])))
            } else {
                elements.append(.paragraph(text: trimmed))
            }
        }

        return elements
    }

    @ViewBuilder
    private func markdownLine(_ element: MarkdownElement) -> some View {
        switch element {
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: level == 1 ? 14 : level == 2 ? 13 : 12, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, level == 1 ? 6 : 3)

        case .listItem(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundColor(.purple.opacity(0.6))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.leading, 8)

        case .codeBlock(let text):
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.green.opacity(0.8))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))

        case .paragraph(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))

        case .empty:
            Spacer().frame(height: 4)
        }
    }
}
