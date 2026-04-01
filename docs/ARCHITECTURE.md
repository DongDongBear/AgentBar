# AgentBar 技术架构

## 整体架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                         macOS 系统层                                 │
│  ┌──────────────────────┐  ┌──────────────────────────────────────┐ │
│  │   NSStatusBar 图标    │  │   NSPanel (刘海区域浮动面板)          │ │
│  │   右键菜单控制        │  │   level: .statusBar                  │ │
│  │   - Show Panel       │  │   styleMask: nonactivatingPanel      │ │
│  │   - Reinstall Hooks  │  │   collectionBehavior: canJoinAllSpaces│ │
│  │   - Quit             │  │                                      │ │
│  └──────────────────────┘  │  ┌────────────────────────────────┐  │ │
│                             │  │     视图层 (SwiftUI Views)      │  │ │
│                             │  │  NotchPanelView                │  │ │
│                             │  │  ├── SessionListView           │  │ │
│                             │  │  ├── PermissionDialogView      │  │ │
│                             │  │  ├── AgentInputField           │  │ │
│                             │  │  └── PlanViewerView            │  │ │
│                             │  └──────────────┬─────────────────┘  │ │
│                             └─────────────────┼────────────────────┘ │
│                                               │ @EnvironmentObject   │
│  ┌────────────────────────────────────────────┴──────────────────┐  │
│  │                     服务层 (Services)                          │  │
│  │  ┌──────────────────────────────────────────────────────────┐ │  │
│  │  │  SessionManager (单例, ObservableObject, @Published)      │ │  │
│  │  │  管理 [AgentSession] 数组                                 │ │  │
│  │  │  会话生命周期 / 权限处理 / 提问处理 / 状态更新             │ │  │
│  │  └──────────────────────────┬───────────────────────────────┘ │  │
│  │                             │ sendResponse()                   │  │
│  │  ┌──────────────────────────┴───────────────────────────────┐ │  │
│  │  │  SocketServer (单例, 后台线程)                             │ │  │
│  │  │  Unix socket /tmp/agentbar.sock                          │ │  │
│  │  │  accept 循环 -> handleClient -> processMessage           │ │  │
│  │  │  信号量阻塞等待用户响应 (权限/提问)                       │ │  │
│  │  └──────────────────────────┬───────────────────────────────┘ │  │
│  │                             │                                  │  │
│  │  ┌──────────────┐ ┌────────┴───────┐                          │  │
│  │  │HookInstaller │ │ SoundManager   │                          │  │
│  │  │安装 hook 脚本 │ │ 播放系统音效    │                          │  │
│  │  └──────────────┘ └────────────────┘                          │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                     模型层 (Models)                            │  │
│  │  AgentType     AgentSession     AgentMessage / AgentResponse  │  │
│  │  (枚举)        (ObservableObject) (Codable 结构体)             │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                     入口层 (Entry)                             │  │
│  │  AgentBarApp.swift (@main) -> AppDelegate                     │  │
│  │  NSApp.setActivationPolicy(.accessory) 隐藏 Dock 图标         │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
└──────────────────────────────┬───────────────────────────────────────┘
                               │ Unix domain socket
                               │ /tmp/agentbar.sock
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
┌────────┴────────┐  ┌────────┴────────┐  ┌────────┴────────┐
│   Claude Code   │  │   Codex CLI     │  │   Gemini CLI    │
│   Hook 脚本      │  │   Hook 脚本      │  │   Hook 脚本      │
│   ~/.claude/    │  │   ~/.codex/     │  │   ~/.gemini/    │
│   settings.json │  │   hooks.json    │  │   settings.json │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## 5 层架构说明

### 1. 入口层（Entry Layer）

| 文件 | 职责 |
|------|------|
| `AgentBarApp.swift` | `@main` SwiftUI App 入口，通过 `@NSApplicationDelegateAdaptor` 桥接到 AppDelegate |
| `AppDelegate.swift` | `NSApplicationDelegate`，负责初始化所有子系统 |

AppDelegate 在 `applicationDidFinishLaunching` 中完成三件事：
1. `setupStatusBarItem()` — 创建状态栏图标和右键菜单
2. `setupNotchPanel()` — 创建 NSPanel 浮动面板
3. `startServices()` — 启动 SocketServer、安装 Hooks、注册事件监听

### 2. 服务层（Service Layer）

| 服务 | 类型 | 线程 | 职责 |
|------|------|------|------|
| `SocketServer` | 单例 (`static let shared`) | 后台 DispatchQueue | 监听 Unix socket，接收/解析/转发消息，管理响应回调 |
| `SessionManager` | 单例 (`static let shared`) | MainActor (主线程) | 管理 `[AgentSession]` 数组，驱动 UI 更新 |
| `HookInstaller` | 实例 | 主线程 | 安装 hook 脚本到 `~/.agentbar/`，配置各 Agent 的设置文件 |
| `SoundManager` | 单例 (`static let shared`) | 主线程 | 根据事件类型播放系统音效 |

