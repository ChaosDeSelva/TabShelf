#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
"$PROJECT_ROOT/scripts/build.sh"
INSTALL_DIR="$HOME/Applications"
TARGET="$INSTALL_DIR/TabShelf.app"
mkdir -p "$INSTALL_DIR"
if [[ -e "$TARGET" ]]; then
  IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TARGET/Contents/Info.plist")
  if [[ "$IDENTIFIER" != "local.tabshelf.app" ]]; then
    print -u2 -- "Refusing to replace a different app at $TARGET"
    exit 1
  fi
  if pgrep -x TabShelf >/dev/null; then
    print -u2 -- "Quit TabShelf from its menu before installing this update."
    exit 1
  fi
fi
ditto "$PROJECT_ROOT/dist/TabShelf.app" "$TARGET"
open "$TARGET"
print -r -- "Installed $TARGET"
print -r -- "Click TabShelf in the top-right Mac menu bar to open your shelf."
