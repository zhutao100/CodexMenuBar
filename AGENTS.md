# CodexMenuBar (SwiftPM)

## Quick commands

- Build: `./scripts/build.sh`
- Test (sandboxed): `swift test`
- Run: `swift run CodexMenuBar`
- Fast verify (logs to `.artifacts/`): `scripts/verify_fast.sh`
- Evidence run (xcresult): `scripts/ui/ui_loop.sh --scheme CodexMenuBar --destination 'platform=macOS'`
- E2E codexd smoke (artifacts): `scripts/e2e_codexd.sh`

## Configuration

Check whether `config/external-projects.local.yaml` exists and has a valid `external_projects.codex.local_path` value pointing to a `codex` checkout. If not, check whether this repo is located inside a `codex` checkout (e.g. `../..` has a `codex` directory). If neither of those are true, stop and ask the human developer to either
- place this repo inside a `codex` checkout
- `cp config/external-projects.example.yaml config/external-projects.local.yaml` and point to a `codex` checkout.

## Sandboxed tests (macos-sandbox-testing)

`swift test` is guarded by an in-process Seatbelt sandbox to prevent writes outside the workspace.

- Disable (escape hatch): `SEATBELT_SANDBOX_DISABLE=1 swift test`
- Logs: `CodexMenuBar/.build/macos-sandbox-testing/<run-id>/logs/events.jsonl`

## Formatting + hooks (prek)

This repo uses `prek` to run `.pre-commit-config.yaml` hooks for `CodexMenuBar/**`.

- One-time hook setup: `git config core.hooksPath .githooks && prek prepare-hooks`
- Run on all tracked files (scoped to `CodexMenuBar/**` by config): `prek run --all-files`
