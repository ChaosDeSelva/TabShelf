#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
SWIFT_FLAGS=()
if [[ "${TABSHELF_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then SWIFT_FLAGS+=(--disable-sandbox); fi
swift build "${SWIFT_FLAGS[@]}" -c release
swift scripts/make-icons.swift "$PROJECT_ROOT"
APP="$PROJECT_ROOT/dist/TabShelf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/extension"
cp .build/release/TabShelf "$APP/Contents/MacOS/TabShelf"
cp .build/release/TabShelfBridge "$APP/Contents/Resources/TabShelfBridge"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp extension/* "$APP/Contents/Resources/extension/"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.tabshelf.bridge "$APP/Contents/Resources/TabShelfBridge"
codesign --force --sign - --identifier local.tabshelf.app --entitlements Resources/TabShelf.entitlements "$APP"
codesign --verify --deep --strict "$APP"
print -r -- "Built $APP"
