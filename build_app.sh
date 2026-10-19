set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/QuickShareMac.app"
CONFIG="${CONFIG:-release}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

echo "Building QuickShareMac ($CONFIG)…"
swift build --package-path "$ROOT" -c "$CONFIG"

BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/QuickShareMac"
if [[ ! -x "$BIN" ]]; then
  echo "Binary not found at $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QuickShareMac"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/AppIcon.icns" ]]; then
  cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

for f in LICENSE NOTICE; do
  if [[ -f "$ROOT/$f" ]]; then
    cp "$ROOT/$f" "$APP/Contents/Resources/$f"
  fi
done

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null
  echo "Signed with: $IDENTITY"
else
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad-hoc (notifications may be unavailable on macOS 26+)"
fi
echo "Created $APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/QuickShareMac.zip"
echo "Created $ROOT/QuickShareMac.zip"

rm -f "$ROOT/QuickShareMac.dmg"
hdiutil create -quiet -volname "Quick Share" -srcfolder "$APP" -ov -format UDZO \
  "$ROOT/QuickShareMac.dmg"
echo "Created $ROOT/QuickShareMac.dmg"
