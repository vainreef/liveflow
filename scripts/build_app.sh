#!/bin/bash
set -euo pipefail

echo "========================================"
echo " Building Livestreamer.app for macOS"
echo "========================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

# 1. Ensure ICNS exists, generate if needed
if [ ! -f "$ROOT_DIR/native/LivestreamerIcon.icns" ]; then
    echo "Generating app icon..."
    swift "$ROOT_DIR/scripts/generate_icon.swift"
fi

CONFIG="${1:-release}"
echo "Building target (configuration: $CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$ROOT_DIR/.build/$CONFIG/Livestreamer"
APP_BUNDLE="$ROOT_DIR/build/Livestreamer.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/Livestreamer"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/native/LivestreamerIcon.icns" "$RESOURCES_DIR/LivestreamerIcon.icns"

echo "Signing application bundle..."
codesign --force --deep --sign - --entitlements "$ROOT_DIR/Livestreamer.entitlements" "$APP_BUNDLE"

# Refresh Finder / Dock icon cache for the bundle
touch "$APP_BUNDLE"

echo "========================================"
echo " Successfully created: $APP_BUNDLE"
echo "========================================"
