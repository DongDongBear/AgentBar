import Foundation

/// Supported AI agent types
enum AgentType: String, Codable, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case codexCLI = "codex_cli"
    case geminiCLI = "gemini_cli"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        case .geminiCLI: return "Gemini CLI"
        }
    }

    var iconName: String {
        switch self {
        case .claudeCode: return "c.circle.fill"
        case .codexCLI: return "o.circle.fill"
        case .geminiCLI: return "g.circle.fill"
        }
    }

    var accentColorHex: String {
        switch self {
        case .claudeCode: return "#D97757"  // Claude orange
        case .codexCLI: return "#10A37F"    // OpenAI green
        case .geminiCLI: return "#4285F4"   // Google blue
        }
    }

    /// Path to the hook configuration file for this agent
    var hookConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claudeCode: return "\(home)/.claude/settings.json"
        case .codexCLI: return "\(home)/.codex/hooks.json"
        case .geminiCLI: return "\(home)/.gemini/settings.json"
        }
    }
}
