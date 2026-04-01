import Foundation
import Combine

/// Central manager for all active agent sessions
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var sessions: [AgentSession] = []

    private init() {}

    // MARK: - Session Lifecycle

    func startSession(id: String, agentType: AgentType, workingDirectory: String) {
        // Avoid duplicates
        guard !sessions.contains(where: { $0.id == id }) else { return }
        let session = AgentSession(id: id, agentType: agentType, workingDirectory: workingDirectory)
        sessions.append(session)
    }

    func endSession(id: String) {
        if let session = sessions.first(where: { $0.id == id }) {
            session.status = .completed
            session.lastActivity = Date()
        }
        // Remove completed sessions after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.sessions.removeAll { $0.id == id && $0.status == .completed }
        }
    }

    // MARK: - Permission Handling

    func requestPermission(sessionId: String, request: PermissionRequest) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.pendingPermission = request
        session.status = .waitingForPermission
        session.lastActivity = Date()
    }

    func respondToPermission(sessionId: String, allow: Bool) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.pendingPermission = nil
        session.status = .running
        session.lastActivity = Date()

        let response: AgentResponse = allow ? .allow() : .deny()
        SocketServer.shared.sendResponse(sessionId: sessionId, response: response)
    }

    func clearPermission(sessionId: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.pendingPermission = nil
        session.status = .running
    }

    // MARK: - User Questions

    func askUser(sessionId: String, question: UserQuestion) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.pendingQuestion = question
        session.status = .waitingForInput
        session.lastActivity = Date()
    }

    func respondToQuestion(sessionId: String, answer: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.pendingQuestion = nil
        session.status = .running
        session.lastActivity = Date()

        SocketServer.shared.sendResponse(sessionId: sessionId, response: .answer(answer))
    }

    func clearQuestion(sessionId: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.pendingQuestion = nil
        session.status = .running
    }

    // MARK: - Updates

    func addToolEvent(sessionId: String, event: ToolEvent) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.toolHistory.append(event)
        session.currentTask = event.tool
        session.lastActivity = Date()
        if session.status != .waitingForPermission && session.status != .waitingForInput {
            session.status = .running
        }
    }

    func updateTask(sessionId: String, task: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.currentTask = task
        session.lastActivity = Date()
    }

    func updatePlan(sessionId: String, plan: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.plan = plan
        session.lastActivity = Date()
    }
}
