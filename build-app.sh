#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD_CACHE="$ROOT/.build-cache"
mkdir -p "$BUILD_CACHE/clang" "$BUILD_CACHE/swiftpm"
CLANG_MODULE_CACHE_PATH="$BUILD_CACHE/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_CACHE/clang" \
swift build -c release --package-path "$ROOT" --cache-path "$BUILD_CACHE/swiftpm"

APP="$ROOT/dist/Montclair.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Montclair" "$APP/Contents/MacOS/Montclair"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

xcrun swift "$ROOT/Scripts/make-icon.swift" "$ROOT/Assets/Montclair-M-source.png" "$ROOT/Assets/Montclair-M-square.png"

ICONSET="$BUILD_CACHE/Montclair.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ROOT/Assets/Montclair-M-square.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Montclair.icns"
cp "$ROOT/Assets/Montclair-M-square.png" "$APP/Contents/Resources/MontclairLogo.png"
cp "$ROOT/Assets/Montclair-Homepage-Normal.png" "$APP/Contents/Resources/MontclairHomepageNormal.png"
cp "$ROOT/Assets/Montclair-Homepage-Private.png" "$APP/Contents/Resources/MontclairHomepagePrivate.png"
codesign --force --deep --sign - "$APP"
echo "$APP"
