#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="1.0.1"
NAME="Bookmark Bridge $VERSION"
DIST_DIR="$ROOT/outputs/$NAME"
ZIP_PATH="$ROOT/outputs/$NAME.zip"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"

if [[ ! -d "$SDK" ]]; then
    SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

cd "$ROOT"

env CLANG_MODULE_CACHE_PATH="$ROOT/.swift-cache/clang" SDKROOT="$SDK" \
    swift build -c release --disable-sandbox --cache-path "$ROOT/.swift-cache" \
    --triple arm64-apple-macosx13.0

env CLANG_MODULE_CACHE_PATH="$ROOT/.swift-cache/clang-x86" SDKROOT="$SDK" \
    swift build -c release --disable-sandbox --cache-path "$ROOT/.swift-cache-x86" \
    --triple x86_64-apple-macosx13.0

rm -rf "$DIST_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$DIST_DIR/Bookmark Bridge.app/Contents/MacOS"
mkdir -p "$DIST_DIR/Bookmark Bridge.app/Contents/Resources"
mkdir -p "$DIST_DIR/Bookmark Bridge Chrome Extension"

lipo -create \
    "$ROOT/.build/arm64-apple-macosx/release/BookmarkBridge" \
    "$ROOT/.build/x86_64-apple-macosx/release/BookmarkBridge" \
    -output "$DIST_DIR/Bookmark Bridge.app/Contents/MacOS/BookmarkBridge"

cp "$ROOT/AppResources/Info.plist" "$DIST_DIR/Bookmark Bridge.app/Contents/Info.plist"
cp -R "$ROOT/ChromeExtension/." "$DIST_DIR/Bookmark Bridge.app/Contents/Resources/ChromeExtension/"
rsync -a --delete "$ROOT/ChromeExtension/" "$DIST_DIR/Bookmark Bridge Chrome Extension/"
cp "$ROOT/Distribution/使用说明.txt" "$DIST_DIR/使用说明.txt"

codesign --force --deep --sign - "$DIST_DIR/Bookmark Bridge.app"
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR" "$ZIP_PATH"

echo "$DIST_DIR"
echo "$ZIP_PATH"
