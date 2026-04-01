# AgentBar 通信协议规范

## 概述

AgentBar 通过 Unix domain socket 接收来自 AI Agent hook 脚本的消息，并将用户的操作结果返回给 hook 脚本。

## 连接信息

| 项目 | 值 |
|------|------|
| Socket 路径 | `/tmp/agentbar.sock` |
| Socket 类型 | Unix domain socket (`AF_UNIX`) |
| Socket 模式 | `SOCK_STREAM`（流式） |
| 消息格式 | 每行一个 JSON，以 `\n` 换行结尾 |
| 编码 | UTF-8 |
| 权限 | `0o777`（任何用户进程可连接） |

## 连接模式

每条消息使用**独立连接**（短连接）：

1. 客户端建立连接
2. 客户端发送一行 JSON（以 `\n` 结尾）
3. 客户端关闭写端（`shutdown(SHUT_WR)`）
4. 服务端处理消息
5. 服务端返回一行 JSON 响应
6. 连接关闭

对于需要用户交互的消息（权限请求、提问），服务端会阻塞直到用户操作完成或超时。

## 入站消息格式

所有从 hook 脚本发给 AgentBar 的消息共享以下基础结构：

```json
{
  "sessionId": "string — 会话唯一标识符",
  "agentType": "string — Agent 类型 (claude_code / codex_cli / gemini_cli)",
  "event": "string — 事件类型",
  "workingDirectory": "string? — Agent 的工作目录（可选）",
  "payload": { }
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sessionId` | string | 是 | 会话 ID，同一 Agent 进程使用相同 ID。通常取自环境变量 `$CLAUDE_SESSION_ID` 等 |
| `agentType` | string | 是 | 枚举值：`claude_code`、`codex_cli`、`gemini_cli` |
| `event` | string | 是 | 事件类型，见下方完整定义 |
| `workingDirectory` | string | 否 | Agent 的当前工作目录，默认为 `$PWD` |
| `payload` | object | 是 | 事件相关数据，不同事件类型包含不同字段 |

---

## 消息类型详细定义

### 1. `session_start` — 会话开始

Agent 启动或新会话开始时发送。AgentBar 将创建新的会话条目。

**Payload 字段**：无（`payload` 可以为空对象 `{}`）

**完整示例**：

```json
{
  "sessionId": "claude-abc123",
  "agentType": "claude_code",
  "event": "session_start",
  "workingDirectory": "/Users/dev/my-project",
  "payload": {}
}
```

**响应**：`acknowledge`

---

### 2. `session_end` — 会话结束

Agent 退出或会话结束时发送。AgentBar 将标记会话为已完成，5 秒后从列表中移除。

**Payload 字段**：无

**完整示例**：

```json
{
  "sessionId": "claude-abc123",
  "agentType": "claude_code",
  "event": "session_end",
  "workingDirectory": "/Users/dev/my-project",
  "payload": {}
}
```

**响应**：`acknowledge`

---

### 3. `pre_tool_use` / `permission_request` — 权限请求

Agent 请求执行工具前发送，等待用户允许或拒绝。消息发送后连接会**阻塞**，直到用户操作或超时（5 分钟）。

**Payload 字段**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tool` | string | 是 | 工具名称（如 `Bash`、`Edit`、`Write`） |
| `description` | string | 否 | 操作描述（如 `Run: rm -rf /tmp/old`） |
| `parameters` | object | 否 | 工具参数键值对 |

**完整示例**：

```json
{
  "sessionId": "claude-abc123",
  "agentType": "claude_code",
  "event": "permission_request",
  "workingDirectory": "/Users/dev/my-project",
  "payload": {
    "tool": "Bash",
    "description": "Run: npm install express@latest",
    "parameters": {
      "command": "npm install express@latest"
    }
  }
}
```

**响应**：`allow` 或 `deny`

**超时行为**：5 分钟无响应自动返回 `deny`

---

### 4. `post_tool_use` — 工具使用完成

Agent 工具执行完成后发送。用于记录工具使用历史。

**Payload 字段**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tool` | string | 否 | 工具名称 |
| `status` | string | 否 | 执行结果：`completed` 或 `denied` |

**完整示例**：

```json
{
  "sessionId": "claude-abc123",
  "agentType": "claude_code",
  "event": "post_tool_use",
  "workingDirectory": "/Users/dev/my-project",
  "payload": {
    "tool": "Bash",
    "status": "completed"
  }
}
```

**响应**：`acknowledge`

---

### 5. `ask_user` — Agent 提问

Agent 需要用户输入文字回答时发送。消息发送后连接会**阻塞**，直到用户输入并发送或超时（10 分钟）。

**Payload 字段**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `question` | string | 是 | Agent 的问题文本 |

**完整示例**：

