#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/MonoHuiKit"
BUILD_DIR="$ROOT/Build"
APP_NAME="MonoHui-Kit"          # .app 名称
EXEC_NAME="MonoHuiKit"         # 可执行文件名
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# ── Version Management ──────────────────────────────────────────
VERSION_FILE="$ROOT/version.txt"
if [ ! -f "$VERSION_FILE" ]; then
  echo "1.0.0" > "$VERSION_FILE"
fi

# If VERSION_OVERRIDE is set (e.g. from env), use it; else read file
if [ -n "${VERSION_OVERRIDE:-}" ]; then
  SHORT_VERSION="$VERSION_OVERRIDE"
else
  SHORT_VERSION="$(cat "$VERSION_FILE" | xargs)"
fi

# Auto-increment build number
BUILD_NUMBER_FILE="$ROOT/.build_number"
if [ -f "$BUILD_NUMBER_FILE" ]; then
  BUILD_NUMBER="$(($(cat "$BUILD_NUMBER_FILE") + 1))"
else
  BUILD_NUMBER=1
fi
echo "$BUILD_NUMBER" > "$BUILD_NUMBER_FILE"

echo "📌 版本: $SHORT_VERSION (build $BUILD_NUMBER)"

echo "🚀 MonoHui-Kit 构建脚本"
echo "═══════════════════════════"

# Step 1: Download tools if missing
TOOLS_DIR="$PROJECT/Sources/App/Resources/tools"
TOOL_COUNT=$(find "$TOOLS_DIR" -type f 2>/dev/null | wc -l)
if [ "$TOOL_COUNT" -lt 5 ]; then
  echo ""
  echo "📦 下载压缩工具..."
  bash "$ROOT/scripts/download-tools.sh"
else
  echo "✅ 压缩工具已就绪 ($TOOL_COUNT 个)"
fi

# Step 1.5: Ensure bundled ImageMagick exists (offline format conversion)
echo ""
if [ ! -x "$TOOLS_DIR/imagemagick/bin/magick" ]; then
  echo "📦 打包内置 ImageMagick（离线格式转换用）..."
  bash "$ROOT/scripts/package-imagemagick.sh"
else
  echo "✅ 内置 ImageMagick 已就绪"
fi

# Step 2: Generate app icon
echo ""
echo "🎨 生成 App 图标..."
bash "$ROOT/scripts/generate-icon.sh"

# Step 3: Build Swift project
echo ""
echo "🔨 编译 Swift 项目 (release)..."
cd "$PROJECT"
swift build -c release --disable-sandbox 2>&1 | tail -5

# Step 4: Create .app bundle
echo ""
echo "📁 打包 .app..."
# 本机删除保护会拒绝 rm -rf 整个 .app（一次删除上百个文件）。
# 旧产物一律移入 Build/archive/ 归档，归档只保留最近 2 份，更早的移入废纸篓。
ARCHIVE_DIR="$BUILD_DIR/archive"
mkdir -p "$ARCHIVE_DIR"
if [ -d "$APP_BUNDLE" ]; then
  ARCHIVED="$ARCHIVE_DIR/MonoHui-Kit-build-$(date +%Y%m%d-%H%M%S).app"
  mv "$APP_BUNDLE" "$ARCHIVED" && touch "$ARCHIVED"
  OLD_ARCHIVES="$(ls -1dt "$ARCHIVE_DIR"/*.app 2>/dev/null | tail -n +3 || true)"
  if [ -n "$OLD_ARCHIVES" ]; then
    while IFS= read -r old; do
      mv "$old" "$HOME/.Trash/" 2>/dev/null || true
    done <<< "$OLD_ARCHIVES"
  fi
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/tools"

# Copy binary
BINARY_PATH="$(swift build -c release --disable-sandbox --show-bin-path 2>/dev/null)/$EXEC_NAME"
if [ ! -f "$BINARY_PATH" ]; then
  BINARY_PATH=".build/release/$EXEC_NAME"
fi

if [ ! -f "$BINARY_PATH" ]; then
  echo "❌ 找不到编译产物: $BINARY_PATH"
  exit 1
fi

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

# Copy tools (skip lib/ subdirectory, handle separately)
find "$TOOLS_DIR" -maxdepth 1 -type f -exec cp {} "$APP_BUNDLE/Contents/Resources/tools/" \; 2>/dev/null || true
chmod -R +x "$APP_BUNDLE/Contents/Resources/tools" 2>/dev/null || true

# Copy dylibs
if [ -d "$TOOLS_DIR/lib" ]; then
  LIB_DEST="$APP_BUNDLE/Contents/Resources/tools/lib"
  mkdir -p "$LIB_DEST"
  cp -R "$TOOLS_DIR/lib/" "$LIB_DEST/" 2>/dev/null || true
  chmod -R +w "$LIB_DEST" 2>/dev/null || true
