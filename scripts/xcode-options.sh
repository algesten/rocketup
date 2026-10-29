# Shared options for the local build and App Store archive scripts.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcode_options=(-project RocketUp.xcodeproj -scheme RocketUp -configuration Release
    -derivedDataPath .build/xcode -allowProvisioningUpdates)
if [[ -n "${ROCKETUP_VERSION:-}" ]]; then
    if [[ ! "$ROCKETUP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ROCKETUP_VERSION must have three numeric components." >&2
        exit 1
    fi
    xcode_options+=("MARKETING_VERSION=$ROCKETUP_VERSION")
fi
if [[ -n "${ROCKETUP_BUILD_NUMBER:-}" ]]; then
    if [[ ! "$ROCKETUP_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
        echo "ROCKETUP_BUILD_NUMBER must be a positive integer." >&2
        exit 1
    fi
    xcode_options+=("CURRENT_PROJECT_VERSION=$ROCKETUP_BUILD_NUMBER")
fi
