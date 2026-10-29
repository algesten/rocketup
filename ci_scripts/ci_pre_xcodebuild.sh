#!/bin/bash
set -euo pipefail
repo_path="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

# A test-without-building action can reuse artifacts without a source checkout.
version_file="$repo_path/Configuration/Version.xcconfig"
if [[ ! -f "$version_file" ]]; then
    if [[ ! -d "$repo_path/RocketUp.xcodeproj" ]]; then
        echo "Reusing the versioned build artifact without a source checkout."
        exit 0
    fi
    echo "Missing Configuration/Version.xcconfig." >&2
    exit 1
fi

if [[ ! "${CI_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Xcode Cloud must supply a positive CI_BUILD_NUMBER." >&2
    exit 1
fi
release_tag="${CI_TAG:-}"
release_version="${release_tag#v}"
if [[ -n "$release_tag" && ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Release tags must be versions such as 0.2.1 or v0.2.1." >&2
    exit 1
fi

python3 - "$version_file" "$CI_BUILD_NUMBER" "$release_version" <<'PY'
from pathlib import Path
import re
import sys

path, build, version = sys.argv[1:]
config = Path(path).read_text()
config, count = re.subn(r"(?m)^CURRENT_PROJECT_VERSION\s*=.*$", f"CURRENT_PROJECT_VERSION = {build}", config)
if count != 1:
    raise SystemExit("Expected one CURRENT_PROJECT_VERSION in Version.xcconfig.")
if version:
    config, count = re.subn(r"(?m)^MARKETING_VERSION\s*=.*$", f"MARKETING_VERSION = {version}", config)
    if count != 1:
        raise SystemExit("Expected one MARKETING_VERSION in Version.xcconfig.")
Path(path).write_text(config)
print(config, end="")
PY
