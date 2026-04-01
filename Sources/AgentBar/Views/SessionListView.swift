import SwiftUI

/// Displays a scrollable list of active agent sessions
struct SessionListView: View {
    let sessions: [AgentSession]
    let onSelect: (AgentSession) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(sessions) { session in
                    SessionRowView(session: session)
                        .onTapGesture { onSelect(session) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    @ObservedObject var session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            // Agent icon
            agentIcon

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.agentType.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    statusBadge
                }

                if let task = session.currentTask {
                    Text(task)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(shortenedPath(session.workingDirectory))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Action indicator
            actionIndicator

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Components

    private var agentIcon: some View {
        Image(systemName: session.agentType.iconName)
            .font(.system(size: 16))
            .foregroundColor(agentColor)
            .frame(width: 28, height: 28)
            .background(agentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var statusBadge: some View {
        Group {
            switch session.status {
            case .running:
                HStack(spacing: 3) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("Running")
                }
            case .waitingForPermission:
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.shield")
                    Text("Permission")
                }
                .foregroundColor(.orange)
            case .waitingForInput:
                HStack(spacing: 3) {
                    Image(systemName: "questionmark.bubble")
                    Text("Question")
                }
                .foregroundColor(.yellow)
            case .idle:
                Text("Idle")
            case .completed:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle")
                    Text("Done")
                }
                .foregroundColor(.green)
            case .error:
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle")
                    Text("Error")
                }
                .foregroundColor(.red)
            }
        }
        .font(.system(size: 10))
        .foregroundColor(.white.opacity(0.5))
    }

    private var actionIndicator: some View {
        Group {
            if session.pendingPermission != nil {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(Color.orange.opacity(0.4))
                            .frame(width: 14, height: 14)
                    )
            } else if session.pendingQuestion != nil {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(Color.yellow.opacity(0.4))
                            .frame(width: 14, height: 14)
                    )
            }
        }
    }

    private var rowBackground: some View {
        ZStack {
            Color.white.opacity(0.05)
            if session.pendingPermission != nil || session.pendingQuestion != nil {
                Color.orange.opacity(0.05)
            }
        }
    }

    private var agentColor: Color {
        Color(hex: session.agentType.accentColorHex)
    }

    private func shortenedPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 2 {
            return "~/" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}
