# Changelog

AI Coding Remote iPhone App 的重要变更记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)。正式发布后遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)。

> Release status: **Unreleased**
>
> 首个生产 GitHub Release 发布前不承诺向后兼容。预发布阶段的破坏性变更会直接移除旧实现，并记录在 `Changed` 或 `Removed`。

## [Unreleased]

### Added

- 提供 SwiftUI 单页远程控制台和 Relay URL 本地设置。
- 支持多个 Project、Codex Thread、新会话和继续会话。
- 支持启动和中断 Turn，实时展示 assistant、stdout、stderr 与完成结果。
- 提供空闲、运行、完成、失败和离线 Mock 场景。

### Changed

- App 协议升级为 `spec_version: "2.0"`，使用 Project、Thread、Turn 界面模型。
- WebSocket 发送统一使用文本帧承载 JSON。

### Removed

- 删除 `spec_version: "1.0"` 的 `run.*` 客户端模型和界面状态。

### Fixed

- 修正 Relay 对文本帧的协议要求，避免发送二进制 JSON 帧。
- 修正 RFC 3339 时间解析和局域网权限配置。
