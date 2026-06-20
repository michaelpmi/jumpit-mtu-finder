#!/bin/bash
# Builds "MTU Finder.app" from the Swift sources — no Xcode project needed,
# only the Command Line Tools (swiftc + macOS SDK).
set -euo pipefail
cd "$(dirname "$0")"

APP="MTU Finder.app"
EXE="MTUFinder"

echo "==> Cleaning previous bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling Swift sources (release)"
swiftc -O \
    -framework SwiftUI -framework AppKit \
    -o "$APP/Contents/MacOS/$EXE" \
    Sources/*.swift

echo "==> Installing Info.plist"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f icon/AppIcon.icns ]; then
    echo "==> Installing app icon"
    cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "   (no icon/AppIcon.icns — skipping icon)"
fi

echo "==> Installing localizations"
for d in localization/*.lproj; do
    [ -d "$d" ] && cp -R "$d" "$APP/Contents/Resources/"
done

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   (codesign skipped)"

echo "==> Done: $(pwd)/$APP"
