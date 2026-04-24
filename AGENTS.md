# CodexMenuBar (XcodeGen + SwiftPM)

## Quick commands

- Generate Xcode project: `./scripts/generate_xcodeproj.sh`
- Build: `./scripts/build.sh`
- Verify (sandboxed, auto Xcode/SwiftPM): `./scripts/verify_fast.sh`
- Run (Xcode): `open CodexMenuBar.xcodeproj`
- Run (SwiftPM): `swift run CodexMenuBar`
- Evidence run (xcresult): `./scripts/ui/ui_loop.sh --scheme CodexMenuBarUI --destination 'platform=macOS' --adhoc-signing`
- E2E codexd smoke (artifacts): `./scripts/e2e_codexd.sh`
- E2E codexd smoke using installed `codex`: `./scripts/e2e_codexd.sh --use-codex-on-path`

## Configuration

Check whether `config/external-projects.local.yaml` exists and has a valid `external_projects.codex.local_path` value pointing to a `codex` checkout. If not, check whether this repo is located inside a `codex` checkout (e.g. `../..` has a `codex` directory). If neither of those are true, stop and ask the human developer to either
- place this repo inside a `codex` checkout
- `cp config/external-projects.example.yaml config/external-projects.local.yaml` and point to a `codex` checkout.

The app also exposes a Settings window from the menu bar dropdown. Use it for session-only `codexd` socket overrides and macOS 26 menu-bar-visibility troubleshooting; launch-time env vars (`CODEXD_SOCKET_PATH`, `CODEX_HOME`) still define the default path.

## Sandboxed tests (macos-sandbox-testing)

Unit tests (SwiftPM and Xcode) are guarded by an in-process Seatbelt sandbox to prevent writes outside the workspace.

- Disable (escape hatch): `SEATBELT_SANDBOX_DISABLE=1 ./scripts/verify_fast.sh`
- Logs: `.build/macos-sandbox-testing/<run-id>/logs/events.jsonl`

## Formatting + hooks (prek)

This repo uses `prek` to run `.pre-commit-config.yaml` hooks for `CodexMenuBar/**`.

- One-time hook setup: `git config core.hooksPath .githooks && prek prepare-hooks`
- Run on all tracked files (scoped to `CodexMenuBar/**` by config): `prek run --all-files`
