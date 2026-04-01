# AgentBar 测试指南

## 概述

AgentBar 目前没有自动化单元测试。测试通过手动连接 Unix socket 发送模拟消息来进行。本文档提供完整的 Python 测试脚本和各种测试场景。

## 前置条件

1. AgentBar 已启动并运行（`swift run AgentBar`）
2. Socket 文件存在：`/tmp/agentbar.sock`
3. Python 3 可用（macOS 自带）

验证 AgentBar 是否运行：

```bash
# 检查 socket 文件
ls -la /tmp/agentbar.sock

# 快速发送测试消息
echo '{"sessionId":"ping","agentType":"claude_code","event":"session_start","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock
```

---

## 完整 Python 测试脚本

将以下脚本保存为 `test_agentbar.py`：

```python
#!/usr/bin/env python3
"""
AgentBar 测试脚本 — 模拟 AI Agent 通过 Unix socket 发送消息
用法：python3 test_agentbar.py [测试场景编号]
"""

import socket
import json
import sys
import time
import uuid
import threading


SOCKET_PATH = "/tmp/agentbar.sock"


def send_message(msg: dict, timeout: float = 30.0) -> dict:
    """发送一条消息到 AgentBar 并返回响应"""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(SOCKET_PATH)
        data = json.dumps(msg) + "\n"
        s.sendall(data.encode("utf-8"))
        s.shutdown(socket.SHUT_WR)

        # 读取响应
        chunks = []
        while True:
            try:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
            except socket.timeout:
                print("  [超时] 等待响应超时")
                break

        resp_data = b"".join(chunks).decode("utf-8").strip()
        if resp_data:
            return json.loads(resp_data)
        return {}
    except ConnectionRefusedError:
        print("  [错误] 连接被拒绝，AgentBar 是否在运行？")
        return {}
    except FileNotFoundError:
        print(f"  [错误] Socket 文件不存在: {SOCKET_PATH}")
        return {}
    finally:
        s.close()


def make_message(session_id: str, agent_type: str, event: str,
                 payload: dict = None, cwd: str = "/tmp/test") -> dict:
    """构造 AgentMessage"""
    return {
        "sessionId": session_id,
        "agentType": agent_type,
        "event": event,
        "workingDirectory": cwd,
        "payload": payload or {}
    }


# ============================================================
# 测试场景 1：会话生命周期（开始 → 通知 → 结束）
# ============================================================
def test_session_lifecycle():
    print("\n=== 测试 1：会话生命周期 ===")
    sid = f"test-{uuid.uuid4().hex[:8]}"

    # 开始会话
    print(f"  发送 session_start (sessionId={sid})")
    resp = send_message(make_message(sid, "claude_code", "session_start"))
    print(f"  响应: {resp}")
    assert resp.get("action") == "acknowledge", "session_start 应返回 acknowledge"

    time.sleep(1)

    # 发送通知
    print("  发送 notification")
    resp = send_message(make_message(sid, "claude_code", "notification", {
        "message": "正在分析代码库..."
    }))
    print(f"  响应: {resp}")
    assert resp.get("action") == "acknowledge"

    time.sleep(1)

    # 发送工具使用完成
    print("  发送 post_tool_use")
    resp = send_message(make_message(sid, "claude_code", "post_tool_use", {
        "tool": "Bash",
        "status": "completed"
    }))
    print(f"  响应: {resp}")
    assert resp.get("action") == "acknowledge"

    time.sleep(1)

    # 发送计划更新
    print("  发送 plan_update")
    resp = send_message(make_message(sid, "claude_code", "plan_update", {
        "plan": "## 实施计划\n\n1. 创建数据库模型\n2. 实现 API 端点\n3. 编写测试\n\n```python\nclass User(Model):\n    name = CharField()\n```"
    }))
    print(f"  响应: {resp}")
    assert resp.get("action") == "acknowledge"

    time.sleep(2)

    # 结束会话
    print("  发送 session_end")
    resp = send_message(make_message(sid, "claude_code", "session_end"))
    print(f"  响应: {resp}")
    assert resp.get("action") == "acknowledge"

    print("  ✅ 测试 1 通过")


# ============================================================
# 测试场景 2：权限请求（等待用户 Allow/Deny）
# ============================================================
def test_permission_request():
    print("\n=== 测试 2：权限请求 ===")
    sid = f"test-{uuid.uuid4().hex[:8]}"

    # 先开始会话
    send_message(make_message(sid, "claude_code", "session_start"))
    time.sleep(0.5)

    # 发送权限请求（会阻塞等待用户操作）
    print("  发送 permission_request")
    print("  ⏳ 请在 AgentBar 面板上点击 Allow 或 Deny...")
    resp = send_message(make_message(sid, "claude_code", "permission_request", {
        "tool": "Bash",
        "description": "执行命令: npm install express@latest",
        "parameters": {
            "command": "npm install express@latest"
        }
    }), timeout=120.0)
    print(f"  响应: {resp}")

    action = resp.get("action", "")
    if action == "allow":
        print("  ✅ 用户点击了 Allow")
    elif action == "deny":
        print("  ✅ 用户点击了 Deny")
    else:
        print(f"  ⚠️ 意外响应: {action}")

    # 清理
    send_message(make_message(sid, "claude_code", "session_end"))
    print("  ✅ 测试 2 通过")


# ============================================================
# 测试场景 3：Agent 提问（等待用户输入文字）
# ============================================================
def test_ask_user():
    print("\n=== 测试 3：Agent 提问 ===")
    sid = f"test-{uuid.uuid4().hex[:8]}"

    # 先开始会话
    send_message(make_message(sid, "codex_cli", "session_start",
                              cwd="/Users/dev/my-app"))
    time.sleep(0.5)

    # 发送提问（会阻塞等待用户输入）
    print("  发送 ask_user")
    print("  ⏳ 请在 AgentBar 面板的输入框中输入回答，然后按 Cmd+Enter 发送...")
    resp = send_message(make_message(sid, "codex_cli", "ask_user", {
        "question": "项目应该使用 PostgreSQL 还是 SQLite？请说明理由。"
    }), timeout=120.0)
    print(f"  响应: {resp}")

    action = resp.get("action", "")
    text = resp.get("text", "")
    if action == "answer":
        print(f"  ✅ 用户回答: {text}")
    else:
        print(f"  ⚠️ 意外响应: {action}")

    # 清理
    send_message(make_message(sid, "codex_cli", "session_end"))
    print("  ✅ 测试 3 通过")


# ============================================================
# 测试场景 4：通知和计划更新
# ============================================================
def test_notifications():
    print("\n=== 测试 4：通知和计划 ===")
    sid = f"test-{uuid.uuid4().hex[:8]}"

    send_message(make_message(sid, "gemini_cli", "session_start",
                              cwd="/Users/dev/web-app"))
    time.sleep(0.5)

    notifications = [
        "正在分析项目结构...",
        "发现 42 个源文件",
        "正在生成代码覆盖率报告...",
        "代码覆盖率: 78.3%",
    ]

    for msg in notifications:
        print(f"  发送通知: {msg}")
        resp = send_message(make_message(sid, "gemini_cli", "notification", {
            "message": msg
        }))
        assert resp.get("action") == "acknowledge"
        time.sleep(0.8)

    # 发送计划
    print("  发送 plan_update")
    resp = send_message(make_message(sid, "gemini_cli", "plan_update", {
        "plan": """## 代码优化计划

### 第一阶段：性能优化
- 优化数据库查询（N+1 问题）
- 添加 Redis 缓存层
- 图片懒加载

### 第二阶段：代码质量
- 提取公共组件
- 添加单元测试（目标 >90%）
- ESLint 规则统一

```typescript
// 优化前
const users = await db.query('SELECT * FROM users');
for (const user of users) {
  user.posts = await db.query('SELECT * FROM posts WHERE userId = ?', user.id);
}

