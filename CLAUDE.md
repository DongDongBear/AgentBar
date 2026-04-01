# CLAUDE.md — AgentBar 开发指引

本文件面向在 Mac 上使用 Claude Code 进行 AgentBar 项目开发的 AI 助手和开发者。

## 项目架构概述

AgentBar 是一个纯 Swift macOS 应用，使用 SwiftUI + NSPanel 在 Mac 刘海（notch）区域显示浮动监控面板。它通过 Unix domain socket (`/tmp/agentbar.sock`) 接收来自 AI Agent（Claude Code、Codex CLI、Gemini CLI）的 hook 事件，并在面板上显示会话状态、审批权限请求、接收用户文字输入。没有任何第三方依赖，使用 Swift Package Manager 构建。

## 关键文件和职责

| 文件 | 职责 |
|------|------|
| `Package.swift` | SPM 包定义，macOS 13+，Swift 5.9+ |
| `Sources/AgentBar/AgentBarApp.swift` | `@main` 入口，SwiftUI App，创建 AppDelegate |
| `Sources/AgentBar/AppDelegate.swift` | `NSApplicationDelegate`：状态栏图标、NSPanel 创建和定位、服务启动、音效事件监听 |
| `Sources/AgentBar/Info.plist` | Bundle 元数据，`LSUIElement=true` 隐藏 Dock 图标 |
| `Sources/AgentBar/Models/AgentType.swift` | Agent 类型枚举（claude_code/codex_cli/gemini_cli），含显示名、图标、颜色、hook 配置路径 |
| `Sources/AgentBar/Models/AgentSession.swift` | 会话模型 `AgentSession`（ObservableObject），含状态、权限请求、提问、工具历史等 |
| `Sources/AgentBar/Models/AgentMessage.swift` | Socket 消息结构：`AgentMessage`（入站）、`AgentResponse`（出站）、事件类型枚举 |
| `Sources/AgentBar/Services/SocketServer.swift` | Unix socket 服务器（单例），后台线程 accept 连接，JSON 解码/编码，信号量阻塞等待用户响应 |
| `Sources/AgentBar/Services/SessionManager.swift` | 会话管理器（单例，ObservableObject），管理所有 `AgentSession` 的生命周期和状态 |
| `Sources/AgentBar/Services/HookInstaller.swift` | 自动安装 hook 脚本到 `~/.agentbar/`，配置各 Agent 的 settings/hooks.json |
| `Sources/AgentBar/Services/SoundManager.swift` | macOS 系统音效播放（Funk/Submarine/Glass/Pop） |
| `Sources/AgentBar/Views/NotchPanelView.swift` | 刘海面板主视图，自定义 NotchShape，收起/展开 |
| `Sources/AgentBar/Views/SessionListView.swift` | 会话列表和行视图 |
| `Sources/AgentBar/Views/AgentInputField.swift` | 多行文字输入框，Cmd+Enter 发送 |
| `Sources/AgentBar/Views/PermissionDialogView.swift` | 权限审批对话框（Allow/Deny） |
| `Sources/AgentBar/Views/PlanViewerView.swift` | Markdown 计划渲染（可展开/收起） |
| `Sources/AgentBar/Utils/Constants.swift` | 全局常量：socket 路径、超时时间、面板尺寸 |
| `Sources/AgentBar/Utils/Color+Hex.swift` | Color hex 字符串初始化扩展 |
| `Scripts/agentbar-hook.sh` | Hook 脚本独立备份（实际由 HookInstaller 动态生成安装） |

## 编译命令

```bash
# Debug 构建
swift build

# Release 构建
swift build -c release

# 运行
swift run AgentBar

# 直接运行编译产物
.build/release/AgentBar

# 用 xcodebuild 构建
xcodebuild -scheme AgentBar -configuration Release build
```

## 生成 .app 包

```bash
# 1. 构建 Release
swift build -c release

# 2. 创建 .app 目录结构
mkdir -p AgentBar.app/Contents/MacOS
mkdir -p AgentBar.app/Contents/Resources

# 3. 复制二进制和 Info.plist
cp .build/release/AgentBar AgentBar.app/Contents/MacOS/
cp Sources/AgentBar/Info.plist AgentBar.app/Contents/

# 4. 运行
open AgentBar.app

# 或复制到 Applications
cp -r AgentBar.app /Applications/
```

## 调试技巧

### 控制台日志

代码中使用 `print("[AgentBar] ...")` 输出日志，可以在终端直接看到：

```bash
# 直接终端运行，日志输出到 stdout
swift run AgentBar 2>&1

# 或用 Console.app 查看
# 打开 Console.app -> 搜索 "AgentBar"
```

### lldb 调试

```bash
# 附加到运行中的进程
lldb -n AgentBar

# 或从 lldb 启动
lldb .build/debug/AgentBar
(lldb) run

# 在 SocketServer 设断点
(lldb) b SocketServer.swift:183
(lldb) b processMessage

# 查看 SessionManager 状态
(lldb) po SessionManager.shared.sessions
```

### 常用调试 print

在关键位置临时添加 print 日志：

```swift
// SocketServer.swift handleClient() 中
print("[AgentBar] Received raw: \(String(data: data, encoding: .utf8) ?? "?")")

// SessionManager.swift 中
print("[AgentBar] Sessions count: \(sessions.count)")
print("[AgentBar] Session \(id) status: \(session.status)")
```

