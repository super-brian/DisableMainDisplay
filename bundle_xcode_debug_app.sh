#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP="DisableMainDisplay.app"
EXECUTABLE_NAME="DisableMainDisplay"

find_debug_executable() {
  local candidates=(
    "/Volumes/M1ProApps/Developer/Xcode/DerivedData"
    "$HOME/Library/Developer/Xcode/DerivedData"
  )

  for derived_data in "${candidates[@]}"; do
    [[ -d "$derived_data" ]] || continue

    local executable
    executable=$(
      find "$derived_data" \
        -path "*/Build/Products/Debug/$EXECUTABLE_NAME" \
        -type f \
        -perm -111 \
        -print0 \
        2>/dev/null \
        | xargs -0 ls -t 2>/dev/null \
        | head -n 1
    )

    if [[ -n "$executable" ]]; then
      echo "$executable"
      return 0
    fi
  done

  return 1
}

DEBUG_EXECUTABLE="${1:-}"

if [[ -z "$DEBUG_EXECUTABLE" ]]; then
  DEBUG_EXECUTABLE="$(find_debug_executable || true)"
fi

if [[ -z "$DEBUG_EXECUTABLE" || ! -f "$DEBUG_EXECUTABLE" ]]; then
  echo "Could not find an Xcode Debug build executable."
  echo "Build Debug in Xcode first, or pass the executable path:"
  echo "  ./bundle_xcode_debug_app.sh /path/to/Build/Products/Debug/$EXECUTABLE_NAME"
  exit 1
fi

echo "Using debug executable:"
echo "  $DEBUG_EXECUTABLE"

echo "Replacing $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$DEBUG_EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f AppIcon.icns ]] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "Ad-hoc signing..."
codesign --force --sign - "$APP"

echo "Done!"
echo "  $APP"
