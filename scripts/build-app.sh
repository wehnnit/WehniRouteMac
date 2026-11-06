#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/WehniRoute.app"

echo "Building release binary…"
swift build -c release

echo "Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/WehniRoute" "$APP/Contents/MacOS/WehniRoute"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
codesign --verify --deep --strict "$APP"
