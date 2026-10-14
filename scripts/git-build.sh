#!/bin/bash
# Debug build stamped with git info: CFBundleVersion = commit count,
# CFBundleShortVersionString = <version>-<short sha>[-dirty]. Falls back to the
# project.yml values when not in a git repository.
set -euo pipefail
cd "$(dirname "$0")/.."

"$(dirname "$0")/build.sh"

APP=build/Build/Products/Debug/NotchShelf.app
PLIST="$APP/Contents/Info.plist"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
  SHA=$(git rev-parse --short HEAD)
  COUNT=$(git rev-list --count HEAD)
  DIRTY=""; [ -n "$(git status --porcelain)" ] && DIRTY="-dirty"
  BASE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $COUNT" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${BASE%%-*}-$SHA$DIRTY" "$PLIST"
  codesign --force --deep --sign - "$APP"
  printf 'Stamped: %s-%s%s (build %s)\n' "${BASE%%-*}" "$SHA" "$DIRTY" "$COUNT"
else
  echo "Not a git repo with commits; skipping version stamp."
fi
