# Rocket Up

A native macOS 27 app launcher. It runs without a Dock icon and shows a menu bar icon by default. Press ⌘\ to open it; use ⌘, in the launcher or the menu bar menu to change the shortcut, toggle the menu bar icon, or enable launch at login. If a shortcut is assigned to macOS, release it in System Settings before assigning it here. Quit using Force Quit.

Searches app bundles in `/Applications`, `/System/Applications`, and `~/Applications`, including subfolders. The sandbox uses a read-only home-relative temporary exception for `~/Applications`. Search ranks exact names, full-name prefixes, later word prefixes, then initials; space and punctuation insensitive matching is a fallback. Changes are observed with filesystem events. Everything stays local.

Build a signed local app with `./scripts/build-app.sh`, or open `RocketUp.xcodeproj` in Xcode. The project uses the Taglab team, the `com.taglab.rocketup` identifier, and the App Sandbox. `./scripts/test-search.sh` checks matching; `./scripts/test-integration.sh` checks discovery and notifications inside a development-signed sandbox and briefly displays the launcher. Set `ROCKETUP_CHECK_LAUNCH=1` on that test to check launching Calculator. The latter closes Calculator afterward only if it was not already running.

For App Store releases, `./scripts/build-app-store.sh` archives and exports with automatic signing; `--upload` uploads the archive. Xcode Cloud lifecycle scripts run search checks and set the build number and tagged release version. The Cloud workflow and App Store Connect listing still need configuration. The read-only home-relative temporary exception must be explained in App Store Connect, including a Feedback Assistant issue number, and its acceptance is subject to App Review.

The results panel resizes over 200 ms; search computation alone has been measured in the integration test. Display selection currently uses AppKit's main screen and has not been verified against Spotlight on multiple monitors.
