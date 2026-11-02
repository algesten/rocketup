# Xcode Cloud releases

Rocket Up uses `RocketUp.xcodeproj`, the shared `RocketUp` scheme, and automatic signing for team `JUB99UJD56`.

| Workflow | Start condition | Action |
| --- | --- | --- |
| Default | Changes to `main` | Build macOS |
| Release (tag) | Tags beginning with `v` | Archive macOS, TestFlight and App Store |

The release workflow uses Xcode 27.1 and macOS 27.0.1, matching Grabbler. Cloud runs the search and release-version checks after cloning. Its pre-build hook uses `CI_BUILD_NUMBER` for the build number and the tag, without its `v`, for the marketing version. Tags must contain three numeric components, such as `v0.2.1`.

After the release commit is pushed and its checks pass, create and push a tag:

```sh
git tag v0.2.1
git push origin v0.2.1
```

Check the archive in Xcode Cloud or App Store Connect. After Apple processes it, select the build for the matching App Store version, complete the listing, and submit it for review. A tag or uploaded build does not publish the app. Download the archive and symbols for safekeeping.

The App Store listing still needs configuration. The read-only home-relative temporary exception must be explained in App Store Connect, including a Feedback Assistant issue number; its acceptance is subject to App Review.