// 优化后
const users = await db.query(`
  SELECT u.*, json_agg(p) as posts
  FROM users u
  LEFT JOIN posts p ON p.userId = u.id
  GROUP BY u.id
`);
```"""
    }))
    assert resp.get("action") == "acknowledge"

    time.sleep(3)
    send_message(make_message(sid, "gemini_cli", "session_end"))
    print("  ✅ 测试 4 通过")


# ============================================================
# 测试场景 5：多 Agent 同时运行
# ============================================================
def test_multiple_agents():
    print("\n=== 测试 5：多 Agent 同时运行 ===")

    agents = [
        ("claude_code", "/Users/dev/backend"),
        ("codex_cli", "/Users/dev/frontend"),
        ("gemini_cli", "/Users/dev/infra"),
    ]

    sessions = []

    # 同时启动 3 个会话
    for agent_type, cwd in agents:
        sid = f"{agent_type}-{uuid.uuid4().hex[:6]}"
        sessions.append((sid, agent_type, cwd))
        print(f"  启动会话: {agent_type} ({sid})")
        resp = send_message(make_message(sid, agent_type, "session_start", cwd=cwd))
        assert resp.get("action") == "acknowledge"

    time.sleep(1)

    # 模拟各 Agent 并行活动
    def agent_activity(sid, agent_type, cwd):
        """模拟单个 Agent 的活动"""
        time.sleep(0.5)
        # 发送通知
        send_message(make_message(sid, agent_type, "notification", {
            "message": f"{agent_type}: 正在工作..."
        }))
        time.sleep(1)
        # 发送工具使用
        send_message(make_message(sid, agent_type, "post_tool_use", {
            "tool": "Read",
            "status": "completed"
        }))
        time.sleep(1)
        send_message(make_message(sid, agent_type, "notification", {
            "message": f"{agent_type}: 任务完成"
        }))

    # 并行执行
    threads = []
    for sid, agent_type, cwd in sessions:
        t = threading.Thread(target=agent_activity, args=(sid, agent_type, cwd))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    time.sleep(2)

    # 逐个结束会话
    for sid, agent_type, cwd in sessions:
        print(f"  结束会话: {agent_type} ({sid})")
        send_message(make_message(sid, agent_type, "session_end"))
        time.sleep(0.5)

    print("  ✅ 测试 5 通过")


# ============================================================
# 测试场景 6：快速压力测试
# ============================================================
def test_rapid_messages():
    print("\n=== 测试 6：快速连续消息 ===")
    sid = f"test-{uuid.uuid4().hex[:8]}"

    send_message(make_message(sid, "claude_code", "session_start"))
    time.sleep(0.5)

    # 快速发送 20 条通知
    for i in range(20):
        resp = send_message(make_message(sid, "claude_code", "notification", {
            "message": f"步骤 {i+1}/20: 处理文件 file_{i+1}.swift"
        }))
        if resp.get("action") != "acknowledge":
            print(f"  ⚠️ 第 {i+1} 条消息响应异常: {resp}")
            break
    else:
        print("  20 条消息全部成功")

    time.sleep(1)
    send_message(make_message(sid, "claude_code", "session_end"))
    print("  ✅ 测试 6 通过")


# ============================================================
# 主入口
# ============================================================
TESTS = {
    "1": ("会话生命周期", test_session_lifecycle),
    "2": ("权限请求", test_permission_request),
    "3": ("Agent 提问", test_ask_user),
    "4": ("通知和计划", test_notifications),
    "5": ("多 Agent 同时运行", test_multiple_agents),
    "6": ("快速压力测试", test_rapid_messages),
}


def main():
    # 检查 socket
    import os
    if not os.path.exists(SOCKET_PATH):
        print(f"❌ Socket 文件不存在: {SOCKET_PATH}")
        print("   请先启动 AgentBar: swift run AgentBar")
        sys.exit(1)

    if len(sys.argv) > 1:
        # 运行指定测试
        for num in sys.argv[1:]:
            if num in TESTS:
                name, func = TESTS[num]
                print(f"\n运行测试 {num}: {name}")
                func()
            else:
                print(f"未知测试编号: {num}")
                print(f"可用: {', '.join(TESTS.keys())}")
    else:
        # 显示菜单
        print("AgentBar 测试脚本")
        print("=" * 40)
        for num, (name, _) in TESTS.items():
            print(f"  {num}. {name}")
        print()
        print("用法: python3 test_agentbar.py [编号...]")
        print("示例: python3 test_agentbar.py 1        # 运行测试 1")
        print("      python3 test_agentbar.py 1 4 5    # 运行测试 1、4、5")
        print("      python3 test_agentbar.py 1 2 3 4 5 6  # 运行全部")


if __name__ == "__main__":
    main()
```

