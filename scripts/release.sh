#!/bin/bash
# Required: TEAM_ID, SIGN_IDENTITY, NOTARY_PROFILE, SPARKLE_FEED_URL, SPARKLE_PUBLIC_KEY.
# Store notarization credentials using: xcrun notarytool store-credentials <profile>
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEAM_ID:?Set your Apple Developer team ID}"
: "${SIGN_IDENTITY:?Set your Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set your notarytool keychain profile name}"
: "${SPARKLE_FEED_URL:?Set the HTTPS appcast URL}"
: "${SPARKLE_PUBLIC_KEY:?Set the Sparkle EdDSA public key}"
mkdir -p release
xcodegen generate
xcodebuild -project NotchShelf.xcodeproj -scheme NotchShelf -configuration Release \
  -archivePath release/NotchShelf.xcarchive DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual archive
app=release/NotchShelf.xcarchive/Products/Applications/NotchShelf.app
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$app/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" release/NotchShelf-notary.zip
xcrun notarytool submit release/NotchShelf-notary.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/NotchShelf.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname NotchShelf -srcfolder "$staging" -ov -format UDZO release/NotchShelf.dmg
codesign --timestamp --sign "$SIGN_IDENTITY" release/NotchShelf.dmg
xcrun notarytool submit release/NotchShelf.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple release/NotchShelf.dmg
printf '\nReady: release/NotchShelf.dmg\nGenerate and publish the Sparkle appcast with Sparkle generate_appcast before announcing an update.\n'
