# AI Coding Remote - iPhone App

SwiftUI 移动控制台。App 通过 WebSocket 连接 Relay，列出 Mac 上的多个 Git 项目与 Codex 历史会话，在新会话或已有会话中启动 Turn，并实时展示输出和结果。

开发与 UI 实现遵循 [AGENTS.md](AGENTS.md) 中的项目规范，其中 Apple 官方 API、Human Interface Guidelines 和原生交互方案具有最高优先级。工作区的状态边界、文件职责和扩展规则见 [架构文档](docs/architecture.md)。

## 当前能力

- 真实 `URLSessionWebSocketTask` Relay Client。
- Relay URL 本地设置和自动重连。
- Simulator/iPhone 独立连接预设，以及 Relay `/status` 测试和全新重连。
- 多 Project 选择与刷新。
- Project 下的 Codex Thread 列表、新会话和继续会话。
- 选择历史会话时通过 `thread.read` 加载持久化 Turns，并在 Console 展示消息、命令输出和文件变更。
- Prompt、执行、中断、assistant/stdout/stderr Console。
- 完成、失败、中断结果和最近日志恢复。
- 在任务提交前显示 Mac Agent 的受限执行状态，并提供沙箱、授权策略和不可用宿主能力详情。
- 按项目读取 App Server 允许的执行档位，在原生菜单中选择只读、工作区或完整权限，并把选择同时应用于 Codex Thread 和 Turn。
- 使用 Apple Unified Logging、有限容量 JSONL、MetricKit 和诊断导出保存可脱敏的本地证据。
- 本地 Mock Relay 用于 UI 自动化和离线开发验证。

当前运行模型是单用户、单 Mac、全局单 Turn。

当前版本为 **0.0.1**，是首个最小可用快照。`0.x` 阶段继续快速迭代，后续变更按实际影响决定是否兼容，并在 [CHANGELOG.md](CHANGELOG.md) 中记录；此版本不代表兼容性冻结。

## 诊断架构边界

当前 App 只在本地生成 Unified Logging、有限容量 JSONL 和 MetricKit 文件，自动批量上传尚未实现。完整事件 Schema、隐私边界和事故采集流程见 [诊断文档](docs/diagnostics.md)。

已接受的下一阶段架构要求开发与线上共用同一套本地持久队列、批量、重试、采样和容量逻辑：开发环境上传到本地 Admin Platform，并额外允许 Mac Collector 通过 CoreDevice 拉取 App Data Container 中已密封的日志；线上环境通过 SLS iOS SDK 和 STS 临时凭据上传。CoreDevice 是开发诊断兜底，不是第二套日志实现。

OOM/Jetsam 发生时不能依赖 App 终止回调完成上传。定位需要组合强杀前已落盘事件、下次启动补传、MetricKit、系统崩溃日志和必要时的 sysdiagnose。

## 运行

1. 在 `mac-agent` 仓库执行 `./dev simulator`，启动 Simulator 专用的 Relay 与 Mac Agent。
2. 使用 Xcode 打开 `CodexRemote.xcodeproj`。
3. 选择 iPhone Simulator 或真机，运行 `CodexRemote` Scheme。
4. iPhone Simulator 默认连接 `ws://127.0.0.1:18767/ws/app`。

真机无法使用 Mac 的回环地址，并且必须与 Mac 位于可互通的可信局域网。真机运行脚本默认复用已经连接的 iPhone profile Relay 与 Mac Agent，提取 Mac 当前局域网地址，并写入 App 的 iPhone 连接配置。

Xcode 已配置好签名、真机完成配对且 iPhone profile 已运行后，可以一条命令完成 Debug 构建、覆盖安装、连接配置和启动：

```bash
./scripts/run-device.sh
```

只有一台已配对 iPhone 时脚本会自动选择。连接多台设备时按名称或设备 ID 指定：

```bash
./scripts/run-device.sh --device "LeeHoo i14P"
```

