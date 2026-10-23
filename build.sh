#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=build/Twenty.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14 Twenty.swift -o "$APP/Contents/MacOS/Twenty"
mkdir -p "$APP/Contents/Resources" && cp AppIcon.icns "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
# Copy rather than symlink: Spotlight skips symlinked apps and SMAppService would register the build/ path
rm -rf /Applications/Twenty.app && cp -R "$APP" /Applications/
echo "Built $APP and installed to /Applications/Twenty.app"
