#!/bin/bash
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
./scripts/test-search.sh
