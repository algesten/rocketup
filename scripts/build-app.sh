#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
identity="${ROCKETUP_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')}"
if [[ -z "$identity" ]]; then echo 'A development signing identity is required.' >&2; exit 1; fi
xcodebuild -quiet -project RocketUp.xcodeproj -scheme RocketUp -configuration Release -derivedDataPath .build/xcode -destination 'platform=macOS' CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
codesign --verify --deep --strict .build/xcode/Build/Products/Release/RocketUp.app
mkdir -p dist
rm -rf dist/RocketUp.app
ditto .build/xcode/Build/Products/Release/RocketUp.app dist/RocketUp.app
printf 'Built %s/dist/RocketUp.app\n' "$PWD"
