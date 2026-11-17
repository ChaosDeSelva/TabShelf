#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
SWIFT_FLAGS=()
if [[ "${TABSHELF_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then SWIFT_FLAGS+=(--disable-sandbox); fi
TEST_FLAGS=(--disable-xctest --enable-swift-testing)
DEVELOPER_TOOLS="$(xcode-select -p)"
if [[ -d "$DEVELOPER_TOOLS/Library/Developer/Frameworks/Testing.framework" ]]; then
  TEST_FLAGS+=(-Xswiftc -F -Xswiftc "$DEVELOPER_TOOLS/Library/Developer/Frameworks")
  TEST_FLAGS+=(-Xlinker -rpath -Xlinker "$DEVELOPER_TOOLS/Library/Developer/Frameworks")
  TEST_FLAGS+=(-Xlinker -rpath -Xlinker "$DEVELOPER_TOOLS/Library/Developer/usr/lib")
fi
swift test "${SWIFT_FLAGS[@]}" "${TEST_FLAGS[@]}"
swift build "${SWIFT_FLAGS[@]}" --product TabShelfBridge
node --test tests-extension.cjs
python3 scripts/test-bridge.py .build/debug/TabShelfBridge
