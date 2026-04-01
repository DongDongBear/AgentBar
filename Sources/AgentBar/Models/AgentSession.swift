import Foundation

/// Represents an active agent session
final class AgentSession: ObservableObject, Identifiable {
    let id: String
    let agentType: AgentType
    let startTime: Date
    let workingDirectory: String

    @Published var status: SessionStatus
    @Published var currentTask: String?
    @Published var pendingPermission: PermissionRequest?
    @Published var pendingQuestion: UserQuestion?
    @Published var plan: String?
    @Published var lastActivity: Date
    @Published var toolHistory: [ToolEvent]

    init(
        id: String,
        agentType: AgentType,
        workingDirectory: String
    ) {
        self.id = id
        self.agentType = agentType
        self.startTime = Date()
        self.workingDirectory = workingDirectory
        self.status = .running
        self.currentTask = nil
        self.pendingPermission = nil
        self.pendingQuestion = nil
        self.plan = nil
        self.lastActivity = Date()
        self.toolHistory = []
    }
}

// MARK: - Supporting Types

enum SessionStatus: String, Codable {
    case running
    case waitingForPermission = "waiting_permission"
    case waitingForInput = "waiting_input"
    case idle
    case completed
    case error
}

struct PermissionRequest: Identifiable, Codable {
    let id: String
    let tool: String
    let description: String
    let parameters: [String: String]

    init(id: String = UUID().uuidString, tool: String, description: String, parameters: [String: String] = [:]) {
        self.id = id
        self.tool = tool
        self.description = description
        self.parameters = parameters
    }
}

struct UserQuestion: Identifiable, Codable {
    let id: String
    let question: String

    init(id: String = UUID().uuidString, question: String) {
        self.id = id
        self.question = question
    }
}

struct ToolEvent: Identifiable, Codable {
    let id: String
    let tool: String
    let timestamp: Date
    let status: ToolEventStatus

    init(id: String = UUID().uuidString, tool: String, timestamp: Date = Date(), status: ToolEventStatus = .completed) {
        self.id = id
        self.tool = tool
        self.timestamp = timestamp
        self.status = status
    }
}

enum ToolEventStatus: String, Codable {
    case pending
    case completed
    case denied
}
