#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-options.sh

destination=export
case "${1:-}" in
    '') ;;
    --upload) destination=upload ;;
    *) echo "Usage: $0 [--upload]" >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [--upload]" >&2
    exit 1
fi

xcodebuild -quiet "${xcode_options[@]}" -destination 'generic/platform=macOS' \
    -archivePath dist/RocketUp.xcarchive archive

mkdir -p .build/store
cp Configuration/AppStoreExport.plist .build/store/ExportOptions.plist
/usr/libexec/PlistBuddy -c "Set :destination $destination" .build/store/ExportOptions.plist
xcodebuild -exportArchive -archivePath dist/RocketUp.xcarchive \
    -exportOptionsPlist .build/store/ExportOptions.plist \
    -exportPath dist/AppStore -allowProvisioningUpdates