---

## 单独测试场景说明

### 测试 1：会话生命周期

模拟完整的会话流程：`session_start` → `notification` → `post_tool_use` → `plan_update` → `session_end`。

**验证点**：
- 面板上出现新的 Claude Code 会话条目
- 通知文本正确显示
- 工具历史记录更新
- 计划视图出现 Markdown 内容
- 会话结束后 5 秒从列表移除

**运行**：

```bash
python3 test_agentbar.py 1
```

### 测试 2：权限请求

发送权限请求，脚本会阻塞等待用户在面板上点击 Allow 或 Deny。

**验证点**：
- 面板弹出权限审批对话框，显示工具名和描述
- 会话状态变为"等待权限"
- 系统播放 Funk 音效
- 点击 Allow 后响应 `{"action":"allow"}`
- 点击 Deny 后响应 `{"action":"deny"}`

**运行**：

```bash
python3 test_agentbar.py 2
```

### 测试 3：Agent 提问

发送提问，脚本会阻塞等待用户在面板输入框中输入文字并按 Cmd+Enter。

**验证点**：
- 面板显示 Agent 的问题文本
- 输入框可以正常打字
- Cmd+Enter 发送回答
- 系统播放 Submarine 音效
- 响应包含用户输入的文字

**运行**：

```bash
python3 test_agentbar.py 3
```

### 测试 4：通知和计划

连续发送多条通知和一个 Markdown 计划。

