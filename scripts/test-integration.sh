#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
workdir="$(mktemp -d "${TMPDIR:-/tmp}/rocketup-integration.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT
sed '/^let app = NSApplication.shared/,$d' Sources/RocketUp/main.swift > "$workdir/Core.swift"
cp Tests/Integration.swift "$workdir/main.swift"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$workdir/cache"
mkdir -p "$workdir/Integration.app/Contents/MacOS"
xcrun swiftc -swift-version 5 "$workdir/Core.swift" Sources/RocketUp/Shortcut.swift "$workdir/main.swift" -o "$workdir/Integration.app/Contents/MacOS/Integration"
cat > "$workdir/Integration.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Integration</string><key>CFBundleIdentifier</key><string>com.taglab.rocketup.integration</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST
identity="${ROCKETUP_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')}"
if [[ -z "$identity" ]]; then echo 'A development signing identity is required.' >&2; exit 1; fi
codesign --force --sign "$identity" --entitlements Sources/RocketUp/App.entitlements "$workdir/Integration.app"
"$workdir/Integration.app/Contents/MacOS/Integration"
