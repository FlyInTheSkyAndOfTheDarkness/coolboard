#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS builds require macOS and Xcode. Use the Build iPhone IPA GitHub workflow from Windows."
  exit 1
fi
cd "$ROOT/ios"
xcodegen generate
xcodebuild -project CoolBoard.xcodeproj -scheme CoolBoard \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT/ios/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
APP="$ROOT/ios/build/Build/Products/Release-iphoneos/CoolBoard.app"
test -d "$APP/PlugIns/CoolBoardKeyboard.appex"
for key in CFBundleShortVersionString CFBundleVersion; do
  APP_VERSION="$(plutil -extract "$key" raw -o - "$APP/Info.plist")"
  EXTENSION_VERSION="$(plutil -extract "$key" raw -o - "$APP/PlugIns/CoolBoardKeyboard.appex/Info.plist")"
  if [[ "$APP_VERSION" != "$EXTENSION_VERSION" ]]; then
    echo "Version mismatch for $key: app=$APP_VERSION, keyboard=$EXTENSION_VERSION"
    exit 1
  fi
done
for resource in layouts.json lexicon.json emoji.json prediction.json predictive-seeds.json; do
  test -f "$APP/PlugIns/CoolBoardKeyboard.appex/$resource"
done
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Payload" "$ROOT/artifacts"
cp -R "$APP" "$STAGING/Payload/"
cd "$STAGING"
zip -qr "$STAGING/CoolBoard-unsigned.ipa" Payload
cp "$STAGING/CoolBoard-unsigned.ipa" "$ROOT/artifacts/CoolBoard-unsigned.ipa"
echo "Created artifacts/CoolBoard-unsigned.ipa. Sign with AltStore before installing on iPhone."
