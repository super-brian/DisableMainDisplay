#!/bin/zsh
set -e

cd "$(dirname "$0")"

echo "Building..."
swift build -c release

APP="DisableMainDisplay.app"
echo "Creating $APP bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DisableMainDisplay "$APP/Contents/MacOS/DisableMainDisplay"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f AppIcon.icns ]] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "Ad-hoc signing..."
codesign --force --sign - "$APP"

echo "Done!"
echo "  $APP"
