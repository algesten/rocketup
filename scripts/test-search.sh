#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
workdir="$(mktemp -d "${TMPDIR:-/tmp}/rocketup-tests.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT
sed '/^final class Index/,$d' Sources/RocketUp/main.swift > "$workdir/Search.swift"
cp Tests/SearchChecks.swift "$workdir/main.swift"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$workdir/cache}"
xcrun swiftc -swift-version 5 "$workdir/Search.swift" "$workdir/main.swift" -o "$workdir/check"
"$workdir/check"
