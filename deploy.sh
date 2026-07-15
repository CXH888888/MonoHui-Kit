#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="QuickActions"
APP_BUNDLE="$ROOT/Build/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"
VERSION_FILE="$ROOT/version.txt"
CHANGELOG_FILE="$ROOT/CHANGELOG.md"

echo "🚀 QuickActions 一键部署（编译 + 覆盖安装 + 注册服务菜单）"
echo "═══════════════════════════════════════════════════════════"

# 0. 检查本地签名证书（避免更新后 TCC 权限失效）
SIGNING_IDENTITY="QuickActions Local Signing"
# 搜索证书指纹或名称 - 即使证书不被信任也能找到
CERT_FINGERPRINT=$(security find-identity -p codesigning 2>/dev/null | grep -E "[0-9A-F]{40}" | grep "$SIGNING_IDENTITY" | awk '{print $2}')
if [ -z "$CERT_FINGERPRINT" ]; then
    echo "⚠️  未检测到本地签名证书: $SIGNING_IDENTITY"
    echo "    没有稳定签名身份，每次更新后辅助功能权限会失效（需要重新授权）"
    echo ""
    echo "   要创建证书吗？只需一次，后续 deploy 自动使用"
    echo "   1) 创建证书（推荐，输入钥匙串密码即可）"
    echo "   2) 跳过，继续用 ad-hoc 签名"
    read -r -p "请选择 [1/2]: " CHOICE
    if [ "$CHOICE" = "1" ]; then
        bash "$ROOT/scripts/setup-signing-cert.sh" || {
            echo "❌ 证书创建失败，继续用 ad-hoc 签名"
        }
    else
        echo "   继续使用 ad-hoc 签名"
    fi
    echo ""
fi

# 0.5. 自动 +0.0.1 版本号
CURRENT_VERSION="$(cat "$VERSION_FILE" | xargs)"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
PATCH=$((PATCH + 1))
if [ "$PATCH" -gt 9 ]; then
  PATCH=0
  MINOR=$((MINOR + 1))
fi
if [ "$MINOR" -gt 9 ]; then
  MINOR=0
  MAJOR=$((MAJOR + 1))
fi
NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "📌 版本号: $CURRENT_VERSION → $NEW_VERSION"

# 1. 编译
echo ""
echo "1️⃣  编译..."
VERSION_OVERRIDE="$NEW_VERSION" bash "$ROOT/build.sh"

# 2. 退出正在运行的旧版（如果在跑）
echo ""
echo "2️⃣  退出旧版进程..."
pkill -f "/Applications/QuickActions.app" 2>/dev/null || true
sleep 1

# 3. 增量更新到 /Applications（保留目录结构，更接近正常应用更新）
echo ""
echo "3️⃣  更新到 /Applications..."
if [ -d "$INSTALL_DIR" ]; then
    # 已存在：用 rsync 增量同步（保留目录 inode，TCC 更友好）
    rsync -a --delete --exclude '.DS_Store' "$APP_BUNDLE/" "$INSTALL_DIR/"
    echo "   ✅ 增量更新完成"
else
    # 首次安装：直接复制
    cp -R "$APP_BUNDLE" "$INSTALL_DIR"
    echo "   ✅ 首次安装完成"
fi

# 4. 注册 App 到 Launch Services
echo ""
echo "4️⃣  注册 App..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$INSTALL_DIR" 2>/dev/null || true

# 5. 安装服务菜单（会自动清理旧 workflow + 子目录）
echo ""
echo "5️⃣  安装服务菜单..."
"$INSTALL_DIR/Contents/MacOS/$APP_NAME" --install 2>&1 || true

# 6. 刷新服务缓存
echo ""
echo "6️⃣  刷新服务缓存..."
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

# 7. 更新 CHANGELOG.md：把「未发布」区块改名为正式版本
echo ""
echo "7️⃣  更新 CHANGELOG.md..."
TODAY="$(date +%Y-%m-%d)"
if [ -f "$CHANGELOG_FILE" ]; then
  # 检查「未发布」区块是否有实际内容（排除占位文案）
  UNRELEASED_BODY="$(python3 -c "
import re, sys
with open('$CHANGELOG_FILE', 'r', encoding='utf-8') as f:
    content = f.read()
m = re.search(r'^## \[未发布\][^\n]*\n(.*?)(?=^## \[)', content, re.MULTILINE | re.DOTALL)
if m:
    body = m.group(1).strip()
    # 过滤掉占位文案和分割线，看是否还有实际内容
    placeholder = '（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）'
    body = body.replace(placeholder, '').replace('---', '').strip()
    print(body)
" 2>/dev/null || echo "")"

  if [ -z "$UNRELEASED_BODY" ]; then
    echo "   ⚠️  CHANGELOG.md 的「未发布」区块是空的"
    echo "   跳过 CHANGELOG 更新，请手动在 CHANGELOG.md 补充 v$NEW_VERSION 条目"
  else
    # 用 python3 安全替换：把 `## [未发布]` 改成 `## [vX.Y.Z] - YYYY-MM-DD`，
    # 并在其上方插入新的空 `## [未发布]` 区块
    python3 - "$CHANGELOG_FILE" "$NEW_VERSION" "$TODAY" <<'PY'
import sys, re
path, version, today = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
placeholder = "（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）"
# 先去掉全文所有占位文案（它只应存在于新的 [未发布] 区块，后面会重新写入）
content = content.replace(placeholder + "\n\n", "").replace("\n\n" + placeholder, "")
new_unreleased = "## [未发布]\n\n" + placeholder + "\n\n---\n\n"
pattern = re.compile(r'^## \[未发布\][^\n]*\n', re.MULTILINE)
if pattern.search(content):
    replacement = new_unreleased + "## [v" + version + "] - " + today + "\n"
    content = pattern.sub(replacement, content, count=1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"   已生成 v{version} 条目")
else:
    print(f"   ⚠️  未找到 `## [未发布]` 区块，请手动在 CHANGELOG.md 顶部加 `## [v{version}] - {today}`")
PY
  fi
else
  echo "   ⚠️  CHANGELOG.md 不存在，跳过"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ 部署完成！(v$NEW_VERSION)"
echo ""
echo "现在在 Finder 中右键文件 → 服务，应该看到："
echo "  图片·快速压缩"
echo "  图片·压缩为…"
echo "  文件夹·新建-年月"
echo "  文件夹·新建-月日"
echo "  文件夹·新建-年月日"
echo ""
echo "💡 如果没看到，尝试："
echo "   - 重新登录 macOS，或"
echo "   - 杀掉 Finder: killall Finder"
echo ""
echo "📝 下次开发时记得在 CHANGELOG.md 的「未发布」区块写改动说明"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "🔍 签名状态验证:"
SIGN_INFO=$(codesign -dvv "$INSTALL_DIR" 2>&1 | grep -E "Signature=|TeamIdentifier=" || echo "未知")
echo "   $SIGN_INFO"
if echo "$SIGN_INFO" | grep -q "adhoc"; then
    echo "   ⚠️  当前为 ad-hoc 签名，更新后 TCC 权限可能失效"
    echo "   建议运行: bash scripts/setup-signing-cert.sh"
elif echo "$SIGN_INFO" | grep -q "Signature=ad hoc"; then
    echo "   ⚠️  当前为 ad-hoc 签名，更新后 TCC 权限可能失效"
    echo "   建议运行: bash scripts/setup-signing-cert.sh"
else
    echo "   ✅ 已使用稳定证书签名，TCC 权限不会因更新失效"
fi
