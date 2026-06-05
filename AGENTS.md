# CodexMenuBar (XcodeGen + SwiftPM)

## Quick commands

- Generate Xcode project: `./scripts/generate_xcodeproj.sh`
- Build: `./scripts/build.sh`
- Verify (sandboxed, auto Xcode/SwiftPM): `./scripts/verify_fast.sh`
- Run (Xcode): `open CodexMenuBar.xcodeproj`
- Run (SwiftPM): `swift run CodexMenuBar`
- Evidence run (agent-safe xcresult): `./scripts/ui/ui_loop.sh --scheme CodexMenuBarUI --destination 'platform=macOS' --adhoc-signing --reuse-build --system-attachment-lifetime keepNever --sanitize-screenshots keep --delete-raw-attachments`
- E2E codexd smoke
  - using installed `codex`, preferred when available and no `codex` code changes: `./scripts/e2e_codexd.sh --use-codex-on-path`
  - build `codex` from source: `./scripts/e2e_codexd.sh`

## Configuration

Check whether `config/external-projects.local.yaml` exists and has a valid `external_projects.codex.local_path` value pointing to a `codex` checkout. If not, check whether this repo is located inside a `codex` checkout (e.g. `../..` has a `codex` directory). If neither of those are true, stop and ask the human developer to either
- place this repo inside a `codex` checkout
- `cp config/external-projects.example.yaml config/external-projects.local.yaml` and point to a `codex` checkout.

The app also exposes a Settings window from the menu bar dropdown. Use it for session-only `codexd` socket overrides and macOS 26 menu-bar-visibility troubleshooting; launch-time env vars (`CODEXD_SOCKET_PATH`, `CODEX_HOME`) still define the default path.

UI tests use launch harnesses (`--start-screen Settings`, `--open-status-surface popover|context-menu`, `--fixture active-turn|delegate-turn|completed-turn-history|post-turn-review-lifecycle`). Focus runs by suite with `--only-testing CodexMenuBarUITests/<Class>`; the UI suites are `StatusPopoverUITests`, `StatusContextMenuUITests`, `StatusCenterWindowUITests`, `StatusCenterPromptHistoryUITests`, `StatusCenterTokenUsageUITests`, `StatusCenterCompletedTurnUITests`, and `SettingsWindowUITests`. If macOS blocks XCUITest with an "XCTest is trying to Enable UI Automation" password prompt, preserve the `.xcresult`, capture attribution with `scripts/macos/tcc_attribution_tail.sh`, and treat manual screenshots as fallback evidence only until the OS permission is granted.

`AppDelegate` owns the programmatic main menu for standard macOS command shortcuts (`⌘W`, `⌘,`, edit commands, window commands). Keep new persistent windows on the responder chain so these shortcuts continue to work.

`AppDelegate` also owns the live status refresh timer. Keep it active while either the menu bar popover or the Status Center window is visible; Status Center stats must not depend on popover visibility.

The menu bar popover keeps global actions as icon buttons in the title row with `.help`/accessibility labels; keep idle popovers compact and resize active popovers from runtime count/expanded state instead of adding fixed footer chrome.

The Status Center sidebar starts compact, is resizable when expanded, restores the last expanded width after collapse/expand, and still switches runtimes through collapsed icon buttons. Preserve the centered `No Codex runtimes` detail empty state when no runtime is selected.

The app normally runs with accessory activation policy, but switches to regular activation while the Status Center window is open so the window has a Dock icon. Revert to accessory only when the Status Center closes.

Runtime detail panes keep interactive history controls compact: active and completed prompts default to the first five logical prompt lines, expand/refold inline, and copy the full prompt; turn token usage browses newest/older samples across current-turn rounds and completed turns, each expanded completed turn browses its own round history, folded completed turns show aggregate per-turn token totals from codexd cumulative `tokenUsage.total` deltas when available, including active-turn `tokenUsageBaseline` snapshots on reconnect, so context compaction does not under-count and prior same-thread turns do not over-count, thread token usage is the latest codexd per-thread total, and session token usage aggregates the latest thread totals for the runtime session. Token history excludes total-only context estimates; codexd `runtimeUpsert` snapshots replay active turns before forwarded notifications, so token round seeding must stay idempotent. Active and completed turn identity is keyed by codexd `turnKey`/thread before legacy turn id so delegate turns do not inherit regular-turn token history; post-turn review runtime turn ids can be child-session ids such as `0`, not `post-turn-review-*`; token updates may arrive keyed only by `turnKey`, completion events may carry direct `promptPreview` metadata that must patch archived runs, and completion events without an explicit thread must not fall back to endpoint metadata after the active turn has expired. Long plan, file, command, completed-turn, and expanded-run histories page instead of silently truncating; completed-turn pages start newest-first.

Icon assets: the app bundle icon is `Sources/CodexMenuBar/Resources/Assets.xcassets/AppIcon.appiconset`, generated from `Resources/svgs/codex-app.svg`; the menu bar template icon loads from `Resources/svgs/codex.svg`. Keep the SVGs valid when replacing icons, then regenerate the Xcode project.

## Sandboxed tests (macos-sandbox-testing)

Unit tests (SwiftPM and Xcode) are guarded by an in-process Seatbelt sandbox to prevent writes outside the workspace.

- Disable (escape hatch): `SEATBELT_SANDBOX_DISABLE=1 ./scripts/verify_fast.sh`
- Logs: `.build/macos-sandbox-testing/<run-id>/logs/events.jsonl`

## Formatting + hooks (prek)

This repo uses `prek` to run `.pre-commit-config.yaml` hooks for `CodexMenuBar/**`.

- One-time hook setup: `git config core.hooksPath .githooks && prek prepare-hooks`

## Development plans

- App expansion plans live under `docs/dev_plans/`.
- Keep daemon prerequisite work aligned with `codex-rs/codexd/docs/dev_plans/` when a UI plan depends on new `codexd` protocol or runtime-control behavior.
- Release signing, App Sandbox, Hardened Runtime, notarization, and launch-at-login decisions live in `docs/release_security.md`.
