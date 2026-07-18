#!/bin/bash
set -euo pipefail

# macOS symlinks have no special extension (unlike Windows .lnk).
# Keep a ".app" suffix so Finder launches it.
SRC="${BUILT_PRODUCTS_DIR:?}/${FULL_PRODUCT_NAME:?}"

if [[ -w /Applications ]]; then
  DEST_DIR="/Applications"
else
  DEST_DIR="${HOME}/Applications"
  mkdir -p "$DEST_DIR"
fi

DEST="${DEST_DIR}/DisableMainDisplay.app"

if [[ ! -e "$SRC" ]]; then
  echo "error: built app not found at $SRC" >&2
  exit 1
fi

# Remove older link/copy names and the current destination.
rm -rf \
  "/Applications/DisableMainDisplay.app" \
  "/Applications/DisableMainDisplay-Xcode.app" \
  "${HOME}/Applications/DisableMainDisplay.app" \
  "${HOME}/Applications/DisableMainDisplay-Xcode.app"

ln -s "$SRC" "$DEST"
echo "Symlinked $DEST -> $SRC"
