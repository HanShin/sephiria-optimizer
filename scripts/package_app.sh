#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_CACHE_ROOT="${TMPDIR:-/tmp}/sephiria-optimizer-build"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_CACHE_ROOT/swiftpm-modules"

cd "$PROJECT_DIR"
swift build -c release --disable-sandbox --cache-path "$BUILD_CACHE_ROOT/swiftpm"
BIN_DIR="$(swift build -c release --disable-sandbox --cache-path "$BUILD_CACHE_ROOT/swiftpm" --show-bin-path)"

APP_DIR="$PROJECT_DIR/dist/Sephiria Optimizer.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/SephiriaOptimizer" "$MACOS_DIR/SephiriaOptimizer"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "$BIN_DIR/SephiriaOptimizer_SephiriaOptimizerApp.bundle" "$RESOURCES_DIR/"
cp "$PROJECT_DIR/Sources/SephiriaOptimizerApp/Resources/artifacts.json" "$RESOURCES_DIR/artifacts.json"
chmod +x "$MACOS_DIR/SephiriaOptimizer"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
