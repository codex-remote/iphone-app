# Diagnostics

CodexRemote uses Apple Unified Logging, bounded structured JSONL, and MetricKit. The same
event vocabulary feeds both the system log and the export file so diagnosis does not depend
on ad hoc text searches.

## Current implementation and target boundary

The current app does not upload telemetry automatically. Settings export and Mac-side
collection are the supported evidence paths today.

The accepted next architecture keeps one production-grade upload state machine for both
development and production. Development adds CoreDevice pull as a recovery path; it does not
fork the logging schema or queue implementation.

```text
development = production logging and upload behavior + CoreDevice container pull
```

The cross-service contract is documented in `Codex Remote/01-架构设计/日志采集与诊断数据流.md`.

## Data paths

| Source | Purpose | Retention |
| --- | --- | --- |
| Apple Unified Logging | Console, Xcode, `log`, Instruments | Managed by iOS |
| `Library/Application Support/Diagnostics/events*.jsonl` | Ordered app events for export and automation | 4 files, 512 KiB each |
| `metrickit-*.json` | Apple crash, hang, CPU, disk-write, launch, memory and daily metrics | Newest 8 reports, 4 MiB each |

In the current implementation, no telemetry is uploaded. Export is an explicit user action in
Settings > Diagnostics. The temporary export directory retains only the newest three export
files.

In the accepted target architecture, sealed JSONL segments and MetricKit reports enter a
bounded persistent upload queue. A segment is removed only after the destination acknowledges
its stable event IDs or artifact checksum.

## Upload and collection model

Development and production use the same local queue, batching, retry, sampling, privacy, and
capacity rules. Target triggers are:

| Trigger | Action | Reliability note |
| --- | --- | --- |
| 100-200 records | Seal and enqueue a segment | Threshold is configurable |
| 64-256 KiB | Seal and enqueue a segment | Prevents oversized batches |
| 10-30 seconds while foregrounded | Submit a pending partial batch | Only when work exists |
| Network becomes available | Retry eligible batches | Exponential backoff with jitter |
| App launch or foreground | Recover and submit persisted batches | Primary recovery after termination |
| App enters background | Seal and attempt a small batch | Completion is not guaranteed |
| MetricKit report arrives | Persist first, then enqueue | Treat reports as artifacts |
| User submits a support report | Pin and prioritize the incident window | Still applies privacy and size limits |

These ranges are design defaults, not implemented constants. They require physical-device CPU,
memory, storage, network, and energy measurements before release.

Production uploads use the SLS iOS SDK with short-lived STS credentials obtained from a trusted
service. Never embed a long-lived Alibaba Cloud AccessKey in the app.

Development adds a Mac-side pull of sealed files from the app data container:

```bash
xcrun devicectl device copy from \
  --device <device-id> \
  --domain-type appDataContainer \
  --domain-identifier <bundle-id> \
  --source <diagnostics-directory> \
  --destination <mac-destination> \
  --json-output <result.json>
```

The bundle identifier must come from the selected build. The Admin Platform collector may
generate this command only from a validated device, registered bundle ID, allowlisted
diagnostics directory, and structured task type. The browser must never submit shell text or
an arbitrary source path.

## Record schema

Every JSONL record contains:

- `schema_version`: increment only for a breaking schema change.
- `timestamp` and `uptime_ms`: wall-clock ordering plus monotonic process time.
- `session_id` and `sequence`: identify one launch and provide deterministic ordering.
- `level`, `category`, and `event`: stable filter dimensions.
- `trace_id`: Relay correlation ID when one exists.
- `turn_ref`: session-scoped SHA-256 reference, never the raw Turn ID.
- `fields`: event-specific values from the `DiagnosticField` allowlist.

Event names use `area.action_or_state`, for example `relay.send_failed` and
`memory.warning`. Do not rename an existing event. Add a new event and update this document.

## Levels

- `debug`: high-volume development details; do not rely on persistence.
- `info`: normal lifecycle and measurements.
- `notice`: meaningful state transitions and user-visible outcomes.
- `warning`: degraded behavior with automatic recovery.
- `error`: an operation failed.
- `fault`: an app invariant or resource condition may terminate the process.

## Privacy contract

Allowed fields are enums in `Diagnostics.swift`. Never add prompts, responses, transcript
content, console output, credentials, authorization headers, Relay URLs, user-entered text,
full file paths, device serial numbers, or permanent device identifiers. Prefer counts,
durations, byte sizes, public protocol types, error domains and numeric error codes.

Do not put `localizedDescription` in diagnostic events. Error domain and code are stable,
machine-readable, and less likely to expose server or user data.

## Incident workflow

1. Ask the user to export Settings > Diagnostics immediately after the failure or next launch.
2. For a connected development device, run `scripts/collect-diagnostics.sh DEVICE_ID OUTPUT_DIR`.
3. Start with `summary.json`, then inspect `events.jsonl` by `session_id`, `trace_id`, and
   `turn_ref`. Compare the final memory samples, buffer drops and Relay state transitions.
4. Open the `.logarchive` in Console for surrounding Apple system events. Open MetricKit
   reports for crash, hang, CPU, disk-write or launch diagnostics.
5. For memory incidents, reproduce with Allocations and Leaks; use the scheme's automatic
   memory graph on resource exception. JSON events identify the workflow and growth trend,
   but do not replace an allocation backtrace.

An OOM or Jetsam termination does not reliably call `applicationWillTerminate`, deliver a memory
warning, or provide time for a final network request. Diagnosis must combine events persisted
before termination, next-launch queue recovery, MetricKit, CoreDevice system crash logs, and a
sysdiagnose when justified.

## Adding instrumentation

Before merging a new event:

1. Reuse an existing event when it represents the same state transition.
2. Add event and field names to the typed enums; do not pass free-form keys.
3. Include `trace_id` for Relay operations and a Turn ID only through `turnID:` hashing.
4. Rate-limit loop, delta, retry and pressure-path events.
5. Add a schema or rotation test and update the event catalog below.
6. Verify Console output, JSONL export, localization and the generic iOS build.

When automatic upload is implemented, also verify offline persistence, duplicate acknowledgement,
queue pressure, background transition, next-launch recovery, STS expiry, and CoreDevice pull on a
physical device. Upload failure must not block the main actor or grow an unbounded in-memory queue.

## Event catalog

| Category | Events |
| --- | --- |
| `lifecycle` | `app.launched`, `app.entered_background`, `app.entered_foreground`, `app.will_terminate` |
| `memory` | `memory.snapshot`, `memory.warning`, `memory.cleanup` |
| `relay` | `relay.connect_started`, `relay.connected`, `relay.disconnected`, `relay.reconnect_scheduled`, `relay.request_sent`, `relay.response_received`, `relay.decode_failed`, `relay.send_failed`, `relay.buffer_dropped`, `relay.connection_test_started`, `relay.connection_test_completed` |
| `turn` | `turn.started`, `turn.ended` |
| `speech` | `speech.started`, `speech.ended`, `speech.failed` |
| `diagnostics` | `diagnostics.metric_payload_received`, `diagnostics.diagnostic_payload_received` |

The persisted Relay response list intentionally excludes `turn.item.delta` and output payloads.
Their byte totals and retained-character counts are represented by periodic memory snapshots.
