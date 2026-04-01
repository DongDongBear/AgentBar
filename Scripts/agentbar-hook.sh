#!/bin/bash
# AgentBar hook script — sends events to AgentBar via Unix socket
# This is a standalone copy for manual installation.
# AgentBar auto-installs this to ~/.agentbar/agentbar-hook.sh on launch.
#
# Usage: agentbar-hook.sh <agent_type> <event_type>
# Reads JSON payload from stdin, forwards to AgentBar socket, returns response on stdout.

SOCKET_PATH="/tmp/agentbar.sock"
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
if command -v socat &>/dev/null; then
    RESPONSE=$(echo "$MESSAGE" | socat - UNIX-CONNECT:"$SOCKET_PATH" 2>/dev/null)
elif command -v nc &>/dev/null; then
    RESPONSE=$(echo "$MESSAGE" | nc -U "$SOCKET_PATH" 2>/dev/null)
else
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

# Output response
if [ -n "$RESPONSE" ]; then
    echo "$RESPONSE"

    ACTION=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('action',''))" 2>/dev/null)
    if [ "$EVENT_TYPE" = "permission_request" ] || [ "$EVENT_TYPE" = "pre_tool_use" ]; then
        if [ "$ACTION" = "deny" ]; then
            exit 2
        fi
    fi

    if [ "$EVENT_TYPE" = "ask_user" ]; then
        ANSWER=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))" 2>/dev/null)
        if [ -n "$ANSWER" ]; then
            echo "$ANSWER"
        fi
    fi
fi

exit 0
