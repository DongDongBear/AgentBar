# AgentBar

Mac 刘海屏上的 AI Agent 统一监控面板。支持在刘海区域直接输入文字回答 Agent 的提问。

## 功能

### P0（核心）
- **刘海区域浮动面板** — 在 Mac notch 区域显示可展开的监控面板，非激活窗口不抢焦点
- **多 Agent 监控** — 同时显示 Claude Code、Codex CLI、Gemini CLI 的运行状态
- **权限批准/拒绝** — Agent 请求权限时，面板上 Allow/Deny 按钮一键操作
- **文字输入回答** — Agent 提问时，面板上直接输入文字回答（核心差异！）
- **零配置 hook** — 启动时自动配置所有 Agent 的 hook

### P1
- 终端跳转 — 点击 session 跳转到对应终端
- 音效提醒 — 任务完成、权限请求、提问时播放提示音
- Plan 预览 — Markdown 渲染 Agent 的计划

## 技术栈
- 纯 Swift + SwiftUI
- macOS 13+ (Ventura)
- Apple Silicon 优化
- 本地 Unix socket 通信（不联网）
- 目标：<50MB 内存

## 构建

### 前置要求
- macOS 13.0+ (Ventura 或更新)
- Xcode 15+ 或 Swift 5.9+ toolchain
- Apple Silicon 或 Intel Mac

### 使用 Swift Package Manager 构建

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
# 或
.build/release/AgentBar
```

### 使用 xcodebuild 构建

```bash
# 生成 Xcode 项目（可选）
swift package generate-xcodeproj

# 或直接用 xcodebuild
xcodebuild -scheme AgentBar -configuration Release build
```

### 创建 .app 包

构建完成后，如需创建标准的 macOS .app 包：

```bash
# 构建 Release
swift build -c release

# 创建 .app 结构
mkdir -p AgentBar.app/Contents/MacOS
mkdir -p AgentBar.app/Contents/Resources
cp .build/release/AgentBar AgentBar.app/Contents/MacOS/
cp Sources/AgentBar/Info.plist AgentBar.app/Contents/

# 运行
open AgentBar.app
```

## 运行

启动后 AgentBar 会：
1. 在状态栏显示一个 CPU 图标
2. 在刘海区域显示一个浮动面板
3. 自动安装 hook 到 `~/.claude/settings.json`、`~/.codex/hooks.json`、`~/.gemini/settings.json`
4. 启动 Unix socket server 在 `/tmp/agentbar.sock` 监听

然后正常使用 Claude Code / Codex CLI / Gemini CLI，AgentBar 会自动接收事件并显示在面板上。

## 架构

```
Sources/AgentBar/
├── AgentBarApp.swift       # SwiftUI App 入口
├── AppDelegate.swift       # NSApplicationDelegate, 面板 & 服务管理
├── Info.plist              # App 元数据 (LSUIElement=true 隐藏 Dock)
├── Models/
│   ├── AgentType.swift     # Agent 类型枚举
│   ├── AgentSession.swift  # 会话模型
│   └── AgentMessage.swift  # Socket 消息协议
├── Services/
│   ├── SocketServer.swift  # Unix socket 服务器
│   ├── SessionManager.swift# 会话管理器
│   ├── HookInstaller.swift # Hook 自动安装
│   └── SoundManager.swift  # 音效管理
├── Views/
│   ├── NotchPanelView.swift    # 刘海面板主视图
│   ├── SessionListView.swift   # 会话列表
│   ├── PermissionDialogView.swift # 权限审批
│   ├── AgentInputField.swift   # 文字输入框（核心差异）
│   └── PlanViewerView.swift    # Markdown 计划预览
├── Utils/
│   ├── Constants.swift     # 常量定义
│   └── Color+Hex.swift     # Color hex 扩展
└── Resources/
    └── .gitkeep

Scripts/
└── agentbar-hook.sh        # Hook 脚本（独立备份）
```

## 通信协议

Agent hook → AgentBar 的 JSON 消息格式：

```json
{
  "sessionId": "uuid",
  "agentType": "claude_code",
  "event": "ask_user",
  "workingDirectory": "/path/to/project",
  "payload": {
    "question": "Which database should I use?"
  }
}
```

AgentBar → hook 的响应格式：

```json
{
  "action": "answer",
  "text": "Use PostgreSQL"
}
```

## License

MIT
