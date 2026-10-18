#!/bin/zsh
# Baut Playlist Reverser (Release, Universal) und erzeugt dist/PlaylistReverser-<Version>.dmg + .sha256.
# Aufruf aus der Projektwurzel: scripts/package.sh
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME="Playlist Reverser"
command -v xcodegen >/dev/null && xcodegen generate --quiet
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
[[ -n "$VERSION" && -f LICENSE ]] || { echo "Version oder LICENSE fehlt"; exit 1; }
DERIVED=build/release
DIST=dist
STAGE=$DERIVED/dmg

rm -rf "$DERIVED" "$STAGE"
mkdir -p "${DERIVED:h}"
xcodebuild -project PlaylistReverser.xcodeproj -scheme PlaylistReverser -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" ONLY_ACTIVE_ARCH=NO clean build > "$DERIVED-build.log" 2>&1 || {
    tail -n 80 "$DERIVED-build.log"
    exit 1
  }

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Build fehlgeschlagen"; exit 1; }
cp LICENSE "$APP/Contents/Resources/LICENSE"
# Entfernt Debug-Symbole mit lokalen Objekt-/Quellpfaden vor der Signierung.
strip -S "$APP/Contents/MacOS/$APP_NAME"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements PlaylistReverser/PlaylistReverser.entitlements "$APP"
codesign --verify --deep --strict "$APP"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  echo "Universal-Build fehlt: $ARCHS"
  exit 1
}
cmp LICENSE "$APP/Contents/Resources/LICENSE"

mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
cp LICENSE "$STAGE/LICENSE.txt"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/PlaylistReverser-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
(cd "$DIST" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
ls -l "$DMG"; cat "$DMG.sha256"
