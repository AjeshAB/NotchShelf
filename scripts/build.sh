#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project NotchShelf.xcodeproj -scheme NotchShelf -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - build/Build/Products/Debug/NotchShelf.app
printf '\nBuilt: %s/build/Build/Products/Debug/NotchShelf.app\n' "$PWD"
