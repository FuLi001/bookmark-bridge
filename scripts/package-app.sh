#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/outputs/Bookmark Bridge.app"
EXTENSION_DIR="$ROOT/outputs/Bookmark Bridge Chrome Extension"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"

if [[ ! -d "$SDK" ]]; then
    SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

cd "$ROOT"
env CLANG_MODULE_CACHE_PATH="$ROOT/.swift-cache/clang" SDKROOT="$SDK" \
    swift build -c release --disable-sandbox --cache-path "$ROOT/.swift-cache"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/BookmarkBridge" "$APP_DIR/Contents/MacOS/BookmarkBridge"
cp -R "$ROOT/ChromeExtension" "$APP_DIR/Contents/Resources/ChromeExtension"
mkdir -p "$EXTENSION_DIR"
rsync -a --delete "$ROOT/ChromeExtension/" "$EXTENSION_DIR/"
cp "$ROOT/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
echo "$EXTENSION_DIR"
