# Release Security

## Current Posture

- Local development builds are unsigned by default (`CODE_SIGNING_ALLOWED=NO`) so agents can build without keychain state.
- The Settings window exposes launch-at-login through `SMAppService.mainApp`; this requires a signed app bundle for successful registration.
- App Sandbox is not enabled for developer builds. The app needs local Unix-domain socket access under the user home directory and can open Terminal for Quick Start, so sandbox entitlements need a dedicated release pass before any Mac App Store path.
- Hardened Runtime is declared for the Release configuration. Developer ID notarization still requires a signed archive with local signing credentials.

## Release Gate Checks

1. Archive with Developer ID signing credentials and confirm Hardened Runtime remains enabled.
2. Decide whether the release channel is Developer ID or Mac App Store.
3. If App Sandbox is enabled, validate `codexd` socket access, Quick Start terminal launch, reconnect/error states, and permission-denied copy.
4. Run notarization packaging outside the agent build path and keep credentials out of the repo.
