#!/bin/bash
set -euo pipefail

PROJECT="ClawIsland.xcodeproj"
SCHEME="ClawIsland"
CONFIG="Release"
BUILD_DIR=".build"
DIST_DIR="dist"
DMG_NAME="ClawIsland"
APP_NAME="ClawIsland.app"
VOLUME_NAME="$DMG_NAME"

echo "==> Cleaning..."
# Detach any leftover mounts
for dev in $(hdiutil info 2>/dev/null | grep "/Volumes/$VOLUME_NAME" | awk '{print $1}'); do
    hdiutil detach "$dev" -quiet 2>/dev/null || true
done
sleep 1
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> Building $SCHEME ($CONFIG)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build \
    2>&1 | tail -3

APP_PATH="$BUILD_DIR/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found"
    exit 1
fi

echo "==> Preparing DMG contents..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir "$DMG_STAGING"

cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

cat > "$DMG_STAGING/README.md" << 'README'
# Claw Island

## Install

1. Drag **ClawIsland.app** to the **Applications** folder.

2. Open Terminal and run:

   ```
   xattr -cr /Applications/ClawIsland.app
   ```

3. Launch from Applications.

This step is needed because the app is not notarized.
You only need to do it once.
README

FINAL_DMG="$DIST_DIR/${DMG_NAME}.dmg"

echo "==> Creating DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$FINAL_DMG"

echo ""
echo "==> Done: $FINAL_DMG"
echo "    Size: $(du -h "$FINAL_DMG" | cut -f1)"