### 3. 模型层（Model Layer）

| 模型 | 说明 |
|------|------|
| `AgentType` | 枚举，定义支持的 Agent 类型及其元数据（名称、图标、颜色、配置路径） |
| `AgentSession` | `ObservableObject` 类，表示一个活跃的 Agent 会话，含 `@Published` 状态属性 |
| `SessionStatus` | 枚举：running / waitingForPermission / waitingForInput / idle / completed / error |
| `PermissionRequest` | 结构体，权限请求详情（工具名、描述、参数） |
| `UserQuestion` | 结构体，Agent 提问详情 |
| `ToolEvent` | 结构体，工具使用记录 |
| `AgentMessage` | 入站消息结构体（从 hook 脚本发来） |
| `AgentResponse` | 出站响应结构体（发回 hook 脚本） |

### 4. 视图层（View Layer）

| 视图 | 职责 |
|------|------|
| `NotchPanelView` | 主面板视图，自定义刘海形状（`NotchShape`），管理展开/收起状态 |
| `SessionListView` | 显示所有活跃会话列表，每行展示 Agent 类型、状态、工作目录 |
| `PermissionDialogView` | 权限审批 UI，显示工具名和描述，提供 Allow/Deny 按钮 |
| `AgentInputField` | 多行文字输入框，`Cmd+Enter` 发送回答 |
| `PlanViewerView` | Markdown 渲染 Agent 执行计划，支持展开/收起 |

视图通过 `@EnvironmentObject` 获取 `SessionManager`，数据变更自动刷新。

### 5. 脚本层（Script Layer）

| 文件 | 职责 |
|------|------|
| `~/.agentbar/agentbar-hook.sh` | 共享 hook 脚本，被所有 Agent 调用。接收 agent_type 和 event_type 参数，构造 JSON 发送到 socket |
| `~/.claude/settings.json` | Claude Code hook 配置（PreToolUse/PostToolUse/Notification） |
| `~/.codex/hooks.json` | Codex CLI hook 配置 |
| `~/.gemini/settings.json` | Gemini CLI hook 配置 |

hook 脚本优先使用 `socat`，fallback 到 `nc`，再 fallback 到 `python3`。

## 模块依赖关系

```
AgentBarApp
  └── AppDelegate
        ├── SessionManager ──── AgentSession, AgentType, PermissionRequest, UserQuestion, ToolEvent
        │     └── SocketServer.sendResponse()
        ├── SocketServer ────── AgentMessage, AgentResponse, SessionManager
        ├── HookInstaller ───── Constants, AgentType
        └── SoundManager

Views (NotchPanelView, SessionListView, PermissionDialogView, AgentInputField, PlanViewerView)
  └── SessionManager (via @EnvironmentObject)
        └── AgentSession (via @Published sessions)
```

关键依赖方向：
- **Views** 依赖 **SessionManager**（单向，通过 `@EnvironmentObject`）
- **SocketServer** 依赖 **SessionManager**（调用其方法更新会话状态）
- **SessionManager** 依赖 **SocketServer**（调用 `sendResponse` 发回用户响应）
- 两个服务之间存在双向依赖，通过 `static let shared` 单例解耦

## 通信流程

完整的一次交互（以权限请求为例）：

```
1. Claude Code 执行到需要权限的工具
   │
2. 触发 PreToolUse hook
   │
3. 调用 ~/.agentbar/agentbar-hook.sh claude_code pre_tool_use
   │  hook 脚本从 stdin 读取 payload JSON
   │
4. hook 脚本构造完整 AgentMessage JSON
   │  用 socat/nc/python3 发送到 /tmp/agentbar.sock
   │
5. SocketServer.handleClient() 接收数据
   │  JSONDecoder 解码为 AgentMessage
   │
6. SocketServer.processMessage() 处理消息
   │  case .preToolUse / .permissionRequest:
   │  ├── 创建 PermissionRequest 对象
   │  ├── DispatchQueue.main.async { sessionManager.requestPermission() }
   │  ├── registerResponseHandler() 注册回调
   │  └── semaphore.wait(timeout: 300秒)  ← 当前线程阻塞
   │
7. SessionManager.requestPermission()（主线程）
   │  ├── session.pendingPermission = request
   │  ├── session.status = .waitingForPermission
   │  └── @Published 触发 UI 更新
   │
8. SwiftUI Views 自动刷新
   │  ├── SessionListView 显示 "等待权限" 状态
   │  └── PermissionDialogView 显示 Allow/Deny 按钮
   │
9. 用户点击 Allow（或 Deny）
   │
10. SessionManager.respondToPermission()
    │  ├── session.pendingPermission = nil
    │  ├── session.status = .running
    │  └── SocketServer.shared.sendResponse(sessionId, .allow())
    │
11. SocketServer.sendResponse()
    │  ├── 从 pendingResponses 取出回调
    │  └── 调用 handler(response) → semaphore.signal()
    │
12. processMessage() 中 semaphore 被唤醒
    │  返回 AgentResponse
    │
13. handleClient() 将 AgentResponse 编码为 JSON
    │  写回 client socket
    │
14. hook 脚本从 socket 读到响应
    │  ├── 解析 action 字段
    │  ├── allow → exit 0
    │  └── deny → exit 2
    │
15. Claude Code 读取 hook exit code
    └── 继续执行或取消操作
```