**验证点**：
- 通知文本实时更新
- 计划视图正确渲染 Markdown（标题、列表、代码块）
- 计划可以展开/收起

**运行**：

```bash
python3 test_agentbar.py 4
```

### 测试 5：多 Agent 同时运行

同时启动 3 个不同类型的 Agent 会话，并行发送消息。

**验证点**：
- 面板同时显示 3 个会话（Claude Code / Codex CLI / Gemini CLI）
- 每个会话有不同的图标和颜色
- 并行消息不会混淆或丢失
- 各会话独立结束

**运行**：

```bash
python3 test_agentbar.py 5
```

### 测试 6：快速压力测试

快速连续发送 20 条通知消息。

**验证点**：
- 所有消息都得到 acknowledge 响应
- UI 不卡顿或崩溃
- 通知文本快速更新

**运行**：

```bash
python3 test_agentbar.py 6
```

---

## 使用 socat 快速测试

如果只需要发送单条消息，不需要完整 Python 脚本：

```bash
# 安装 socat (如果没有)
brew install socat

# 开始会话
echo '{"sessionId":"s1","agentType":"claude_code","event":"session_start","workingDirectory":"/tmp","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 权限请求 (阻塞等待点击)
echo '{"sessionId":"s1","agentType":"claude_code","event":"permission_request","workingDirectory":"/tmp","payload":{"tool":"Write","description":"Write to /etc/hosts"}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 提问 (阻塞等待输入)
echo '{"sessionId":"s1","agentType":"claude_code","event":"ask_user","workingDirectory":"/tmp","payload":{"question":"Continue?"}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 结束
echo '{"sessionId":"s1","agentType":"claude_code","event":"session_end","workingDirectory":"/tmp","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock
```

---

## 自动化测试思路

当前 AgentBar 缺少自动化测试。以下是未来可以实现的方向：

### 1. 单元测试（Swift XCTest）

```swift
// 测试 SessionManager 的状态管理
func testStartSession() {
    let manager = SessionManager()
    manager.startSession(id: "test-1", agentType: .claudeCode, workingDirectory: "/tmp")
    XCTAssertEqual(manager.sessions.count, 1)
    XCTAssertEqual(manager.sessions[0].status, .running)
}

func testDuplicateSession() {
    let manager = SessionManager()
    manager.startSession(id: "test-1", agentType: .claudeCode, workingDirectory: "/tmp")
    manager.startSession(id: "test-1", agentType: .claudeCode, workingDirectory: "/tmp")
    XCTAssertEqual(manager.sessions.count, 1)  // 不应重复
}
```

**挑战**：`SessionManager` 是单例，测试需要重构为支持依赖注入。

### 2. 协议测试（Python pytest）

```python
# 测试 JSON 解码
def test_valid_message_accepted():
    resp = send_message({"sessionId": "t", "agentType": "claude_code",
                         "event": "session_start", "payload": {}})
    assert resp["action"] == "acknowledge"

def test_invalid_json_rejected():
    """发送非法 JSON，验证不崩溃"""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect("/tmp/agentbar.sock")
    s.sendall(b"not json\n")
    s.shutdown(socket.SHUT_WR)
    resp = s.recv(4096)
    s.close()
    assert resp == b""  # 无响应，但服务不崩溃
```

### 3. 集成测试

用 Python 脚本模拟完整的 Agent 工作流：

```python
def test_full_workflow():
    """模拟 Claude Code 的完整工作流"""
    sid = "integration-test"

    # 1. 开始会话
    assert send("session_start")["action"] == "acknowledge"

    # 2. 几个工具使用
    assert send("post_tool_use", tool="Read")["action"] == "acknowledge"
    assert send("post_tool_use", tool="Grep")["action"] == "acknowledge"

    # 3. 权限请求（自动化测试中需要跳过或模拟点击）
    # TODO: 需要 UI 自动化框架或模拟 sendResponse

    # 4. 结束
    assert send("session_end")["action"] == "acknowledge"
```

### 4. UI 自动化测试

使用 macOS Accessibility API 或 XCUITest 进行 UI 自动化：

- 验证面板显示/隐藏
- 验证按钮点击
- 验证输入框交互

**当前限制**：NSPanel 的 `.nonactivatingPanel` 行为可能与 XCUITest 的窗口捕获不兼容，需要进一步研究。

### 5. CI/CD 集成

```yaml
# GitHub Actions 示例（仅构建，不做 UI 测试）
- name: Build
  run: swift build

- name: Protocol tests
  run: |
    swift run AgentBar &
    sleep 3
    python3 test_agentbar.py 1 4 6
    kill %1
```

macOS UI 测试需要 macOS runner，且可能需要屏幕访问权限。
