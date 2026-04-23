# CodexMenuBar

`CodexMenuBar` is a standalone macOS menu bar companion app, resident as a sub-repo in the [`zhutao100/codex`](https://github.com/zhutao100/codex) project, and depends on customized
- `codexd`,  Unix domain socket + JSON-lines protocol
- `codex-app-server`

It connects to a single local `codexd` daemon, and renders authoritative active turn state in the menu bar dropdown.

## Features

- Menu bar icon state for connected/running/error.
- One row per active turn.
- Terminal-style progress semantics:
  - working status
  - elapsed timer
  - trace legend categories
  - indeterminate progress bar while running

## Build

```shell
./scripts/build.sh
```

## Xcode project

This repo includes a generated Xcode project (`CodexMenuBar.xcodeproj`) driven by `project.yml`.

If you edit `project.yml`, regenerate with:

```shell
./scripts/generate_xcodeproj.sh
```

## Run

### Start `codexd`

If `codexd` is already running (for example, via the launch agent), you can skip this step.

From this repo:

```shell
cd ../codex-rs
cargo run -p codex-cli -- app-server codexd run
```

If you have a `codex` binary installed:

```shell
codex app-server codexd run
```

### Start the menu bar app

```shell
open CodexMenuBar.xcodeproj
```

Or (SwiftPM):

```shell
swift run CodexMenuBar
```

By default, the app connects to `~/.codex/runtime/codexd/codexd.sock`.

Socket overrides:

- `CODEXD_SOCKET_PATH` (preferred): connect to that exact socket path (supports `~` expansion).
- `CODEX_HOME`: connect to `$CODEX_HOME/runtime/codexd/codexd.sock` (supports `~` expansion).
- The menu bar dropdown now exposes `Settings`, which can apply a session-only socket-path override and reconnect without relaunching the app.

Example:

```shell
CODEXD_SOCKET_PATH=/tmp/codexd.sock swift run CodexMenuBar
```

The Settings window also includes a macOS 26 visibility note: if the status item is hidden, enable `CodexMenuBar` under `System Settings -> Menu Bar`.

When connected, the app subscribes to:

- `turn/started`
- `turn/completed`
- `turn/progressTrace`

It also uses `item/started` and `item/completed` as a fallback to synthesize trace categories if needed.

`codexd` receives runtime updates from Codex runtimes and provides:

- `codexd/snapshot` for current state.
- `codexd/event` notifications for live changes.

If the menu bar disconnects, it reconnects and re-fetches snapshot state before resubscribing.

## Verify

- Xcode build + unit tests (low-noise logs): `scripts/verify_fast.sh`
- Evidence run (`.xcresult`): `scripts/ui/ui_loop.sh --scheme CodexMenuBar --destination 'platform=macOS'`
- `codexd` end-to-end smoke: `scripts/e2e_codexd.sh`

Notes:

- Unit tests are guarded by an in-process Seatbelt sandbox; set `SEATBELT_SANDBOX_DISABLE=1` to bypass.
- For `scripts/ui/ui_loop.sh`, set `VERBOSE=1` to stream full `xcodebuild` output.

## Configuration

This repo supports optional local configuration under the `config/` directory. The important file for developer workflows is:

- `config/external-projects.local.yaml` — (git-ignored) local overrides for external projects used by scripts.

`scripts/e2e_codexd.sh` looks for `external_projects->codex->local_path` inside this file to locate a developer-built `codex` checkout. If the file or value is missing the script will print a warning and fall back to the repository parent directory.

`cp config/external-projects.example.yaml config/external-projects.local.yaml` and update the `local_path`.