## NSPanel 配置和焦点管理策略

### NSPanel 配置

```swift
let panel = NSPanel(
    contentRect: rect,
    styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
    backing: .buffered,
    defer: false
)

panel.isFloatingPanel = true           // 浮动在所有窗口之上
panel.level = .statusBar               // 与状态栏同级
panel.collectionBehavior = [
    .canJoinAllSpaces,                 // 在所有桌面空间显示
    .fullScreenAuxiliary               // 全屏应用中也可见
]
panel.isOpaque = false                 // 支持透明背景
panel.backgroundColor = .clear         // 透明背景
panel.becomesKeyOnlyIfNeeded = true    // 只在需要时获取键盘焦点
```

### 焦点管理策略

核心挑战：面板需要在不抢夺当前应用焦点的前提下，允许用户在输入框中打字。

解决方案：
1. **`NSApp.setActivationPolicy(.accessory)`** — 应用不出现在 Dock 中，不自动成为前台应用
2. **`.nonactivatingPanel`** — 点击面板不会激活 AgentBar 应用，当前前台应用保持焦点
3. **`becomesKeyOnlyIfNeeded = true`** — 只有当面板中有需要键盘输入的控件（如 TextField）时，面板才会临时成为 key window
4. **`.statusBar` level** — 面板浮动在普通窗口之上，但不遮挡系统菜单

这意味着：
- 正常展示会话列表时，面板不影响其他应用
- 当 Agent 提问需要输入文字时，点击输入框，面板临时获取键盘焦点
- 发送回答后，焦点自然回到之前的应用

## 线程模型

```
┌─────────────────────────────────────────────────────────┐
│  主线程 (Main Thread / MainActor)                        │
│                                                          │
│  - AppDelegate 初始化                                    │
│  - SessionManager 的所有方法                              │
│  - SwiftUI 视图更新                                      │
│  - SoundManager 播放                                     │
│  - HookInstaller 安装                                    │
└──────────────────────────────┬──────────────────────────┘
                               │ DispatchQueue.main.async
┌──────────────────────────────┴──────────────────────────┐
│  SocketServer 后台队列                                    │
│  DispatchQueue(label: "com.agentbar.socketserver")       │
│                                                          │
│  - accept() 循环（阻塞等待新连接）                        │
│  - 每个 client 在 DispatchQueue.global() 处理             │
│  - processMessage() 在 global queue 执行                 │
│  - 权限/提问请求用 DispatchSemaphore 阻塞等待用户响应    │
│  - DispatchQueue.main.async 将状态更新分发到主线程        │
└─────────────────────────────────────────────────────────┘
```

关键线程规则：
- `@Published` 属性只能在主线程修改（否则 SwiftUI 崩溃或警告）
- `SocketServer` 的 accept 和 client 处理在后台线程
- 用 `DispatchSemaphore` 阻塞后台线程等待用户响应，不阻塞主线程
- 用 `DispatchQueue.main.async` 桥接后台线程到主线程

## 状态管理

### SessionManager — 全局状态中心

`SessionManager` 是 `ObservableObject` 单例，持有 `@Published var sessions: [AgentSession]`。

```
SessionManager.shared
  └── @Published sessions: [AgentSession]
        ├── session.status           → SessionListView 行状态颜色
        ├── session.pendingPermission → PermissionDialogView 显示/隐藏
        ├── session.pendingQuestion   → AgentInputField 显示/隐藏
        ├── session.plan              → PlanViewerView 内容
        ├── session.currentTask       → SessionListView 当前任务文本
        └── session.toolHistory       → 工具使用历史列表
```

### 状态流转

```
session_start → status: running
                  │
    ┌─────────────┼─────────────┐
    │             │             │
permission    ask_user     notification
request         │             │
    │             │         更新 currentTask
    ▼             ▼
waitingFor    waitingFor
Permission    Input
    │             │
用户 Allow/   用户输入
Deny          文字
    │             │
    ▼             ▼
  running       running
                  │
              session_end → status: completed → 5秒后移除
```

### 数据不持久化

当前版本不做持久化。应用重启后所有会话状态丢失。这是有意为之——Agent 会话本身是临时的，重启后 Agent 会重新连接并创建新会话。