fi

# Copy bundled ImageMagick (bin + lib + modules), recursive
if [ -d "$TOOLS_DIR/imagemagick" ]; then
  IM_DEST="$APP_BUNDLE/Contents/Resources/tools/imagemagick"
  mkdir -p "$IM_DEST"
  cp -R "$TOOLS_DIR/imagemagick/." "$IM_DEST/" 2>/dev/null || true
  chmod -R +x "$IM_DEST/bin" 2>/dev/null || true
fi

# Create Info.plist
# NOTE: We intentionally do NOT ship a FinderSync extension, Automator Quick
# Actions, or NSServices in this plist. FinderSync requires an Apple Developer
# certificate; Quick Actions appear as top-level Finder context menu items,
# which we do not want. Instead, the two "服务" menu items are provided by
# .workflow files placed in ~/Library/Services by the app Settings panel. This
# makes them truly installable/removable without rebuilding the app.
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.monohui.kit</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MonoHui-Kit</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>需要读取 Finder 中选中的文件，用于图片压缩、视频压缩、重命名、新建日期文件夹与暂存等操作。</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Copy app icon
if [ -f "$PROJECT/Sources/App/Resources/AppIcon.icns" ]; then
  cp "$PROJECT/Sources/App/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# GitHub PAT：私有仓库的应用内更新需要授权（建议只读细粒度 token，仅 Contents: Read）
# 存放在 ~/.monohui-kit/github-token，构建时打进 Bundle 资源，App 用它调 GitHub API
GH_TOKEN_FILE="$HOME/.monohui-kit/github-token"
if [ -f "$GH_TOKEN_FILE" ]; then
  cp "$GH_TOKEN_FILE" "$APP_BUNDLE/Contents/Resources/github-token"
else
  echo "   ℹ️  未找到 $GH_TOKEN_FILE，应用内「检查更新」在私有仓库上不可用"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 5: Sign app（优先用本地自签名证书，保持 TCC 权限；无证书则 ad-hoc）
echo ""
echo "✍️  签名..."
SIGNING_IDENTITY="QuickActions Local Signing"
# Apple Events 权限（读取 Finder 选中项）在 Hardened Runtime 下必须有对应 entitlement
# （MonoHuiKit.entitlements：com.apple.security.automation.apple-events），
# 否则系统直接拒绝且不弹授权框，新机器上表现就是「一直提示未检测到选中文件」。
# 注意 entitlements 文件本身不要加 XML 注释：plutil 与 AMFI 对注释位置都很挑剔。
ENTITLEMENTS="$PROJECT/MonoHuiKit.entitlements"

sign_app() {
    local identity="$1"
    if [ -f "$ENTITLEMENTS" ]; then
        codesign --force --sign "$identity" --options runtime \
            --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
    else
        echo "   ⚠️  未找到 $ENTITLEMENTS，Apple Events 可能被 Hardened Runtime 拒绝"
        codesign --force --sign "$identity" --options runtime "$APP_BUNDLE"
    fi
}
# 搜索证书指纹或名称 - 即使证书不被信任也能找到
CERT_FINGERPRINT=$(security find-identity -p codesigning 2>/dev/null | grep -E "[0-9A-F]{40}" | grep "$SIGNING_IDENTITY" | awk '{print $2}')
if [ -z "$CERT_FINGERPRINT" ]; then
    # 自签名证书未被系统信任（"始终信任"）时不会出现在 -p codesigning 列表中，
    # 回退到全量身份列表按名称查找，避免误退化成 ad-hoc 签名导致 TCC 权限失效
    CERT_FINGERPRINT=$(security find-identity 2>/dev/null | grep -E "[0-9A-F]{40}" | grep "$SIGNING_IDENTITY" | awk '{print $2}')
fi
if [ -n "$CERT_FINGERPRINT" ]; then
    echo "   使用本地证书: $SIGNING_IDENTITY"
    sign_app "$CERT_FINGERPRINT"
else
    echo "   ⚠️  未找到本地签名证书，使用 ad-hoc 签名"
    echo "   建议运行 bash scripts/setup-signing-cert.sh 创建证书，避免更新后 TCC 权限失效"
    sign_app -
fi

# Step 6: Register the .app with Launch Services for "Open With" support.
# The Services menu items are provided by .workflow files in ~/Library/Services
# and are installed/removed from the app Settings panel.
echo ""
echo "🔗 注册 App..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ 构建完成 (v$SHORT_VERSION build $BUILD_NUMBER)!"
echo "   📁 $APP_BUNDLE"
echo ""
echo "运行: open \"$APP_BUNDLE\""
echo "安装: bash install.sh"
echo ""
echo "💡 打开 App → 设置 → 安装服务菜单，"
echo "   然后在 Finder 中右击文件 → 服务 → 图片/快速压缩 等"
