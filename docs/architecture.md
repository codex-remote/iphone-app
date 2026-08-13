# iPhone App Architecture

This document defines the ownership boundaries for Codex Remote's iPhone app.
Keep feature behavior inside these boundaries when extending the app.

> **Architecture status:** the running app currently uses Relay WebSocket communication and a
> local diagnostics pipeline. The accepted Admin Platform and SLS upload path is a target boundary
> until its queue, credentials, ingestion, and physical-device tests land.

## Data Flow

```text
RelayServiceProtocol
        |
        v
WorkspaceViewModel ----------> project, thread, connection, navigation state
        |
        +--------------------> TurnSessionStore (high-frequency Turn state)
                                      |
                                      v
                               TaskWorkspaceView

PromptComposer (local draft) --submit/interrupt--> WorkspaceViewModel
```

`WorkspaceViewModel` coordinates Relay requests and low-frequency workspace state.
`TurnSessionStore` reduces streaming Turn events, enforces sequence ordering and
memory bounds, and publishes only to views that need live output. A token delta
must never be published through `WorkspaceViewModel.objectWillChange`.

## Workspace File Ownership

| File | Ownership |
| --- | --- |
| `WorkspaceView.swift` | Root navigation, sheets, toolbar and startup lifecycle |
| `WorkspaceSupportViews.swift` | New-session picker and startup loading presentation |
| `SlidingWorkspaceContainer.swift` | UIKit sibling layout, drawer gesture arbitration and accessibility visibility |
| `ProjectDrawerView.swift` | Project drawer coordination and project detail screen |
| `ProjectDrawerComponents.swift` | Drawer rows, loading states and scroll-boundary UIKit bridge |
| `TaskWorkspaceView.swift` | Transcript composition, focus dismissal and live Turn presentation |
| `ComposerDock.swift` | Composer spacing, keyboard-safe background and visual transition |
| `PromptComposer.swift` | Local draft, voice input controls and explicit submit/interrupt actions |
| `TurnSessionStore.swift` | Streaming sequence reducer, memory limits, logs and Turn terminal state |
| `TranscriptView.swift` | Persisted transcript and process detail presentation |
| `MarkdownContentView.swift` | Completed-response Markdown rendering |
| `ActivityHomeView.swift` | Activity filtering and session list |
| `ExecutionAccessView.swift` | Execution-profile warning and capability details |
| `WorkspaceComponents.swift` | Small, workspace-wide presentational components |

`RelayClient.swift` owns connection lifecycle and event routing. Transport-only
payloads, errors and JSON date coding live in `Services/RelayWireTypes.swift`.

## Input And Keyboard Rules

- Active draft and marked-text composition stay in `PromptComposer` local state.
- Only trimmed submitted text crosses into `WorkspaceViewModel`.
- `PromptComposer` has separate `onSubmit` and `onInterrupt` actions; do not use
  sentinel prompt values to represent commands.
- `TaskWorkspaceView` owns focus dismissal through `FocusState`, content taps and
  native interactive scroll dismissal.
- `ComposerDock` owns the background behind the keyboard's rounded top corners.
  It uses public safe-area APIs and the workspace background color; never inspect
  or modify the system keyboard view hierarchy.

## Streaming And Memory Rules

- Live Turn fields, item count, file changes and log text remain bounded in
  `TurnSessionStore`.
- Sequence numbers reject duplicate and out-of-order item events.
- Running assistant output renders as lightweight text. Full Markdown parsing is
  deferred until the Turn stops changing.
- Persisted transcripts remain bounded and paged by `ThreadTranscript`.
- Project drawer, settings and root hosting containers must not observe
  high-frequency streaming data.
- Keep the current Turn in a stable outer `VStack`; transcript messages may use
  paging and lazy layout, but scrolling must not destroy the live Turn subtree.

## Diagnostics Boundary

- Apple Unified Logging, bounded JSONL, MetricKit, and the future upload queue share one typed
  event vocabulary and privacy allowlist.
- Development and production use the same persistent queue, batching, retry, sampling, and
  capacity behavior. Development adds Mac-side CoreDevice pull of sealed files only.
- Upload state must not be published through workspace-wide observation or execute on the main
  actor. Queue and network failures cannot block Relay or Turn state updates.
- Do not rely on termination, memory-warning, or scheduled-background callbacks for final upload.
  Persist first and recover on the next launch or foreground transition.
- The iPhone app never executes CoreDevice commands and never stores a long-lived SLS AccessKey.
- Full trigger, storage, and incident rules live in [Diagnostics](diagnostics.md).

## Accessibility And Test Isolation

- Put accessibility identifiers on the smallest actionable control or a
  dedicated marker. A container identifier must not overwrite identifiers on
  its buttons, fields or menus.
- UI tests that read persistent connection or execution-profile settings must
  reset those settings explicitly in their launch arguments.

## Extension Checklist

When adding a composer feature such as attachments or modes:

1. Keep editing state local to the composer.
2. Add explicit semantic actions at the composer boundary.
3. Put safe-area or keyboard visuals in `ComposerDock`.
4. Add state-reducer unit tests and focused UI interaction tests.

When adding Relay events:

1. Decode transport data in Services/Models.
2. Route low-frequency workspace data through `WorkspaceViewModel`.
3. Route high-frequency Turn data through `TurnSessionStore`.
4. Apply explicit count and field-size limits before publishing UI state.
