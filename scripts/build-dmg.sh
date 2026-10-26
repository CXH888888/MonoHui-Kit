#!/bin/bash
# 打包 MonoHui-Kit.app 为 dmg 安装包（标准拖拽安装布局：app 在左、Applications 在右）
# 用法：bash scripts/build-dmg.sh
# 产物：dist/MonoHui-Kit-v{version}.dmg

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

VOLNAME="MonoHui-Kit"

# 读取版本号
VERSION=$(cat version.txt | tr -d '[:space:]')
if [ -z "$VERSION" ]; then
    echo "❌ version.txt 为空"
    exit 1
fi

APP_PATH="Build/MonoHui-Kit.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到 $APP_PATH，请先运行 bash deploy.sh 编译"
    exit 1
fi

# 产物目录
DIST_DIR="dist"
mkdir -p "$DIST_DIR"

DMG_NAME="MonoHui-Kit-v${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RW_DMG_PATH="$DIST_DIR/.tmp-rw.dmg"

# 清理旧产物
rm -f "$DMG_PATH" "$RW_DMG_PATH"

# 清理可能残留的旧 MonoHui-Kit 挂载点（避免后续 AppleScript 找错卷）
echo "🧹 清理残留挂载..."
for dev in $(hdiutil info | grep -B3 "/Volumes/$VOLNAME" | grep -oE '^/dev/disk[0-9]+' | sort -u); do
    hdiutil detach "$dev" -force >/dev/null 2>&1 || true
done

echo "📦 打包 $DMG_NAME ..."

# 步骤 1：创建可读写 dmg（只含 app 本体）
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDRW \
    "$RW_DMG_PATH" >/dev/null

# 步骤 2：挂载可读写 dmg（此时已清理残留，固定挂载到 /Volumes/MonoHui-Kit）
ATTACH_OUT=$(hdiutil attach -nobrowse -noautoopen "$RW_DMG_PATH")
MOUNT_DIR=$(echo "$ATTACH_OUT" | grep -oE '/Volumes/.*$' | head -1 | sed 's/[[:space:]]*$//')
DEV=$(echo "$ATTACH_OUT" | grep -oE '^/dev/disk[0-9]+' | head -1)
if [ -z "$MOUNT_DIR" ] || [ -z "$DEV" ]; then
    echo "❌ 挂载失败或解析失败"
    echo "$ATTACH_OUT"
    exit 1
fi
echo "   挂载到: $MOUNT_DIR (device: $DEV)"

# 步骤 3：在挂载点创建 Applications 软链接（拖拽安装用）
ln -s /Applications "$MOUNT_DIR/Applications"

# 步骤 4：用 AppleScript 设置 Finder 图标视图布局
#   - app 在左侧 (120, 160)
#   - Applications 在右侧 (400, 160)
#   - 窗口大小 660×400，图标大小 96px
# 无「自动化」权限时 Finder 会返回 -10004；此时退回默认布局，不影响 dmg 可用性
echo "   设置 Finder 布局..."
if osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    activate
    set theDisk to disk "$VOLNAME"
    open theDisk
    delay 1
    set theWindow to window 1
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {200, 200, 860, 600}
    set icon size of the icon view options of theWindow to 96
    set arrangement of the icon view options of theWindow to not arranged
    set position of item "MonoHui-Kit.app" of theDisk to {120, 160}
    set position of item "Applications" of theDisk to {400, 160}
    close theWindow
end tell
APPLESCRIPT
then
    echo "   ✅ 布局已设置"
else
    echo "   ⚠️  Finder 自动化权限不可用，跳过图标布局（dmg 功能不受影响）"
fi

# 步骤 5：卸载（用 device 强制 eject，避免挂载点残留导致资源忙）
hdiutil detach "$DEV" -force >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1

# 步骤 6：转换成只读压缩 dmg（UDZO）
hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG_PATH"

echo ""
echo "✅ 打包完成"
echo "   📁 $DMG_PATH"
echo ""
echo "📋 分发说明："
echo "   - 拷贝到其他 Mac 后双击挂载"
echo "   - 把左侧 MonoHui-Kit.app 拖到右侧 Applications 文件夹即完成安装"
echo "   - 首次启动需在「系统设置 → 隐私与安全性」点「仍要打开」放行 Gatekeeper"
echo "   - 打开后到「设置 → 服务菜单」点「全部安装」注册右键菜单"
