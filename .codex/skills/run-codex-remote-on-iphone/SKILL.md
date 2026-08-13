---
name: run-codex-remote-on-iphone
description: Build, sign, install, configure, launch, verify, and maintain the Codex Remote iPhone app and its local Relay/Mac Agent stack. Use when the user asks to run, rebuild, refresh, deploy, install, or test Codex Remote on a physical iPhone; asks for Cmd+R-equivalent deployment; wants to restart or troubleshoot the local Relay Server, Mac Agent, Codex App Server, or Code Mode Host; encounters a missing codex-code-mode-host after an install or ChatGPT/Codex upgrade; or asks to update the related maintenance documentation. Trigger on equivalent Chinese requests such as 真机运行、真机调试、重新构建到手机、刷新 iPhone App、启动 Relay 和 Mac Agent、代码执行器缺失、升级后无法执行、维修手册、更新维护文档、连接局域网 Relay、连接远程 Relay、或使用指定 WebSocket 地址。
---

# Run Codex Remote on iPhone

Run commands from the `iphone-app` repository root. Read the repository `AGENTS.md` files before changing code or diagnosing a failure.

## Select a Mode

- Normal local deployment: use the script without a Relay argument. It reuses the running `iphone` Relay and Mac Agent, discovers the Mac LAN URL, deploys the app, injects the URL, and verifies a new App connection.
- Full local stack restart: use `--restart-stack` only from Codex Desktop or Terminal when Relay or Mac Agent code, configuration, or runtime changed. Never use this mode from an iPhone-hosted Turn.
- Existing remote Relay: require the exact user-provided `ws://` or `wss://` URL ending in `/ws/app`. Pass it with `--relay-url`; this mode must not restart local Relay or Mac Agent services.

Never invent, rewrite, or silently substitute a remote host. If the user requests remote mode without providing a URL, ask for it.

## Run

For local LAN debugging:

```bash
./scripts/run-device.sh
```

For an explicit full stack restart from an external Mac session:

```bash
./scripts/run-device.sh --restart-stack
```

For an existing remote Relay:

```bash
./scripts/run-device.sh --relay-url "wss://relay.example.com/ws/app"
```

When multiple iPhones are paired, add `--device <name-or-id>`. Use `--no-launch` only when the user explicitly wants install-only behavior; it cannot inject or verify a new Relay URL.

When the script detects that it is running inside the iPhone Mac Agent, it automatically builds and preflights synchronously, then starts a detached one-shot refresh job. The job waits for the App's `turn.acknowledged(status=completed)` before installing or terminating the current App. Keep the job free of `KeepAlive`, start it explicitly with `launchctl kickstart`, and unload it on every terminal path; do not use `launchctl submit` for this workflow because a short-lived submitted job can be relaunched repeatedly. After the script prints `Environment ready; deferred iPhone refresh scheduled`, end the Turn with a concise final message such as `环境已经准备好，正在重启刷新 iPhone App。` Do not run another foreground tool afterward.

## Preflight the Local Runtime

For local LAN mode, treat the Mac Agent `./dev iphone` checks as required preflight. Confirm its `Codex CLI` output is the canonical executable path, not a `~/.local/bin/codex` symlink. For an App bundle installation, require an executable `codex-code-mode-host` beside the resolved `codex` binary.

If startup or an iPhone task reports a missing Code Mode Host, read `../mac-agent/docs/maintenance.md` from the `iphone-app` repository root before changing code. Do not recommend restarting the desktop App as the sole fix and do not create a second helper symlink as a permanent workaround. Verify the launch path used by the running Mac Agent and fix path resolution at the process boundary.

## Verify and Report

For external synchronous deployment, treat the command as successful only when it reports all required stages:

- local stack reuse, or an explicitly requested stack restart;
- Xcode build success;
- app installation and launch;
- `iPhone app connected to Relay`.
- the task composer shows the current project's execution profile selector after the Agent connects.

For an iPhone-hosted deferred deployment, the current Turn may only claim that the environment is ready and the refresh is scheduled. The detached job records `waiting`, `running`, `completed`, `cancelled`, or `failed` under `.build/device-refresh/`; verify the final result after the App reconnects. Confirm the matching log contains exactly one install and one launch, and that `launchctl print gui/$(id -u)/<job-label>` no longer finds the completed job. Do not describe the preflight-only Turn as an already completed installation.

Report the selected device and Relay URL. If the command fails, relay the exact failing stage and error. Do not describe a build-only result as successful device validation.

For runtime maintenance, also run the focused Mac Agent tests and confirm the selected service profile reports `agent_connected: true`. Verify `execution.profile.list` returns the expected allowed profiles for one real project; do not infer permission negotiation only from `agent.capabilities`. Distinguish path inspection, automated tests, Relay connection, permission-profile discovery, and an actual iPhone Turn in the report.

## Maintain Upgrade Documentation

When a ChatGPT/Codex release changes binary layout, App Server flags, companion processes, or startup behavior:

1. Check the current official App Server documentation and local `codex app-server --help`.
2. Update Mac Agent runtime validation and focused regression tests together.
3. Update `../mac-agent/docs/maintenance.md`, its README link, and the Mac Agent Unreleased changelog.
4. Update this skill when the diagnosis or recovery workflow changes, then regenerate `agents/openai.yaml` if its description is stale.
5. Validate the skill with the skill-creator `quick_validate.py` script.

Do not encode one machine's home directory or App version as an invariant. Document recognizable layouts, diagnostic commands, expected outcomes, and a recovery path for fresh installations.

## Triage New Incidents

After resolving any non-trivial issue, decide whether it should produce a durable maintenance artifact. Record it when it can recur across machines or upgrades, required non-obvious diagnosis, caused repeated failed attempts, needs a manual recovery sequence, or can silently disrupt user work.

Route the result deliberately:

- add an automated preflight for conditions detectable before startup or deployment;
- add a focused regression test for corrected behavior;
- add installation or upgrade steps to `../mac-agent/docs/maintenance.md` when an operator may need them;
- add a repository invariant to the applicable `AGENTS.md` when future implementations must obey it;
- update this skill when the AI workflow, evidence requirements, or document synchronization steps change.

Include the symptom, scope, verified root cause, fastest diagnosis, recovery, prevention, and verification. Revise obsolete guidance rather than appending a competing workaround. Skip transient external failures and obvious one-off mistakes unless they reveal a reusable invariant.

## Safety

- Require an unlocked, paired iPhone with Developer Mode and valid Xcode signing.
- Keep Relay URLs free of embedded credentials, query tokens, and fragments; the script rejects them.
- The current Relay protocol has no application-layer authentication. Do not expose plain `ws://` directly to the public internet. Prefer a trusted LAN or VPN; for non-private networks require a protected `wss://` endpoint and state that TLS alone does not add Relay identity or application authentication.
- Do not disable TLS verification or bypass Xcode signing checks.
- Do not print credentials or unrelated device data.
- Never replace a terminal acknowledgement with a fixed sleep, and never synchronously restart the Agent that hosts the current Turn.
