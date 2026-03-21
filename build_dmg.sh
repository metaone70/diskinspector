#!/bin/bash
#
# build_dmg.sh — Build Disk Inspector DMG with custom icon
#
# Usage: ./build_dmg.sh [path-to-app]
#

set -e

APP_NAME="Disk Inspector"
VERSION="1.2"
DMG_NAME="DiskInspector-${VERSION}"
DMG_VOLUME="Disk Inspector"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Find the .app ──

if [ -n "$1" ]; then
    APP_PATH="$1"
else
    echo "Searching for Release build in DerivedData..."
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/DiskInspector-*/Build/Products/Release -name "DiskInspector.app" -maxdepth 1 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: DiskInspector.app not found."
    echo "Build a Release version in Xcode first, then run this script."
    exit 1
fi

echo "Using app: $APP_PATH"

# ── Calculate size needed ──

APP_SIZE=$(du -sm "$APP_PATH" | awk '{print $1}')
DMG_SIZE=$(( APP_SIZE + 10 ))  # Add 10 MB for overhead
echo "App size: ${APP_SIZE}MB, DMG size: ${DMG_SIZE}MB"

# ── Create a writable DMG with enough space ──

DMG_OUTPUT="$HOME/Desktop/${DMG_NAME}.dmg"
DMG_RW="/tmp/${DMG_NAME}_rw.dmg"
rm -f "$DMG_OUTPUT" "$DMG_RW"

echo "Creating writable DMG..."

# Eject any previously mounted volume with the same name
if [ -d "/Volumes/${DMG_VOLUME}" ]; then
    echo "Ejecting existing volume..."
    hdiutil detach "/Volumes/${DMG_VOLUME}" -quiet 2>/dev/null || diskutil unmount "/Volumes/${DMG_VOLUME}" 2>/dev/null || true
    sleep 1
fi

hdiutil create -size "${DMG_SIZE}m" -fs HFS+ -volname "$DMG_VOLUME" "$DMG_RW"

# ── Mount it ──

echo "Mounting..."
MOUNT_OUTPUT=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$MOUNT_OUTPUT" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/${DMG_VOLUME}"

sleep 1

if [ ! -d "$MOUNT_POINT" ]; then
    echo "Error: Could not mount DMG at $MOUNT_POINT"
    hdiutil detach "$DEVICE" 2>/dev/null || true
    exit 1
fi

echo "Mounted at: $MOUNT_POINT"

# ── Copy contents ──

echo "Copying app..."
cp -R "$APP_PATH" "$MOUNT_POINT/Disk Inspector.app"

echo "Adding Applications shortcut..."
ln -s /Applications "$MOUNT_POINT/Applications"

echo "Adding README..."
cp "$SCRIPT_DIR/README.md" "$MOUNT_POINT/README.md"

if [ -f "$SCRIPT_DIR/CHANGELOG.md" ]; then
    echo "Adding CHANGELOG..."
    cp "$SCRIPT_DIR/CHANGELOG.md" "$MOUNT_POINT/CHANGELOG.md"
fi

# ── Set volume icon ──

ICON_SRC="$APP_PATH/Contents/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    echo "Setting volume icon..."
    cp "$ICON_SRC" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT" 2>/dev/null && echo "  Icon flag set" || echo "  Note: SetFile not available"
fi

# ── Set Finder window position and icon sizes (optional) ──

echo "Configuring Finder view..."
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 720, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        close
    end tell
end tell
APPLESCRIPT
sleep 1

# ── Unmount ──

sync
hdiutil detach "$DEVICE" -quiet

# ── Convert to compressed read-only ──

echo "Compressing..."
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT"
rm -f "$DMG_RW"

# ── Set icon on the .dmg FILE itself ──

ICON_SRC="$APP_PATH/Contents/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    echo "Setting DMG file icon..."
    if command -v fileicon &> /dev/null; then
        fileicon set "$DMG_OUTPUT" "$ICON_SRC" && echo "  DMG file icon set" || echo "  Warning: fileicon failed"
    else
        echo "  Note: Install 'fileicon' (brew install fileicon) for DMG file icon"
    fi
fi

echo ""
echo "=================================="
echo "  DMG created: $DMG_OUTPUT"
echo "=================================="
echo "  Size: $(du -h "$DMG_OUTPUT" | cut -f1)"
echo ""
open -R "$DMG_OUTPUT"
