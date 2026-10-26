#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$ROOT/Build/MonoHui-Kit.app"

echo "🚀 MonoHui-Kit 一键安装"
echo "═══════════════════════════"

# Step 1: Build
echo ""
echo "🔨 构建 App..."
bash "$ROOT/build.sh"

# Step 2: Copy to Applications
echo ""
echo "📋 安装到 /Applications..."
# 本机删除保护会拒绝 rm -rf 已安装的 .app，改为「归档旧包 + 整包复制」，失败则回滚
ARCHIVE_DIR="$ROOT/Build/archive"
mkdir -p "$ARCHIVE_DIR"
BACKUP_APP=""
if [ -d "/Applications/MonoHui-Kit.app" ]; then
  BACKUP_APP="$ARCHIVE_DIR/MonoHui-Kit-installed-$(date +%Y%m%d-%H%M%S).app"
  if ! mv "/Applications/MonoHui-Kit.app" "$BACKUP_APP"; then
    echo "   ❌ 旧版本无法移出 /Applications，中止安装"
    exit 1
  fi
  touch "$BACKUP_APP" 2>/dev/null || true
  echo "   📦 旧版本已归档"
fi
# 目标已存在时 cp -R 会复制成嵌套目录，必须先断言清空
if [ -e "/Applications/MonoHui-Kit.app" ]; then
  echo "   ❌ /Applications/MonoHui-Kit.app 仍然存在，中止安装以避免嵌套复制"
  exit 1
fi
if ! cp -R "$APP_BUNDLE" "/Applications/MonoHui-Kit.app"; then
  echo "   ❌ 复制失败，回滚到安装前的版本"
  if [ -n "$BACKUP_APP" ]; then
    mv "$BACKUP_APP" "/Applications/MonoHui-Kit.app"
  fi
  exit 1
fi

# Step 3: Register the app with Launch Services for "Open With" support.
echo ""
echo "🔗 注册 App..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "/Applications/MonoHui-Kit.app" 2>/dev/null || true

echo ""
echo "✅ 安装完成!"
echo ""
echo "打开 App: 在 Finder 中打开 /Applications，双击 MonoHui-Kit"
echo "管理服务菜单: 打开 App → 左下角设置 → 安装/移除各服务项"
echo ""
echo "使用方法:"
echo "  1. 打开 App → 设置 → 安装需要的服务菜单项"
echo "  2. 右击文件 → 服务 → 图片/快速压缩、文件夹/新建-年月日 等"
echo "  3. App 窗口: 打开 App → 图片压缩 → 拖入图片 → 压缩"
