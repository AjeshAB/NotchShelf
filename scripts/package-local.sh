#!/bin/bash
# Creates a locally ad-hoc signed development DMG. Use release.sh for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/Build/Products/Debug/NotchShelf.app
if [[ ! -d "$app" ]]; then ./scripts/build.sh; fi
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/NotchShelf.app"
codesign --force --deep --sign - "$staging/NotchShelf.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname NotchShelf -srcfolder "$staging" -ov -format UDZO build/NotchShelf-development.dmg
