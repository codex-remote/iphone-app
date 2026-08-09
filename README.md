# AI Coding Remote - iPhone App

AI Coding Remote 的移动控制端。使用 SwiftUI 构建，通过 WebSocket 连接 Relay Server，向一台 Mac Agent 发起 Codex Run，并实时展示状态、输出和结果。

## 当前状态

仓库已初始化，尚未生成 Xcode 工程或业务代码。

当前实现基线是单用户 MVP：无登录、无设备管理、无任务列表、无服务端历史。Relay 必须运行在 Tailscale 等私有网络中。

## 本仓库负责

- Relay URL 的本地配置。
- WebSocket 连接、断线重连和前后台生命周期。
- Mac Agent 的在线、空闲和运行中状态展示。
- Prompt 输入、启动和停止当前 Run。
- stdout、stderr 和系统事件的实时 Console。
- 完成、失败、取消结果和 Git Diff 摘要展示。
- 使用 `run.snapshot` 恢复当前页面和最近日志。

## 本仓库不负责

- Relay 消息路由和连接注册。
- Codex CLI 的启动、参数和本地进程管理。
- 用户鉴权、设备配对、数据库和 Task 管理。
- 修改 Mac 工作目录或传递任意 Shell 命令。

## 项目边界

本仓库不依赖 `relay-server` 或 `mac-agent` 的源码。三端只通过版本化 JSON 协议协作：

- 协议版本：`spec_version: "1.0"`
- App 连接端点：`/ws/app`
- Relay 协议 Schema 和 Fixtures 是线上的协议权威来源。
- Swift 模型必须通过相同 Fixtures 的契约测试。
- 新增协议字段必须保持向后兼容；UI 不直接拼装或解析原始 JSON。

本地架构说明位于：`../Codex Remote/02-通信协议/MVP WebSocket 协议.md`。

## MVP 界面

第一版只需要一个主工作台：

```text
Connection Status
Mac: Online / Idle / Running

Run Console
--------------------------------
Streaming stdout/stderr...
--------------------------------

Prompt Editor
[ Run ] / [ Stop ]
```

建议代码边界：

```text
AICodingRemote/
├── App/
├── Features/Console/
├── Services/RelayClient.swift
├── Models/Message.swift
└── Models/RunState.swift
```

SwiftUI View 只依赖 `RunState` 和 ViewModel；网络连接、协议编解码和重连逻辑放在 `RelayClient`。

## 计划中的本地配置

- Relay WebSocket URL，例如 `wss://relay.example.ts.net/ws/app`
- Console 最大保留行数
- 自动重连开关

配置存储在 iPhone 本地，不提交环境地址或个人信息到 Git。

## MVP 验收

- 真机可以连接 Relay 并看到 Mac 在线状态。
- 可以发送 Prompt 并看到 `run.started`。
- 可以连续展示 stdout 和 stderr。
- Stop 可以取消当前 Run。
- App 切到后台再回来后可以重连并恢复快照。
- 长日志不会导致界面明显卡顿或内存持续增长。

## 后续扩展

未来的登录、设备列表、Task 历史和多项目选择通过新增 Service 和 Feature 接入，不改变现有 Console 与 `run.*` 执行协议。
