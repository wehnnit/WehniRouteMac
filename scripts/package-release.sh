#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
APP="$ROOT/dist/WehniRoute.app"
OUT="$ROOT/dist/releases"
ARCHIVE="$OUT/WehniRoute-$VERSION.zip"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must be semver, got: $VERSION" >&2
    exit 1
fi

bash "$ROOT/scripts/build-app.sh"

codesign --verify --deep --strict "$APP"
xattr -cr "$APP"

rm -rf "$OUT"
mkdir -p "$OUT"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

echo "Created:"
ls -lh "$ARCHIVE" "$ARCHIVE.sha256"
echo "SHA256: $(cut -d' ' -f1 "$ARCHIVE.sha256")"
