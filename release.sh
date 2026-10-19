set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
TAG="${1:-v$VERSION}"

if [[ "$TAG" != "v$VERSION" ]]; then
  echo "Tag $TAG does not match CFBundleShortVersionString ($VERSION)." >&2
  echo "Bump Info.plist first, or pass the matching tag." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty. Commit or stash changes before releasing." >&2
  git status --short >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

BUILD_ROOT="$(mktemp -d /tmp/quickshare-release.XXXXXX)"
trap 'rm -rf "$BUILD_ROOT"' EXIT
git archive HEAD | tar -x -C "$BUILD_ROOT"
(cd "$BUILD_ROOT" && ./build_app.sh)
cp "$BUILD_ROOT/QuickShareMac.zip" "$ROOT/"
cp "$BUILD_ROOT/QuickShareMac.dmg" "$ROOT/"

if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" \
    "$ROOT/QuickShareMac.zip" \
    "$ROOT/QuickShareMac.dmg" \
    --title "Quick Share $VERSION" \
    --generate-notes
else
  echo "Release $TAG already exists; uploading/replacing assets."
  gh release upload "$TAG" \
    "$ROOT/QuickShareMac.zip" \
    "$ROOT/QuickShareMac.dmg" \
    --clobber
fi

echo "Published $TAG"
gh release view "$TAG" --json url --jq .url