## 代码风格

### SwiftUI 视图命名

- 视图文件以 `View` 结尾：`SessionListView.swift`、`NotchPanelView.swift`
- 子视图提取为独立 struct，放在同一文件或新文件中
- 用 `@EnvironmentObject` 注入 `SessionManager`
- 模型用 `@Published` 属性驱动 UI 更新

### 文件组织

```
Sources/AgentBar/
├── AgentBarApp.swift        # @main 入口
├── AppDelegate.swift        # NSApplicationDelegate
├── Models/                  # 数据模型
├── Services/                # 后台服务（socket、会话管理、hook安装、音效）
├── Views/                   # SwiftUI 视图
├── Utils/                   # 工具和常量
└── Resources/               # 资源文件
```

### 其他约定

- 单例使用 `static let shared`
- 服务类标记 `final class`
- 模型中复杂类型遵循 `Identifiable`、`Codable`
- 使用 `// MARK: -` 分隔代码段
- 常量统一放在 `Constants.swift`

## 常见编译错误和修复

### 1. macOS API 版本问题

```
error: 'xxx' is only available in macOS 14 or newer
```

**修复**：检查 `Package.swift` 中 `.macOS(.v13)` 约束，使用条件编译或替代 API：

```swift
if #available(macOS 14, *) {
    // 新 API
} else {
    // 降级方案
}
```

### 2. import 缺失

```
error: cannot find 'NSPanel' in scope
```

**修复**：确保文件顶部有正确的 import：

```swift
import AppKit    // NSPanel, NSStatusBar, NSSound 等
import SwiftUI   // SwiftUI 视图
import Foundation // 基础类型
import Darwin    // 底层 socket API（如果用 #if canImport）
```

### 3. Socket API 编译错误

`SocketServer.swift` 使用底层 Darwin socket API，注意：
- `sockaddr_un` 的 `sun_path` 是固定长度 C 数组，需要 `withUnsafeMutablePointer` + `withMemoryRebound` 写入
- `bind`/`accept`/`listen` 等函数和 Swift 标准库同名函数冲突时，确保用正确的参数签名

### 4. @Published 在非 ObservableObject 中

```
error: @Published requires class to conform to ObservableObject
```

**修复**：确保类继承了 `ObservableObject` 或改用 `@Observable`（macOS 14+）。

### 5. 线程问题

```
warning: Publishing changes from background threads is not allowed
```

**修复**：所有 `@Published` 属性的修改必须在主线程：

```swift
DispatchQueue.main.async {
    sessionManager.updateSomething()
}
```

## 手动 Socket 测试命令

### 使用 socat

```bash
# 发送 session_start
echo '{"sessionId":"test-001","agentType":"claude_code","event":"session_start","workingDirectory":"/tmp/test","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 发送权限请求（会阻塞等待用户点击 Allow/Deny）
echo '{"sessionId":"test-001","agentType":"claude_code","event":"permission_request","workingDirectory":"/tmp/test","payload":{"tool":"Bash","description":"Run: rm -rf /tmp/old","parameters":{"command":"rm -rf /tmp/old"}}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 发送提问（会阻塞等待用户输入文字）
echo '{"sessionId":"test-001","agentType":"claude_code","event":"ask_user","workingDirectory":"/tmp/test","payload":{"question":"Which database should I use?"}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 发送通知
echo '{"sessionId":"test-001","agentType":"claude_code","event":"notification","workingDirectory":"/tmp/test","payload":{"message":"Compiling project..."}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock

# 结束会话
echo '{"sessionId":"test-001","agentType":"claude_code","event":"session_end","workingDirectory":"/tmp/test","payload":{}}' | socat - UNIX-CONNECT:/tmp/agentbar.sock
```

### 使用 Python 脚本

```bash
python3 -c "
import socket, json
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect('/tmp/agentbar.sock')
msg = json.dumps({'sessionId':'test-001','agentType':'claude_code','event':'session_start','workingDirectory':'/tmp/test','payload':{}})
s.sendall((msg + '\n').encode())
s.shutdown(socket.SHUT_WR)
resp = s.recv(4096)
print('Response:', resp.decode())
s.close()
"
```

## 迭代开发工作流

### 标准循环

```
改代码 -> swift build -> 修编译错误 -> swift run AgentBar -> 手动 socket 测试 -> 验证 UI -> commit
```

### 具体步骤

1. **修改代码** — 编辑 `Sources/AgentBar/` 下的文件
2. **编译** — `swift build` 检查编译错误，快速反馈
3. **运行** — `swift run AgentBar`，观察终端日志输出
4. **测试** — 用 socat/python 发送测试消息到 socket，观察面板变化
5. **验证** — 确认 UI 正确显示、交互正常、响应正确
6. **提交** — `git add` + `git commit`

### 注意事项

- 每次修改后先 `swift build` 确认编译通过再运行
- AgentBar 运行时会占用 `/tmp/agentbar.sock`，重新运行前确保旧进程已退出
- 如果 socket 文件残留导致 bind 失败，手动删除：`rm /tmp/agentbar.sock`
- NSPanel 相关的 UI 调试，建议在有刘海的 MacBook 上测试，外接显示器可能定位不准
- 修改消息协议后，同步更新 `Scripts/agentbar-hook.sh` 和 `docs/PROTOCOL.md`
