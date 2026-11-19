#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="盘览.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
cp Resources/AppIcon.icns "$app/Resources/AppIcon.icns"
cp Resources/AppBadge.png "$app/Resources/AppBadge.png"
cp Info.plist "$app/Info.plist"
xcrun swiftc -Osize -target "$(uname -m)-apple-macosx13.0" -module-cache-path "${TMPDIR:-/tmp}/moledesk-swift-cache" Sources/*.swift -o "$app/MacOS/MoleDesk"
codesign --force --sign - "盘览.app"
