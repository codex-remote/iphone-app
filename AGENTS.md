# iPhone App Engineering Guidelines

## Apple Platform Development

- Prefer public Apple frameworks, Human Interface Guidelines, and native SwiftUI or UIKit APIs.
- Check current Apple Developer documentation before introducing custom platform behavior or a third-party dependency.
- If a requested visual or interaction behavior conflicts with public Apple components, native gesture semantics, accessibility, safe areas, or lifecycle expectations, stop implementation and ask the workspace owner for a product/design decision before continuing.
- Use availability checks and a documented fallback when the preferred Apple API is newer than the deployment target.
- Do not use private APIs or hard-coded device internals when a public adaptive API exists.
- Preserve native accessibility, safe-area behavior, gesture semantics, and system animation conventions.
- Add a third-party Apple-platform UI dependency only when public system APIs cannot meet the requirement; record the reason and maintenance impact.

## Gesture Arbitration

- Keep standard controls such as `Button`, `Toggle`, and scrolling containers functional when adding custom gestures.
- For side drawers and similar layered navigation, keep the drawer and main content as separate siblings in a `ZStack`; move the main content's actual layout position so the revealed drawer owns hit testing naturally.
- Do not add transparent coordinate-mapping tap layers to make controls clickable. Fix the layout, hit-test ownership, or gesture composition instead.
- If one targeted gesture/hit-test fix fails verification, reassess the architecture before attempting another patch. If the desired behavior needs custom recognition that may compromise native controls, stop and ask for clarification rather than layering fixes.
- Prefer stable system containers such as `UIScrollView`, `NavigationStack`, sheets, split views, and native controls when a SwiftUI-only layout produces ambiguous hit testing or gesture conflicts.
- Prefer the system gesture recognition threshold unless a documented interaction requirement justifies a different value.
- Lock a drag to its initial dominant axis before applying interactive movement; vertical scrolling and horizontal navigation must not unexpectedly trigger each other.
- Do not change `allowsHitTesting` from transient gesture state. A control that receives touch-down must remain in the hit-test hierarchy until that interaction ends.
- Compose competing gestures deliberately with SwiftUI simultaneous, exclusive, or sequenced gesture APIs; document any UIKit recognizer bridge.
- Provide a visible control for every gesture-only navigation action and preserve VoiceOver escape or dismissal behavior.
- Verify stationary taps, taps with natural finger jitter, vertical scrolling, slow drags, fast swipes, diagonal movement, cancellation, VoiceOver, and Reduce Motion before considering an interaction complete.

## Simulator UI Validation

- Use Computer Use screen recording and accessibility control for routine local Simulator interaction testing when available; the workspace owner has authorized this validation and no repeated permission request is needed.
- This authorization covers local app navigation, taps, drags, scrolling, text entry with mock data, screenshots, and visual inspection. It does not override confirmation requirements for credentials, sensitive data, destructive actions, purchases, or external communication.
- Do not treat a successful build or static screenshot as proof that an interactive behavior works. Exercise the relevant controls and gestures in the running app.
- When Computer Use and the user's live Simulator result disagree, treat the user's live result as authoritative and change the implementation or validation method accordingly.
- Record which interactions were actually exercised and distinguish them from code inspection or build-only verification.

## UI Validation Efficiency

- Validate in this order: focused code or model checks, target build, Computer Use interaction, then the narrowest relevant UI test.
- Do not rerun an expensive UI test after each speculative patch. Group fixes that follow from one evidence-backed diagnosis.
- After a UI test fails, inspect its failure line, `xcresult` activities, attachments, screen recording, accessibility snapshot, and control frame before changing code or rerunning it.
- After two expensive UI-test failures, stop rerunning and perform a full diagnostic checkpoint. State a new evidence-backed hypothesis before another run.
- Confirm synthesized events hit the visible system control, and re-query `XCUIElement` after SwiftUI structural or state transitions.
- Aim for one final UI-test run and normally no more than two runs after implementation; report build, automation, Computer Use, and inspection evidence separately.

## Project Drawer Scrolling

- Keep the project drawer's project and session list vertically scrollable, but stop immediately at its content boundaries without elastic overscroll.
- Scope bounce configuration to the project drawer list. Do not change global scroll appearance or add drag gestures that compete with row taps, vertical scrolling, or the workspace's horizontal navigation gesture.

## Diagnostics

- Record operational telemetry through the typed `Diagnostics` event pipeline so Apple Unified Logging and bounded JSONL stay aligned.
- Use stable event names and allowlisted `DiagnosticField` values. Never log prompts, responses, transcript or console content, credentials, Relay URLs, authorization headers, full paths, serial numbers, or permanent device identifiers.
- Correlate Relay work with `traceID`; pass raw Turn IDs only to `Diagnostics`, which stores a session-scoped hash reference.
- Log error domains and numeric codes instead of localized descriptions. Rate-limit events emitted from loops, streaming deltas, retries, and resource-pressure paths.
- When adding or changing diagnostic events, update `docs/diagnostics.md`, schema or rotation tests, the collection/summary scripts when applicable, and the Unreleased changelog.
