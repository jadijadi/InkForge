#!/bin/sh
# Builds InkForge in Release configuration and installs it into /Applications.
set -e
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

xcodegen generate >/dev/null
xcodebuild -project InkForge.xcodeproj -scheme InkForge -configuration Release \
  -derivedDataPath build/DerivedData -skipPackagePluginValidation build 2>&1 \
  | grep -E "^/.*InkForge/InkForge.*(error|warning):|BUILD (SUCCEEDED|FAILED)" || true

APP="build/DerivedData/Build/Products/Release/InkForge.app"
[ -d "$APP" ] || { echo "Build failed" >&2; exit 1; }

pkill -x InkForge 2>/dev/null || true
rm -rf /Applications/InkForge.app
cp -R "$APP" /Applications/InkForge.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/InkForge.app
echo "Installed /Applications/InkForge.app"
