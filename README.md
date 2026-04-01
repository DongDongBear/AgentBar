# AgentBar

Mac 刘海屏上的 AI Agent 统一监控面板。**在刘海区域直接输入文字回答 Agent 的提问**，无需切换窗口。

> 与 [Vibe Island](https://github.com/nicklama/vibe-island) 的核心差异：Vibe Island 只能显示状态和审批权限，AgentBar 支持**在刘海上直接输入文字回答 Agent 的提问**（`ask_user` 事件），真正实现双向交互。

<!-- 截图区域 -->
<details>
<summary>📸 截图</summary>

| 功能 | 截图 |
|------|------|
| 刘海区域浮动面板（收起） | `TODO: screenshot_collapsed.png` |
| 面板展开 — 会话列表 | `TODO: screenshot_expanded.png` |
| 权限审批对话框 | `TODO: screenshot_permission.png` |
| 文字输入回答 Agent 提问 | `TODO: screenshot_input.png` |
| Plan 预览 | `TODO: screenshot_plan.png` |

</details>

## 功能列表

### P0 — 核心功能

- **刘海区域浮动面板** — 在 Mac notch 区域显示可展开的监控面板，`NSPanel` 非激活窗口不抢焦点
- **多 Agent 监控** — 同时显示 Claude Code、Codex CLI、Gemini CLI 的运行状态
- **权限批准/拒绝** — Agent 请求权限时，面板上 Allow/Deny 按钮一键操作（5 分钟超时）
- **文字输入回答** — Agent 提问时，面板上直接输入文字回答，`Cmd+Enter` 发送（10 分钟超时）
- **零配置 Hook** — 启动时自动安装 hook 到所有 Agent 的配置文件

### P1 — 增强功能

- **音效提醒** — 权限请求（Funk）、Agent 提问（Submarine）、任务完成（Glass）、通知（Pop）
- **Plan 预览** — Markdown 渲染 Agent 的执行计划（支持标题、列表、代码块）
- **工具历史** — 显示每个 Session 的工具使用记录

### P2 — 规划中

- 终端跳转 — 点击 Session 跳转到对应终端窗口
- 多屏幕支持 — 检测外接显示器的刘海位置
- 自定义快捷键 — 全局快捷键打开/关闭面板
- 会话持久化 — 重启后恢复会话状态

## 技术架构

```
┌────────────────────────────────────────────────────────────┐
│                    macOS 刘海区域                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              NotchPanelView (NSPanel)                 │  │
│  │  ┌─────────────┐ ┌────────────┐ ┌────────────────┐  │  │
│  │  │SessionList  │ │Permission  │ │AgentInputField │  │  │
│  │  │View         │ │DialogView  │ │(文字输入)       │  │  │
│  │  └─────────────┘ └────────────┘ └────────────────┘  │  │
│  └────────────────────────┬─────────────────────────────┘  │
│                           │ SwiftUI @Published              │
│  ┌────────────────────────┴─────────────────────────────┐  │
│  │              SessionManager (单例)                     │  │
│  │         管理所有 AgentSession 的状态                    │  │
│  └────────────────────────┬─────────────────────────────┘  │
│                           │                                 │
│  ┌────────────────────────┴─────────────────────────────┐  │
│  │              SocketServer (单例)                       │  │
│  │      Unix socket /tmp/agentbar.sock                   │  │
│  │      newline-delimited JSON 协议                      │  │
│  └────────────┬───────────┬───────────┬─────────────────┘  │
│               │           │           │                     │
└───────────────┼───────────┼───────────┼─────────────────────┘
                │           │           │
     ┌──────────┴──┐ ┌─────┴─────┐ ┌──┴──────────┐
     │ Claude Code │ │ Codex CLI │ │ Gemini CLI  │
     │ Hook        │ │ Hook      │ │ Hook        │
     └─────────────┘ └───────────┘ └─────────────┘
```

## 通信流程

```
Agent (Claude Code / Codex / Gemini)
  │
  │ 触发 hook（如 PreToolUse）
  │
  ▼
Hook 脚本 (~/.agentbar/agentbar-hook.sh)
  │
  │ 构造 JSON，通过 socat/nc/python3 发送
  │
  ▼
Unix Socket (/tmp/agentbar.sock)
  │
  │ SocketServer 接收，JSON 解码
  │
  ▼
SessionManager (主线程更新)
  │
  │ @Published 属性变更
  │
  ▼
SwiftUI Views (自动刷新)
  │
  │ 用户点击 Allow/Deny 或输入文字
  │
  ▼
SocketServer.sendResponse()
  │
  │ 信号量唤醒，JSON 编码发回
  │
  ▼
Hook 脚本读取响应
  │
  │ 返回 exit code 或 stdout
  │
  ▼
Agent 继续执行
```

## 依赖要求

| 依赖 | 最低版本 | 说明 |
|------|---------|------|
| macOS | 13.0 (Ventura) | 支持 SwiftUI 的 NSPanel |
| Xcode | 15.0+ | 或独立 Swift toolchain |
| Swift | 5.9+ | 使用 Swift Package Manager |
| 外部依赖 | 无 | 纯 Swift，不依赖第三方库 |

运行时可选依赖（hook 脚本用于连接 socket）：
- `socat`（推荐，`brew install socat`）
- 或 `nc`（macOS 自带）
- 或 `python3`（macOS 自带，作为最后方案）

## 构建和运行

### 使用 Swift Package Manager

```bash
# 克隆项目
git clone <repo-url> AgentBar
cd AgentBar

# 构建 (Debug)
swift build

# 构建 (Release)
swift build -c release

# 运行
swift run AgentBar
# 或直接运行二进制
.build/release/AgentBar
```

### 使用 xcodebuild

```bash
# 生成 Xcode 项目（可选，方便用 Xcode IDE 调试）
swift package generate-xcodeproj

# 直接构建
xcodebuild -scheme AgentBar -configuration Release build
```

### 生成 .app 包

```bash
# 1. 构建 Release 版本
swift build -c release

# 2. 创建 .app 目录结构
mkdir -p AgentBar.app/Contents/MacOS
mkdir -p AgentBar.app/Contents/Resources

# 3. 复制文件
cp .build/release/AgentBar AgentBar.app/Contents/MacOS/
cp Sources/AgentBar/Info.plist AgentBar.app/Contents/

# 4. 运行
open AgentBar.app

# 或者拷贝到 /Applications
cp -r AgentBar.app /Applications/
```

### 启动后的行为

1. 在状态栏显示一个 CPU 图标（右键菜单可控制面板显示和重装 Hook）
2. 在刘海区域显示浮动面板（可收起/展开）
3. 自动安装 hook 脚本到 `~/.agentbar/agentbar-hook.sh`
4. 自动配置 `~/.claude/settings.json`、`~/.codex/hooks.json`、`~/.gemini/settings.json`
5. 启动 Unix socket server 在 `/tmp/agentbar.sock` 监听

然后正常使用 Claude Code / Codex CLI / Gemini CLI，AgentBar 会自动接收事件并在面板上显示。

## 项目目录结构

```
AgentBar/
├── Package.swift                    # SPM 包定义，macOS 13+, Swift 5.9+
├── README.md                        # 本文件
├── CLAUDE.md                        # Claude Code Agent 开发指引
├── docs/
│   ├── ARCHITECTURE.md              # 详细技术架构
│   ├── PROTOCOL.md                  # 通信协议规范
│   └── TESTING.md                   # 测试指南
├── Scripts/
│   └── agentbar-hook.sh             # Hook 脚本独立备份
└── Sources/AgentBar/
    ├── AgentBarApp.swift             # @main SwiftUI App 入口，创建 AppDelegate
    ├── AppDelegate.swift             # NSApplicationDelegate：状态栏、NSPanel、服务启动
    ├── Info.plist                    # Bundle 元数据（LSUIElement=true 隐藏 Dock 图标）
    ├── Models/
    │   ├── AgentType.swift           # Agent 类型枚举：claudeCode/codexCLI/geminiCLI
    │   ├── AgentSession.swift        # 会话模型 + PermissionRequest/UserQuestion/ToolEvent
    │   └── AgentMessage.swift        # Socket 消息结构：AgentMessage/AgentResponse
    ├── Services/
    │   ├── SocketServer.swift        # Unix socket 服务器，newline-delimited JSON
    │   ├── SessionManager.swift      # 会话生命周期管理（单例，@Published）
    │   ├── HookInstaller.swift       # 自动安装 hook 脚本和 Agent 配置
    │   └── SoundManager.swift        # 系统音效播放
    ├── Views/
    │   ├── NotchPanelView.swift      # 刘海面板主视图（自定义 NotchShape）
    │   ├── SessionListView.swift     # 会话列表和行视图
    │   ├── AgentInputField.swift     # 多行文字输入框（Cmd+Enter 发送）
    │   ├── PermissionDialogView.swift # 权限审批对话框（Allow/Deny）
    │   └── PlanViewerView.swift      # Markdown 计划渲染（可展开/收起）
    ├── Utils/
    │   ├── Constants.swift           # 全局常量（socket 路径、超时时间、面板尺寸）
    │   └── Color+Hex.swift           # Color 从 hex 字符串初始化扩展
    └── Resources/
        └── .gitkeep
```

## 开发指南

### 添加新 Agent 支持

1. **定义类型** — 在 `AgentType.swift` 的 `AgentType` 枚举中添加新 case：

```swift
case newAgent = "new_agent"
```

2. **补充属性** — 在各 `switch` 中添加 `displayName`、`iconName`、`accentColorHex`、`hookConfigPath`。

3. **安装 Hook** — 在 `HookInstaller.swift` 的 `installConfig(for:)` 中添加新的安装方法，参照 `installClaudeCodeHooks()` 实现。

4. 完成。Hook 脚本不需要修改（第一个参数传新的 agent type 即可）。

### 添加新 View

1. 在 `Sources/AgentBar/Views/` 下创建新的 SwiftUI View 文件。
2. 在 `NotchPanelView.swift` 或 `SessionListView.swift` 中引用新 View。
3. 如需新数据，在 `AgentSession` 中添加 `@Published` 属性，在 `SessionManager` 中添加更新方法。

### 添加新的消息事件类型

1. 在 `AgentMessage.EventType` 中添加新 case。
2. 在 `MessagePayload` 中添加所需字段。
3. 在 `SocketServer.processMessage()` 的 `switch` 中添加处理逻辑。
4. 在 hook 脚本中添加对应的事件转发。

## 测试方法

无需真实 Agent，用 `socat` 或 `nc` 手动连接 socket 发送 JSON 即可测试：

```bash
# 启动会话
echo '{"sessionId":"test-001","agentType":"claude_code","event":"session_start","workingDirectory":"/tmp/test","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 发送权限请求（AgentBar 会弹出审批对话框，点击后返回响应）
echo '{"sessionId":"test-001","agentType":"claude_code","event":"permission_request","workingDirectory":"/tmp/test","payload":{"tool":"Bash","description":"Run: rm -rf /tmp/old","parameters":{"command":"rm -rf /tmp/old"}}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 发送提问（AgentBar 会显示输入框，输入后返回响应）
echo '{"sessionId":"test-001","agentType":"claude_code","event":"ask_user","workingDirectory":"/tmp/test","payload":{"question":"Which database should I use?"}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 结束会话
echo '{"sessionId":"test-001","agentType":"claude_code","event":"session_end","workingDirectory":"/tmp/test","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock
```

如果没有 `socat`，用 `nc`：

```bash
echo '{"sessionId":"test-001","agentType":"claude_code","event":"session_start","workingDirectory":"/tmp/test","payload":{}}' | nc -U /tmp/agentbar.sock
```

更多测试消息模板见 [docs/TESTING.md](docs/TESTING.md)。

## 已知问题和 TODO

- [ ] Hook 安装会覆盖 Agent 配置文件中已有的 hook（应改为合并）
- [ ] 多屏幕时面板可能定位不准
- [ ] 没有全局快捷键打开/关闭面板
- [ ] 会话状态不持久化，重启后丢失
- [ ] hook 脚本的 JSON 构造不够健壮（特殊字符可能导致解析失败）
- [ ] 缺少自动化单元测试
- [ ] `socat` 不是 macOS 默认安装的，应考虑纯 Swift 客户端或内嵌 Python fallback

## License

MIT License

Copyright (c) 2024 AgentBar Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
