import SwiftUI

/// Text input field for answering agent questions — the core differentiating feature
struct AgentInputField: View {
    let question: UserQuestion
    let onSubmit: (String) -> Void

    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Question header
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)

                Text("Agent Question")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.yellow)
            }

            // Question text
            Text(question.question)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            // Input area
            VStack(spacing: 8) {
                // Multi-line text editor
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Type your answer...")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $inputText)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44, maxHeight: 120)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .focused($isFocused)
                }
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? Color.yellow.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                )

                // Submit button
                HStack {
                    // Keyboard hint
                    Text("⌘↩ to send")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))

                    Spacer()

                    Button(action: submitAnswer) {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                            Text("Send")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            inputText.isEmpty
                                ? Color.white.opacity(0.1)
                                : Color.yellow.opacity(0.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            // Auto-focus the input field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
        .modifier(CommandReturnKeyHandler(action: submitAnswer))
    }

    private func submitAnswer() {
        let answer = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        inputText = ""
        onSubmit(answer)
    }
}

// MARK: - Command+Return Key Handler

/// Handles Cmd+Return to submit. Uses onKeyPress on macOS 14+, no-op on older versions.
struct CommandReturnKeyHandler: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress(.return, modifiers: .command) {
                action()
                return .handled
            }
        } else {
            content
        }
    }
}
