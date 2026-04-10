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

## 安装

1. 将 **ClawIsland.app** 拖到 **Applications** 文件夹。

2. 打开终端，执行：

   ```
   xattr -cr /Applications/ClawIsland.app
   ```

3. 从 Applications 启动应用。

此步骤用于移除 macOS 的隔离标记，防止系统拦截未签名应用。只需执行一次。

## 更新新版本

如果更新后 macOS 提示"已损坏"或"无法打开"：

1. 重新执行上面的 `xattr -cr` 命令。
2. 如仍然无法打开，前往 **系统设置 → 隐私与安全性**，滚动到底部，点击 **仍要打开**。

## 辅助功能权限

首次启动时，macOS 可能会请求 **辅助功能** 权限。此权限用于检测鼠标在刘海区域的悬停操作。

授权方式：

1. 打开 **系统设置 → 隐私与安全性 → 辅助功能**。
2. 在列表中找到 **ClawIsland** 并开启。
3. 若未弹出授权提示，请重新启动应用。

---

## Install

1. Drag **ClawIsland.app** to the **Applications** folder.

2. Open Terminal and run:

   ```
   xattr -cr /Applications/ClawIsland.app
   ```

3. Launch from Applications.

The `xattr` step removes the quarantine flag so macOS won't block the app.
It is needed because the app is not notarized. You only need to do it once.

## Updating to a New Version

If macOS blocks the app after updating (shows "damaged" or "cannot be opened"):

1. Re-run the `xattr -cr` command above.
2. If the app still won't open, go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.

## Accessibility Access

On first launch, macOS may prompt you to grant **Accessibility** access.
This is required for Claw Island to detect mouse hover on the notch area.

To grant or verify the permission:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Find **ClawIsland** in the list and enable it.
3. If you don't see the prompt, try relaunching the app.
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
