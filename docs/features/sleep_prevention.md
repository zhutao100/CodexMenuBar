# Automatic sleep prevention

## Behavior

- Disabled by default and persisted in `UserDefaults`.
- Starts only while `codexd` is connected and at least one runtime has an in-progress turn.
- Stops when the last turn completes, pauses, fails, or is interrupted; also stops on disconnect and app termination.
- Default mode prevents idle system sleep while allowing display sleep.
- Optional display mode prevents idle display sleep too.
- Manual sleep, lid closure, low-battery sleep, and other non-idle sleep causes remain available.

## Implementation

- `ProcessInfoSleepPreventionManager` owns the `ProcessInfo.beginActivity` token.
- `AutomaticSleepPreventionController` applies connection, preference, and active-session policy without coupling it to SwiftUI.
- `AppDelegate` refreshes policy after authoritative codexd and Settings changes.
- Mode changes acquire the replacement activity before releasing the prior token.

## Verification

- Unit tests cover start, mode change, disable, disconnect, and zero-active-session transitions.
- `SettingsWindowUITests` checks the Settings controls and `pmset -g assertions`.
- The `active-turn` UI fixture supports `--pause-active-fixture-after <seconds>` for deterministic release verification.
