# iPhone Memory Termination: 2026-08-12

## Symptoms and scope

- Xcode reported `IDEDebugSessionErrorDomain` code 11: CodexRemote was terminated for excessive memory use.
- The affected Run used a physical iPhone 14 Pro on iOS 26.6.
- The app ran from 16:10:08 to 16:34:43, about 24 minutes and 32 seconds.
- No matching Jetsam event, allocation trace, or memory graph was available for this Run.

## Verified diagnosis

The operating system terminated the foreground app for memory use. The available Xcode result does not contain an allocation stack or retained-object graph, so it cannot identify a specific source line. The device crash-log service had no matching 16:34 Jetsam report when checked after the incident.

The following are prevention targets, not proven root causes:

- Relay events previously used the default unbounded `AsyncStream` buffer.
- RFC3339 decoding previously created two `ISO8601DateFormatter` instances for every date field.
- Speech recognition had no app-side duration limit.

## Recovery and prevention

- Relay delivery now retains the newest 64 pending events and logs every dropped event count.
- RFC3339 formatters are reused.
- The app records a memory checkpoint every 30 seconds and at launch, memory warning cleanup, and selected lifecycle boundaries.
- Memory warnings evict noncurrent transcript caches and console output, which can be reloaded or regenerated.
- Legacy `SFSpeechRecognizer` recording stops after 55 seconds.
- The shared Run scheme enables Memory Graph on Resource Exception.

Diagnostics intentionally contain counts, byte totals, available memory, and durations only. Do not add prompts, responses, file contents, full paths, credentials, or Relay payloads.

## Fast diagnosis for another occurrence

1. Preserve the Xcode `.xcresult`, `.trace`, and `.memgraph` before running the app again.
2. In Xcode's console or Console.app, filter the app subsystem and category `Memory`. Compare `available_mb`, `relay_messages`, `relay_mb`, `dropped_events`, `transcript_messages`, `live_items`, and `live_characters` over time.
3. From the connected device, retrieve `JetsamEvent_<timestamp>.ips` from `systemCrashLogs`, or use Settings > Privacy & Security > Analytics & Improvements > Analytics Data.
4. Profile the same workflow on the physical device with Instruments Allocations. Mark generations after launch, history load, Turn start, and text or voice input.
5. Capture a memory graph before the memory gauge reaches the red region. Compare retained types and paths with the Allocations growth interval.

Do not use Address Sanitizer for the memory-footprint baseline because its instrumentation substantially increases memory use.

## Verification evidence

- Simulator test build succeeded with strict concurrency enabled.
- Seven focused unit tests passed, including bounded live content, bounded Relay buffering, and both supported RFC3339 date formats.
- Generic arm64 iOS compilation was checked without code signing.
- Physical-device memory growth still requires an Instruments reproduction; a build or unit test cannot prove that the original runtime issue is resolved.
