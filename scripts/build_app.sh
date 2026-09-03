#!/bin/bash
set -euo pipefail

echo "========================================"
echo " Building Liveflow.app for macOS"
echo "========================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

# 1. Ensure ICNS exists, generate if needed
if [ ! -f "$ROOT_DIR/native/LiveflowIcon.icns" ]; then
    echo "Generating app icon..."
    swift "$ROOT_DIR/scripts/generate_icon.swift"
fi

CONFIG="${1:-release}"
echo "Building target (configuration: $CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$ROOT_DIR/.build/$CONFIG/Liveflow"
APP_BUNDLE="$ROOT_DIR/build/Liveflow.app"
APPLICATIONS_APP="/Applications/Liveflow.app"

CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/Liveflow"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/native/LiveflowIcon.icns" "$RESOURCES_DIR/LiveflowIcon.icns"

echo "Signing application bundle with stable designated requirement..."
codesign --force --deep --sign - --requirements '=designated => identifier "com.freevian.liveflow"' --entitlements "$ROOT_DIR/Liveflow.entitlements" "$APP_BUNDLE"

echo "Deploying and replacing to /Applications/Liveflow.app..."
rm -rf "$APPLICATIONS_APP"
cp -R "$APP_BUNDLE" "$APPLICATIONS_APP"
codesign --force --deep --sign - --requirements '=designated => identifier "com.freevian.liveflow"' --entitlements "$ROOT_DIR/Liveflow.entitlements" "$APPLICATIONS_APP"
touch "$APPLICATIONS_APP"

echo "========================================"
echo " Successfully created: $APP_BUNDLE"
echo " Successfully deployed to: $APPLICATIONS_APP"
echo "========================================"
