#!/bin/bash
# 打包 QuickActions.app 为 dmg 安装包（标准拖拽安装：app + Applications 文件夹快捷方式）
# 用法：bash scripts/build-dmg.sh
# 产物：dist/QuickActions-v{version}.dmg

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# 读取版本号
VERSION=$(cat version.txt | tr -d '[:space:]')
if [ -z "$VERSION" ]; then
    echo "❌ version.txt 为空"
    exit 1
fi

APP_PATH="Build/QuickActions.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到 $APP_PATH，请先运行 bash deploy.sh 编译"
    exit 1
fi

# 产物目录
DIST_DIR="dist"
mkdir -p "$DIST_DIR"

DMG_NAME="QuickActions-v${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RW_DMG_PATH="$DIST_DIR/.tmp-rw.dmg"

# 清理旧产物
rm -f "$DMG_PATH" "$RW_DMG_PATH"

echo "📦 打包 $DMG_NAME ..."

# 步骤 1：创建可读写 dmg（只含 app 本体）
hdiutil create \
    -volname "QuickActions" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDRW \
    "$RW_DMG_PATH" >/dev/null

# 步骤 2：挂载可读写 dmg
MOUNT_DIR=$(hdiutil attach -nobrowse -noautoopen -mountpoint /Volumes/QuickActions "$RW_DMG_PATH" | grep '/Volumes/QuickActions' | head -1 | awk '{print $NF}')
if [ -z "$MOUNT_DIR" ]; then
    MOUNT_DIR="/Volumes/QuickActions"
fi

# 步骤 3：在挂载点创建 Applications 软链接（拖拽安装用）
ln -s /Applications "$MOUNT_DIR/Applications"

# 步骤 4：卸载
hdiutil detach "$MOUNT_DIR" >/dev/null

# 步骤 5：转换成只读压缩 dmg（UDZO）
hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG_PATH"

echo ""
echo "✅ 打包完成"
echo "   📁 $DMG_PATH"
echo ""
echo "📋 分发说明："
echo "   - 拷贝到其他 Mac 后双击挂载"
echo "   - 把 QuickActions.app 拖到右侧 Applications 文件夹即完成安装"
echo "   - 首次启动需在「系统设置 → 隐私与安全性」点「仍要打开」放行 Gatekeeper"
echo "   - 打开后到「设置 → 服务菜单」点「全部安装」注册右键菜单"
