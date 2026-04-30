# CodexMenuBar Status Center Expansion

## Goal

Expand CodexMenuBar from a compact active-turn popover into a richer native macOS status center while preserving a stable menu bar item.

## Current App Facts

- Shell: `NSStatusItem` + transient `NSPopover`, with a right-click context menu and Settings window.
- Transport: one Unix domain socket connection to `codexd`, JSON-lines messages, `codexd/snapshot`, then `codexd/subscribe`.
- State: in-memory endpoint, active-turn, progress, token, plan, file, command, error, rate-limit, and recent-run summaries.
- Existing rendering: one row per endpoint, expandable active turn details, token/timeline bars, plan, file/command summaries, recent completed runs, Finder/Terminal actions.
- Existing controls: reconnect, Quick Start terminal launch, Settings, Quit, open terminal for a working directory.

## `codexd` Deep-Dive Findings

### Supplied By `codexd`

- Local daemon over an AF_UNIX socket at `$CODEX_HOME/runtime/codexd/codexd.sock` unless overridden.
- User-only socket permissions: parent directory `0700`, socket `0600`.
- JSON-lines protocol:
  - requests: optional `id`, `method`, `params`;
  - responses: `{ id, result }` or `{ id, error }`;
  - notifications: `{ method, params }`;
  - no required `jsonrpc` version field.
- Consumer methods:
  - `codexd/snapshot` returns `{ seq, runtimes }`;
  - `codexd/subscribe` accepts optional `afterSeq` and returns current `seq`.
- Event stream:
  - notifications use `codexd/event`;
  - each event has a global monotonic `seq`;
  - bounded in-memory replay keeps the latest 1024 events;
  - event payloads are `runtimeUpsert`, `runtimeRemoved`, and `runtimeNotification`.
- Runtime producer methods:
  - `codexd/runtime/register`;
  - `codexd/runtime/updateMetadata`;
  - `codexd/runtime/event`;
  - `codexd/runtime/unregister`.
- Runtime snapshot fields:
  - `runtimeId`, `pid`, `sessionSource`, `cwd`, `displayName`, `activeTurns`;
  - each active turn has only `threadId` and `turnId`.
- `codexd` itself only interprets `turn/started` and `turn/completed` to maintain `activeTurns`; every other runtime notification is forwarded as opaque payload.
- Producer behavior:
  - reconnects to the daemon socket;
  - registers metadata on connect;
  - queues pending JSON lines while disconnected;
  - caps queued pending lines at 4096.
- Current publishers:
  - `app-server` publishes selected `ServerNotification` variants to `codexd`;
  - the TUI bridge publishes synthetic menu-bar notifications for CLI sessions;
  - runtime IDs are currently process-based (`pid:<pid>`), with `sessionSource` such as `appServer` or `cli`.

### Current Limitations For Rich UI

- `codexd/snapshot` cannot reconstruct prompt preview, model, plan, command, file, token, error, or timeline details after reconnect; it only gives runtime metadata and active turn IDs.
- Event replay is in-memory and bounded; missed events beyond the last 1024 are unrecoverable.
- Recent-run history exists only in CodexMenuBar memory.
- Daemon restarts lose runtime state until producers reconnect and publish new events.
- There is no consumer-to-runtime control path for interrupt, pause, continue, approval, or starting turns.
- Several app-server notification types that would enable richer detail panes are not relayed to `codexd` today, especially streaming deltas and diff updates.
- The app currently parses loose `[String: Any]` dictionaries; there is no typed Swift event contract.

## Expansion Strategy

### Phase 1: Use Existing `codexd` Fully

No daemon protocol changes.

- Split transport from event reduction:
  - keep `AppServerClient` focused on socket, reconnect, snapshot, subscribe, sequencing;
  - move notification decoding/reduction into a dedicated model layer.
- Add typed Swift models for known `codexd` envelopes and forwarded notifications.
- Keep unknown forwarded notifications visible in a debug/event-log model instead of silently losing them.
- Improve the popover as an active status surface:
  - compact header with connection, daemon, active turn count, runtime count, and rate-limit state;
  - group endpoints by working directory and `sessionSource`;
  - expose stable row states for idle, running, failed, reconnecting, and stale data;
  - keep rich details in accordion sections already proven in `TurnMenuRowView`.