```json
{
  "sessionId": "claude-abc123",
  "agentType": "claude_code",
  "event": "ask_user",
  "workingDirectory": "/Users/dev/my-project",
  "payload": {
    "question": "Which database should I use? PostgreSQL or SQLite?"
  }
}
```

**响应**：`answer`（携带用户输入的文字）

**超时行为**：10 分钟无响应自动返回空字符串 `answer("")`

---

### 6. `notification` — 通知消息

Agent 发送的状态通知或进度更新。仅展示，不需要用户交互。

**Payload 字段**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `message` | string | 否 | 通知文本 |

**完整示例**：

```json
{
  "sessionId": "claude-abc123",
  "agentType": "claude_code",
  "event": "notification",
  "workingDirectory": "/Users/dev/my-project",
  "payload": {
    "message": "Compiling project... (3/10 files)"
  }
}
```

**响应**：`acknowledge`

---

### 7. `plan_update` — 计划更新

Agent 发送执行计划的内容（Markdown 格式）。在面板中渲染为可展开的计划预览。

**Payload 字段**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `plan` | string | 否 | Markdown 格式的计划内容 |

**完整示例**：

```json
{
  "sessionId": "claude-abc123",
  "agentType": "claude_code",
  "event": "plan_update",
  "workingDirectory": "/Users/dev/my-project",
  "payload": {
    "plan": "## Implementation Plan\n\n1. Create database schema\n2. Implement API endpoints\n3. Add unit tests\n\n```sql\nCREATE TABLE users (\n  id SERIAL PRIMARY KEY,\n  name TEXT NOT NULL\n);\n```"
  }
}
```

**响应**：`acknowledge`

---

## 响应格式

所有从 AgentBar 返回给 hook 脚本的响应共享以下结构：

```json
{
  "action": "string — 响应动作",
  "text": "string? — 附带文本（可选）"
}
```

### 响应类型

#### `acknowledge` — 确认收到

用于不需要用户交互的消息（session_start、session_end、notification、plan_update、post_tool_use）。

```json
{"action": "acknowledge", "text": null}
```

#### `allow` — 允许执行

用户点击 Allow 按钮后返回。hook 脚本应以 exit code 0 退出。

```json
{"action": "allow", "text": null}
```

#### `deny` — 拒绝执行

用户点击 Deny 按钮或权限请求超时后返回。hook 脚本应以 exit code 2 退出。

```json
{"action": "deny", "text": null}
```

#### `answer` — 文字回答

用户在输入框中输入文字并发送后返回。`text` 字段包含用户输入的文本。

```json
{"action": "answer", "text": "Use PostgreSQL, it's better for our scale."}
```

超时时返回空文本：

```json
{"action": "answer", "text": ""}
```

---

## Hook 脚本如何解析响应

hook 脚本收到响应后的处理逻辑：

```bash
# 1. 读取 JSON 响应
RESPONSE=$(echo "$MESSAGE" | socat - UNIX-CONNECT:/tmp/agentbar.sock)

# 2. 解析 action 字段
ACTION=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('action',''))")

# 3. 根据事件类型处理
#    权限请求：deny → exit 2，allow → exit 0
#    提问：提取 text 字段输出到 stdout
```

## 错误处理

### Socket 不存在

如果 `/tmp/agentbar.sock` 不存在（AgentBar 未运行），hook 脚本应：
- 对权限请求，默认返回 `{"action":"allow","text":null}` 并 exit 0（不阻塞 Agent）
- 对其他事件，静默退出

### JSON 解析失败

如果 AgentBar 收到无法解码的 JSON，会在控制台打印错误日志并关闭连接（不返回响应）。客户端可能因读取超时而断开。

### 超时

| 事件类型 | 超时时间 | 超时行为 |
|---------|---------|---------|
| `permission_request` / `pre_tool_use` | 300 秒（5 分钟） | 返回 `deny` |
| `ask_user` | 600 秒（10 分钟） | 返回 `answer("")` |
| 其他事件 | 无阻塞 | 立即返回 `acknowledge` |

### 会话 ID 不存在

如果收到的消息的 `sessionId` 在 SessionManager 中没有对应会话（例如未先发送 `session_start`），除 `session_start` 外的消息会被静默忽略（不创建会话，不崩溃）。

### 并发连接

SocketServer 的 `listen()` backlog 为 10。每个客户端连接在独立的 `DispatchQueue.global()` 线程中处理，支持多个 Agent 同时连接。但同一个 `sessionId` 的权限请求/提问是串行的（通过 `pendingResponses` 字典按 sessionId 键管理）。

---

## 快速测试

用 socat 快速验证协议：

```bash
# 最小可用消息
echo '{"sessionId":"t1","agentType":"claude_code","event":"session_start","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 预期响应
# {"action":"acknowledge"}
```
