# AI Coding Remote - iPhone App

SwiftUI 移动控制台。App 通过 WebSocket 连接 Relay，列出 Mac 上的多个 Git 项目与 Codex 历史会话，在新会话或已有会话中启动 Turn，并实时展示输出和结果。

## 当前能力

- 真实 `URLSessionWebSocketTask` Relay Client。
- Relay URL 本地设置和自动重连。
- 多 Project 选择与刷新。
- Project 下的 Codex Thread 列表、新会话和继续会话。
- Prompt、执行、中断、assistant/stdout/stderr Console。
- 完成、失败、中断结果和最近日志恢复。
- 本地 Mock 场景用于空闲、运行、完成、失败和离线 UI 验证。

当前是单用户、单 Mac、全局单 Turn MVP。没有登录、设备管理、业务 Task、队列和服务端历史。

## 发布状态

当前为 **Unreleased**，尚未形成生产兼容基线。首个正式版本发布前允许直接进行破坏性调整，不提供旧协议、旧设置或旧本地数据兼容；所有重要变更记录在 [CHANGELOG.md](CHANGELOG.md)。

## 运行

1. 启动 Relay Server 和 Mac Agent。
2. 使用 Xcode 打开 `CodexRemote.xcodeproj`。
3. 选择 iPhone Simulator 或真机，运行 `CodexRemote` Scheme。
4. 在右上角 Settings 填入 `ws://<局域网-IP>:8080/ws/app`。

Debug 构建也可从命令行验证：

```bash
xcodebuild \
  -project CodexRemote.xcodeproj \
  -scheme CodexRemote \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

iOS 会请求本地网络权限。Relay 没有应用层鉴权，必须处于可信局域网或私有网络中。

## Mock 场景

右上角省略号菜单可切换 UI 状态。模拟器也可以带启动参数：

```text
--demo-running
--demo-completed
--demo-failed
--demo-offline
```

未提供 Demo 参数时，App 使用真实 `RelayClient`。

## 协议边界

- 协议：`spec_version: "2.0"`
- App 入口：`/ws/app`
- App 发送：`project.list`、`thread.list`、`turn.start`、`turn.interrupt`
- App 接收：Agent 状态、Project/Thread Snapshot、Turn 事件
- SwiftUI View 不直接拼装或解析 JSON

不兼容旧 `1.0 run.*` 协议。

## 结构

```text
CodexRemote/
├── App/CodexRemoteApp.swift
├── Core/AppTheme.swift
├── Features/
│   ├── Settings/SettingsView.swift
│   └── Workspace/
│       ├── WorkspaceView.swift
│       ├── WorkspaceViewModel.swift
│       ├── PromptComposer.swift
│       ├── ConsoleView.swift
│       └── StatusStrip.swift
├── Models/RelayModels.swift
└── Services/
    ├── RelayService.swift
    ├── RelayClient.swift
    └── MockRelayService.swift
```

未来登录、设备列表、业务 Task 历史和多 Mac 通过新增 Service/Feature 接入；Project/Thread/Turn 工作台保持独立于传输实现。