- Add a daemon health/settings section:
  - resolved socket path;
  - last connected time;
  - last event sequence;
  - launch-agent status text when available;
  - reconnect and Quick Start actions.
- Persist only app preferences, not runtime history, in this phase.

### Phase 2: Add A Persistent Status Window

Requires careful macOS UI separation, but not necessarily immediate daemon changes.

- Keep the popover quick and transient.
- Add a normal window for workflows that should survive focus changes:
  - sidebar: runtimes/projects;
  - content list: active and recent turns;
  - detail: timeline, plan, files, commands, token usage, errors;
  - inspector: runtime metadata, socket, rate limits, raw event diagnostics.
- Use the app’s current in-memory summaries for the first implementation.
- Treat app-local history as best effort until daemon replay/snapshot support exists.
- Add toolbar search/filter for cwd, runtime source, turn status, and item type.

### Phase 3: Require `codexd` Expansion

Use this phase for features that must survive app reconnects or send actions back to Codex runtimes.

- Durable or refreshable status snapshots for active turns and recent completed turns.
- Rich item state for command output, file diffs, reasoning summaries, plan updates, and streaming text.
- Runtime capabilities and protocol version discovery.
- Consumer-to-runtime command routing for interrupt, pause, continue, approvals, and thread/turn reads.
- Persistent event replay or a runtime resync method that closes gaps after missed events.

Track daemon-side work in `codex-rs/codexd/docs/dev_plans/menubar_status_hub_prerequisites.md`.

## UI Shape

### Menu Bar Item

- Keep width stable.
- Use the template icon as the primary visual anchor.
- Show only compact status text:
  - active count when running;
  - short reconnecting marker;
  - short failure marker.
- Avoid long dynamic labels.

### Popover

- Purpose: quick glance and short actions.
- Keep transient dismissal.
- Show active and recently completed runs only when enough data is available.
- Keep controls to reconnect, open settings, Quick Start, open terminal, copy, and reveal files.

### Status Window

- Purpose: browsing, filtering, diagnostics, and multi-step workflows.
- Use a normal resizable window instead of increasing popover complexity.
- Prefer a native split-view layout:
  - left: runtime/project groups;
  - center: turn list;
  - right/detail: selected turn details and raw event diagnostics.

## Implementation Order

1. Introduce typed `codexd` envelope and forwarded notification decoding.
2. Move event reduction out of `AppDelegate` into focused reducers with unit tests.
3. Add fixture-driven reducer tests for current daemon snapshots and event streams.
4. Refine popover header, grouping, and empty/error states using existing data only.
5. Add the persistent status window backed by the same reducer state.
6. Add daemon health/status controls that do not mutate runtime work.
7. Gate control actions behind daemon/runtime capabilities from the daemon prerequisite plan.

## Implemented Slice

- The popover now shows daemon diagnostics from `codexd/hello` and snapshot/event sequencing:
  - protocol version;
  - last event sequence;
  - runtime count;
  - resolved socket path.
- A persistent Status Center window shows runtime navigation, selected turn details, and daemon diagnostics using the same state as the popover.
- The UI remains read-only for daemon/runtime state; control actions are still gated on future runtime capabilities.
- The daemon prerequisite plan has started with `codexd/hello`, summary-oriented `codexd/runtime/updateState`, and broader notification relay.

## Verification

- Unit tests for snapshot reconciliation, event replay, missed-event handling, and unknown notifications.
- UI fixtures for:
  - no daemon;
  - connected idle;
  - one active CLI runtime;
  - one active app-server runtime;
  - failed turn;
  - low rate limit;
  - reconnect after missed active-turn completion.
- Existing commands:
  - `./scripts/verify_fast.sh`;
  - `./scripts/e2e_codexd.sh`;
  - `./scripts/ui/ui_loop.sh --scheme CodexMenuBarUI --destination 'platform=macOS' --adhoc-signing --reuse-build --system-attachment-lifetime keepNever --sanitize-screenshots redact-suspect --delete-raw-attachments`.

## Prerequisite Decision

Daemon expansion is not required for the first app-side polish pass. It is a worthy prerequisite for the status window, durable history, reconnect correctness, detailed streaming panes, and runtime control actions.