脚本使用 Apple 官方的 `xcodebuild` 和 `devicectl`，效果相当于不附加 LLDB 调试器的 Xcode `Cmd + R`。App 启动后脚本还会通过 Relay `/status` 确认真机建立了新的连接。仅构建并安装、不自动打开 App 时传入 `--no-launch`。

只有需要更新 Relay 或 Mac Agent 二进制、配置或运行时时，才从 Mac 桌面 Codex 或终端显式重启完整栈：

```bash
./scripts/run-device.sh --restart-stack
```

脚本检测到自己运行在 iPhone Mac Agent 承载的 Turn 中时，会拒绝 `--restart-stack` 并自动采用延迟刷新：先完成设备预检和构建，等待 iPhone 应用 `turn.completed` 并发送 `turn.acknowledged`，再由无 `KeepAlive` 的一次性 `launchd` 任务安装和启动 App；任务结束后会卸载自身，禁止重复覆盖安装。延迟任务状态与日志位于 `.build/device-refresh/`。

连接已经运行的非局域网 Relay 时显式传入完整 App WebSocket 地址。此模式不会重启本机 Relay 或 Mac Agent：

```bash
./scripts/run-device.sh --relay-url "wss://relay.example.com/ws/app"
```

远程 Relay 必须提供同源 `/status`，并由目标环境的 Mac Agent 建立连接。当前协议没有应用层鉴权；不要把无 TLS 的 Relay 直接暴露到公网，远程调试应使用可信私网、VPN，或配有 TLS 与访问控制的入口。

仓库内提供 `$run-codex-remote-on-iphone` Skill，AI 可根据“真机运行 Codex Remote”“重启局域网调试并更新手机”或“使用指定 Relay 地址部署到 iPhone”等自然语言请求调用上述流程。也可以显式写出 Skill 名称避免歧义。

打开 Settings 中的“连接”开关时，App 会从当前 WebSocket 地址推导同主机同端口的 HTTP `/status`，检查成功后保存该设备 profile 的地址并建立新的 WebSocket；关闭开关会断开当前连接并清除旧项目缓存。Simulator 与 iPhone 的地址分别保存，互不覆盖。

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

## 开发规范

Apple 平台能力优先采用公开的 Apple 官方 SwiftUI、UIKit 与系统框架 API，并以 Apple Developer Documentation 和 Human Interface Guidelines 为实现依据。新系统 API 必须配套 deployment target 可用的公开回退方案；仅当官方能力无法满足需求时才引入第三方 UI 依赖，并记录原因和维护影响。仓库级完整约束见 [`AGENTS.md`](AGENTS.md)。

## 协议边界

- 协议：`spec_version: "2.0"`
- App 入口：`/ws/app`
- App 发送：`project.list`、`execution.profile.list`、`thread.list`、`thread.read`、`turn.start`、`turn.interrupt`、`turn.acknowledged`
- App 接收：Agent 状态与执行能力、`execution.profile.snapshot`、Project/Thread Snapshot、`thread.detail`、Turn 事件
- SwiftUI View 不直接拼装或解析 JSON。

## 结构

```text
CodexRemote/
├── App/CodexRemoteApp.swift
├── Core/AppTheme.swift
├── Features/
│   ├── Settings/SettingsView.swift
│   └── Workspace/
│       ├── WorkspaceView.swift
│       ├── WorkspaceSupportViews.swift
│       ├── WorkspaceViewModel.swift
│       ├── TurnSessionStore.swift
│       ├── SlidingWorkspaceContainer.swift
│       ├── ProjectDrawerView.swift
│       ├── ProjectDrawerComponents.swift
│       ├── TaskWorkspaceView.swift
│       ├── ComposerDock.swift
│       ├── PromptComposer.swift
│       ├── TranscriptView.swift
│       ├── MarkdownContentView.swift
│       ├── ActivityHomeView.swift
│       ├── ExecutionAccessView.swift
│       ├── WorkspaceComponents.swift
│       ├── ConsoleView.swift
│       └── VoiceTranscriptionController.swift
├── Models/RelayModels.swift
└── Services/
    ├── RelayService.swift
    ├── RelayClient.swift
    ├── RelayWireTypes.swift
    └── MockRelayService.swift
```
