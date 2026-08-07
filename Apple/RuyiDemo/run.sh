#!/usr/bin/env bash
# CLI fallback: build SPM executable, wrap into a proper .app, then launch.
# Preferred: open RuyiDemo.xcodeproj, scheme RuyiDemo-macOS, press Run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
PRODUCT=".build/${CONFIG}/RuyiDemo"
BUNDLE_NAME="RuyiDemo_RuyiDemo.bundle"
APP_DIR=".build/${CONFIG}/RuyiDemo.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"

swift build -c "$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$PRODUCT" "$MACOS_DIR/RuyiDemo"
cp -R ".build/${CONFIG}/${BUNDLE_NAME}" "$MACOS_DIR/"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc sign so LaunchServices accepts the bundle cleanly.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Launching ${APP_DIR}"
open "$APP_DIR"
