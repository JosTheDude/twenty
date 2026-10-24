#!/bin/sh
# Builds a universal build/Twenty.app and a release zip. Pass `install` to also copy it to /Applications.
set -e
cd "$(dirname "$0")/.."
APP=build/Twenty.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -swift-version 5 -target $arch-apple-macos14 Sources/Twenty/*.swift -o build/Twenty-$arch
done
lipo -create build/Twenty-arm64 build/Twenty-x86_64 -output "$APP/Contents/MacOS/Twenty"
rm build/Twenty-arm64 build/Twenty-x86_64
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$APP"
ditto -c -k --keepParent "$APP" "build/Twenty-$VERSION.zip"
echo "Built $APP and build/Twenty-$VERSION.zip"

if [ "$1" = install ]; then
    # Copy rather than symlink: Spotlight skips symlinked apps and SMAppService would register the build/ path
    rm -rf /Applications/Twenty.app && cp -R "$APP" /Applications/
    pkill -x Twenty; sleep 1; open /Applications/Twenty.app # pause: open fails while the old process is still quitting
    echo "Installed and relaunched /Applications/Twenty.app"
fi
