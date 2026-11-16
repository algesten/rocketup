#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B Tests/DependencyChecks.py
workdir="$(mktemp -d "${TMPDIR:-/tmp}/rocketup-calculator.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT
cp Tests/CalculatorChecks.swift "$workdir/main.swift"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$workdir/cache"
xcrun swiftc -swift-version 5 Sources/RocketUp/Calculator.swift Sources/RocketUp/Vendor/Expression.swift "$workdir/main.swift" -o "$workdir/check"
"$workdir/check"
