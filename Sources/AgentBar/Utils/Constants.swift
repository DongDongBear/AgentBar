import Foundation

enum Constants {
    static let socketPath = "/tmp/agentbar.sock"

    static var hookScriptDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.agentbar"
    }

    static var hookScriptPath: String {
        return "\(hookScriptDirectory)/agentbar-hook.sh"
    }

    static let maxSessionHistory = 100
    static let panelWidth: CGFloat = 370
    static let panelCollapsedHeight: CGFloat = 44
    static let panelExpandedHeight: CGFloat = 470
    static let permissionTimeoutSeconds: TimeInterval = 300
    static let questionTimeoutSeconds: TimeInterval = 600
}
