import Foundation

/// Installs hook scripts for each supported AI agent
final class HookInstaller {

    /// Install hooks for all supported agents
    func installAll() {
        installHookScript()
        for agentType in AgentType.allCases {
            installConfig(for: agentType)
        }
        print("[AgentBar] Hooks installed for all agents")
    }

    // MARK: - Hook Script

    /// Install the shared hook script that all agents will call
    private func installHookScript() {
        let scriptDir = Constants.hookScriptDirectory
        let scriptPath = Constants.hookScriptPath

        // Create directory
        try? FileManager.default.createDirectory(atPath: scriptDir, withIntermediateDirectories: true)

        let script = """
        #!/bin/bash
        # AgentBar hook script — sends events to AgentBar via Unix socket
        # Usage: agentbar-hook.sh <agent_type> <event_type>
        # Reads JSON payload from stdin, forwards to AgentBar socket, returns response.

        SOCKET_PATH="\(Constants.socketPath)"
        AGENT_TYPE="${1:-unknown}"
        EVENT_TYPE="${2:-notification}"
        SESSION_ID="${CLAUDE_SESSION_ID:-${CODEX_SESSION_ID:-${GEMINI_SESSION_ID:-$(uuidgen 2>/dev/null || echo $$)}}}"
        WORKING_DIR="${PWD}"

        # Check if socket exists
        if [ ! -S "$SOCKET_PATH" ]; then
            # AgentBar not running — pass through silently
            if [ "$EVENT_TYPE" = "permission_request" ] || [ "$EVENT_TYPE" = "pre_tool_use" ]; then
                echo '{"action":"allow","text":null}'
            fi
            exit 0
        fi

        # Read stdin if available
        PAYLOAD="{}"
        if [ ! -t 0 ]; then
            PAYLOAD=$(cat)
        fi

        # Build the message
        MESSAGE=$(cat <<EOF
        {"sessionId":"${SESSION_ID}","agentType":"${AGENT_TYPE}","event":"${EVENT_TYPE}","workingDirectory":"${WORKING_DIR}","payload":${PAYLOAD}}
        EOF
        )

        # Send to socket and get response
        # Use socat if available, fall back to /dev/tcp or nc
        if command -v socat &>/dev/null; then
            RESPONSE=$(echo "$MESSAGE" | socat - UNIX-CONNECT:"$SOCKET_PATH" 2>/dev/null)
        elif command -v nc &>/dev/null; then
            RESPONSE=$(echo "$MESSAGE" | nc -U "$SOCKET_PATH" 2>/dev/null)
        else
            # Last resort: use python
            RESPONSE=$(python3 -c "
        import socket, sys
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect('$SOCKET_PATH')
        s.sendall(sys.stdin.buffer.read())
        s.shutdown(socket.SHUT_WR)
        data = b''
        while True:
            chunk = s.recv(4096)
            if not chunk: break
            data += chunk
        sys.stdout.buffer.write(data)
        s.close()
        " <<< "$MESSAGE" 2>/dev/null)
        fi

        # Output response (agents read this from stdout)
        if [ -n "$RESPONSE" ]; then
            echo "$RESPONSE"

            # For permission requests, extract action and exit with appropriate code
            ACTION=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('action',''))" 2>/dev/null)
            if [ "$EVENT_TYPE" = "permission_request" ] || [ "$EVENT_TYPE" = "pre_tool_use" ]; then
                if [ "$ACTION" = "deny" ]; then
                    exit 2
                fi
            fi

            # For ask_user, extract the answer text
            if [ "$EVENT_TYPE" = "ask_user" ]; then
                ANSWER=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))" 2>/dev/null)
                if [ -n "$ANSWER" ]; then
                    echo "$ANSWER"
                fi
            fi
        fi

        exit 0
        """

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            // Make executable
            let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath)
            print("[AgentBar] Hook script installed at \(scriptPath)")
        } catch {
            print("[AgentBar] Failed to install hook script: \(error)")
        }
    }

    // MARK: - Agent Configurations

    private func installConfig(for agentType: AgentType) {
        switch agentType {
        case .claudeCode:
            installClaudeCodeHooks()
        case .codexCLI:
            installCodexHooks()
        case .geminiCLI:
            installGeminiHooks()
        }
    }

    private func installClaudeCodeHooks() {
        let configPath = AgentType.claudeCode.hookConfigPath
        let hookScript = Constants.hookScriptPath

        // Read existing config or create new
        var config = readJSON(at: configPath) ?? [String: Any]()

        let hooks: [String: Any] = [
            "PreToolUse": [
                ["type": "command", "command": "\(hookScript) claude_code pre_tool_use"]
            ],
            "PostToolUse": [
                ["type": "command", "command": "\(hookScript) claude_code post_tool_use"]
            ],
            "Notification": [
                ["type": "command", "command": "\(hookScript) claude_code notification"]
            ]
        ]

        config["hooks"] = hooks

        writeJSON(config, to: configPath)
        print("[AgentBar] Claude Code hooks configured at \(configPath)")
    }

    private func installCodexHooks() {
        let configPath = AgentType.codexCLI.hookConfigPath
        let hookScript = Constants.hookScriptPath

        let hooks: [String: Any] = [
            "pre_tool_use": "\(hookScript) codex_cli pre_tool_use",
            "post_tool_use": "\(hookScript) codex_cli post_tool_use",
            "on_notification": "\(hookScript) codex_cli notification",
            "ask_user": "\(hookScript) codex_cli ask_user"
        ]

        writeJSON(hooks, to: configPath)
        print("[AgentBar] Codex CLI hooks configured at \(configPath)")
    }

    private func installGeminiHooks() {
        let configPath = AgentType.geminiCLI.hookConfigPath
        let hookScript = Constants.hookScriptPath

        var config = readJSON(at: configPath) ?? [String: Any]()

        let hooks: [String: Any] = [
            "pre_tool_use": "\(hookScript) gemini_cli pre_tool_use",
            "post_tool_use": "\(hookScript) gemini_cli post_tool_use",
            "notification": "\(hookScript) gemini_cli notification"
        ]

        config["hooks"] = hooks

        writeJSON(config, to: configPath)
        print("[AgentBar] Gemini CLI hooks configured at \(configPath)")
    }

    // MARK: - JSON Helpers

    private func readJSON(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func writeJSON(_ dict: [String: Any], to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        FileManager.default.createFile(atPath: path, contents: data)
    }
}
