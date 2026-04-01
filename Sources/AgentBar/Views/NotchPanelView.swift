import SwiftUI

/// The main notch-area panel that displays agent status
struct NotchPanelView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isExpanded = true
    @State private var selectedSession: AgentSession?

    var body: some View {
        VStack(spacing: 0) {
            // Notch shape header
            notchHeader

            if isExpanded {
                // Content area
                VStack(spacing: 0) {
                    if sessionManager.sessions.isEmpty {
                        emptyState
                    } else {
                        sessionContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 370, height: isExpanded ? 470 : 44)
        .background(panelBackground)
        .clipShape(NotchShape())
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Header

    private var notchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text("AgentBar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            // Active session count badge
            if !sessionManager.sessions.isEmpty {
                Text("\(sessionManager.sessions.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor)
                    .clipShape(Capsule())
            }

            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    // MARK: - Content

    private var sessionContent: some View {
        VStack(spacing: 0) {
            if let session = selectedSession {
                // Detail view with back button
                SessionDetailView(session: session, onBack: { selectedSession = nil })
            } else {
                // Session list
                SessionListView(
                    sessions: sessionManager.sessions,
                    onSelect: { session in selectedSession = session }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            Text("Waiting for agents...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
            Text("Start Claude Code, Codex CLI, or Gemini CLI")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }

    // MARK: - Styling

    private var panelBackground: some View {
        ZStack {
            // Dark translucent background
            Color.black.opacity(0.85)

            // Subtle gradient
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var statusColor: Color {
        let hasWaiting = sessionManager.sessions.contains {
            $0.status == .waitingForPermission || $0.status == .waitingForInput
        }
        return hasWaiting ? .orange : .green
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    @ObservedObject var session: AgentSession
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(session.agentType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // Jump to terminal button
                Button(action: { jumpToTerminal(session: session) }) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Jump to terminal")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 12) {
                    // Permission request
                    if let permission = session.pendingPermission {
                        PermissionDialogView(
                            request: permission,
                            onAllow: {
                                SessionManager.shared.respondToPermission(sessionId: session.id, allow: true)
                            },
                            onDeny: {
                                SessionManager.shared.respondToPermission(sessionId: session.id, allow: false)
                            }
                        )
                    }

                    // User question with input
                    if let question = session.pendingQuestion {
                        AgentInputField(
                            question: question,
                            onSubmit: { answer in
                                SessionManager.shared.respondToQuestion(sessionId: session.id, answer: answer)
                            }
                        )
                    }

                    // Plan preview
                    if let plan = session.plan {
                        PlanViewerView(markdown: plan)
                    }

                    // Tool history
                    if !session.toolHistory.isEmpty {
                        toolHistorySection
                    }
                }
                .padding(12)
            }
        }
    }

    private var toolHistorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Tools")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)

            ForEach(session.toolHistory.suffix(10).reversed()) { event in
                HStack(spacing: 6) {
                    Circle()
                        .fill(event.status == .completed ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(event.tool)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text(event.timestamp, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }

    private func jumpToTerminal(session: AgentSession) {
        let script = """
        tell application "Terminal"
            activate
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - Notch Shape

struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 16
        let notchRadius: CGFloat = 8

        var path = Path()

        // Start from top-left with notch curve
        path.move(to: CGPoint(x: 0, y: notchRadius))
        path.addQuadCurve(
            to: CGPoint(x: notchRadius, y: 0),
            control: CGPoint(x: 0, y: 0)
        )

        // Top edge
        path.addLine(to: CGPoint(x: rect.width - notchRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: notchRadius),
            control: CGPoint(x: rect.width, y: 0)
        )

        // Right edge
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))

        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.width - cornerRadius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))

        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - cornerRadius),
            control: CGPoint(x: 0, y: rect.height)
        )

        path.closeSubpath()
        return path
    }
}
