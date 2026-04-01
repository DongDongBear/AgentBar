import Foundation

/// Messages sent from hook scripts to AgentBar via Unix socket
struct AgentMessage: Codable {
    let sessionId: String
    let agentType: AgentType
    let event: EventType
    let payload: MessagePayload
    let workingDirectory: String?

    enum EventType: String, Codable {
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case preToolUse = "pre_tool_use"
        case postToolUse = "post_tool_use"
        case permissionRequest = "permission_request"
        case askUser = "ask_user"
        case notification = "notification"
        case planUpdate = "plan_update"
    }
}

/// Payload data carried by agent messages
struct MessagePayload: Codable {
    var tool: String?
    var description: String?
    var question: String?
    var plan: String?
    var parameters: [String: String]?
    var message: String?
    var status: String?
}

/// Response sent back to hook scripts from AgentBar
struct AgentResponse: Codable {
    let action: ResponseAction
    let text: String?

    enum ResponseAction: String, Codable {
        case allow
        case deny
        case answer
        case acknowledge
    }

    static func allow() -> AgentResponse {
        AgentResponse(action: .allow, text: nil)
    }

    static func deny() -> AgentResponse {
        AgentResponse(action: .deny, text: nil)
    }

    static func answer(_ text: String) -> AgentResponse {
        AgentResponse(action: .answer, text: text)
    }

    static func acknowledge() -> AgentResponse {
        AgentResponse(action: .acknowledge, text: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let agentEventReceived = Notification.Name("agentEventReceived")
}
