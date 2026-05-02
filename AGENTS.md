# CodexMenuBar (XcodeGen + SwiftPM)

## Quick commands

- Generate Xcode project: `./scripts/generate_xcodeproj.sh`
- Build: `./scripts/build.sh`
- Verify (sandboxed, auto Xcode/SwiftPM): `./scripts/verify_fast.sh`
- Run (Xcode): `open CodexMenuBar.xcodeproj`
- Run (SwiftPM): `swift run CodexMenuBar`
- Evidence run (agent-safe xcresult): `./scripts/ui/ui_loop.sh --scheme CodexMenuBarUI --destination 'platform=macOS' --adhoc-signing --reuse-build --system-attachment-lifetime keepNever --sanitize-screenshots keep --delete-raw-attachments`
- E2E codexd smoke (artifacts): `./scripts/e2e_codexd.sh`
- E2E codexd smoke using installed `codex`: `./scripts/e2e_codexd.sh --use-codex-on-path`

## Configuration

Check whether `config/external-projects.local.yaml` exists and has a valid `external_projects.codex.local_path` value pointing to a `codex` checkout. If not, check whether this repo is located inside a `codex` checkout (e.g. `../..` has a `codex` directory). If neither of those are true, stop and ask the human developer to either
- place this repo inside a `codex` checkout
- `cp config/external-projects.example.yaml config/external-projects.local.yaml` and point to a `codex` checkout.

The app also exposes a Settings window from the menu bar dropdown. Use it for session-only `codexd` socket overrides and macOS 26 menu-bar-visibility troubleshooting; launch-time env vars (`CODEXD_SOCKET_PATH`, `CODEX_HOME`) still define the default path.

UI tests use launch harnesses (`--start-screen Settings`, `--open-status-surface popover|context-menu`, `--fixture active-turn`). If macOS blocks XCUITest with an "XCTest is trying to Enable UI Automation" password prompt, preserve the `.xcresult`, capture attribution with `scripts/macos/tcc_attribution_tail.sh`, and treat manual screenshots as fallback evidence only until the OS permission is granted.

`AppDelegate` owns the programmatic main menu for standard macOS command shortcuts (`⌘W`, `⌘,`, edit commands, window commands). Keep new persistent windows on the responder chain so these shortcuts continue to work.

`AppDelegate` also owns the live status refresh timer. Keep it active while either the menu bar popover or the Status Center window is visible; Status Center stats must not depend on popover visibility.

The menu bar popover keeps global actions as icon buttons in the title row with `.help`/accessibility labels; keep idle popovers compact and resize active popovers from runtime count/expanded state instead of adding fixed footer chrome.

The Status Center sidebar is resizable when expanded and still switches runtimes through collapsed icon buttons. Preserve the centered `No Codex runtimes` detail empty state when no runtime is selected.

Icon assets: the app bundle icon is `Sources/CodexMenuBar/Resources/Assets.xcassets/AppIcon.appiconset`, generated from `Resources/svgs/codex-app.svg`; the menu bar template icon loads from `Resources/svgs/codex.svg`. Keep the SVGs valid when replacing icons, then regenerate the Xcode project.

## Sandboxed tests (macos-sandbox-testing)

Unit tests (SwiftPM and Xcode) are guarded by an in-process Seatbelt sandbox to prevent writes outside the workspace.

- Disable (escape hatch): `SEATBELT_SANDBOX_DISABLE=1 ./scripts/verify_fast.sh`
- Logs: `.build/macos-sandbox-testing/<run-id>/logs/events.jsonl`

## Formatting + hooks (prek)

This repo uses `prek` to run `.pre-commit-config.yaml` hooks for `CodexMenuBar/**`.

- One-time hook setup: `git config core.hooksPath .githooks && prek prepare-hooks`
- Run on all tracked files (scoped to `CodexMenuBar/**` by config): `prek run --all-files`

## Development plans

- App expansion plans live under `docs/dev_plans/`.
- Keep daemon prerequisite work aligned with `codex-rs/codexd/docs/dev_plans/` when a UI plan depends on new `codexd` protocol or runtime-control behavior.
- Release signing, App Sandbox, Hardened Runtime, notarization, and launch-at-login decisions live in `docs/release_security.md`.
