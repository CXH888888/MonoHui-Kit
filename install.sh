#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$ROOT/Build/QuickActions.app"

echo "🚀 QuickActions 一键安装"
echo "═══════════════════════════"

# Step 1: Build
echo ""
echo "🔨 构建 App..."
bash "$ROOT/build.sh"

# Step 2: Copy to Applications
echo ""
echo "📋 安装到 /Applications..."
if [ -d "/Applications/QuickActions.app" ]; then
  rm -rf "/Applications/QuickActions.app"
fi
cp -R "$APP_BUNDLE" "/Applications/QuickActions.app"

# Step 3: Register the app with Launch Services for "Open With" support.
echo ""
echo "🔗 注册 App..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "/Applications/QuickActions.app" 2>/dev/null || true

echo ""
echo "✅ 安装完成!"
echo ""
echo "打开 App: 在 Finder 中打开 /Applications，双击 QuickActions"
echo "管理服务菜单: 打开 App → 左下角设置 → 安装/移除各服务项"
echo ""
echo "使用方法:"
echo "  1. 打开 App → 设置 → 安装需要的服务菜单项"
echo "  2. 右击文件 → 服务 → 图片/快速压缩、文件夹/新建-年月日 等"
echo "  3. App 窗口: 打开 App → 图片压缩 → 拖入图片 → 压缩"
