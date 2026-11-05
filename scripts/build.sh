#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
app="dist/PyLabNative.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -parse-as-library   Sources/*.swift -o "$app/Contents/MacOS/PyLabNative"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/kernel_bridge.py Resources/workspace_actions.py "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s/%s\n' "$PWD" "$app"
