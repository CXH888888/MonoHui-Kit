#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MonoHui-Kit"          # .app 名称
EXEC_NAME="MonoHuiKit"         # 可执行文件名
APP_BUNDLE="$ROOT/Build/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"
VERSION_FILE="$ROOT/version.txt"
CHANGELOG_FILE="$ROOT/CHANGELOG.md"

echo "🚀 MonoHui-Kit 一键部署（编译 + 覆盖安装 + 注册服务菜单）"
echo "═══════════════════════════════════════════════════════════"

# 0. 重复执行抑制
# 提权执行时命令可能被先以受限方式跑一遍、失败后自动提权重跑，
# 两次都会推进版本号，导致 v3.4.4 → v3.4.6 这种跳号。
# 成功结束后写时间戳，30 秒内的第二次启动直接跳过。
STAMP="${TMPDIR:-/tmp}/monohui-deploy-last-success"
NOW="$(date +%s)"
if [ -f "$STAMP" ]; then
    LAST="$(cat "$STAMP" 2>/dev/null || echo 0)"
    if [ $((NOW - LAST)) -lt 30 ]; then
        echo "⚠️  30 秒内已经成功部署过一次，跳过本次（避免重复递增版本号）"
        exit 0
    fi
fi

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
# 注意：版本号到安装成功后才落盘，中途失败不会留下已递增的版本号
echo "📌 版本号: $CURRENT_VERSION → $NEW_VERSION"

# 1. 编译
echo ""
echo "1️⃣  编译..."
VERSION_OVERRIDE="$NEW_VERSION" bash "$ROOT/build.sh"

# 2. 退出正在运行的旧版（如果在跑）
echo ""
echo "2️⃣  退出旧版进程..."
pkill -f "/Applications/MonoHui-Kit.app" 2>/dev/null || true
pkill -f "/Applications/QuickActions.app" 2>/dev/null || true
sleep 1

# 3. 覆盖安装：归档旧包 + 整包复制
# 不用 rsync --delete：本机删除保护会拒绝在 /Applications 内 unlink，
# 半更新会留下「新二进制 + 旧资源/旧 plist」的不一致状态。
echo ""
echo "3️⃣  更新到 /Applications..."
ARCHIVE_DIR="$ROOT/Build/archive"
mkdir -p "$ARCHIVE_DIR"
PREVIOUS_APP=""
if [ -d "$INSTALL_DIR" ]; then
    PREVIOUS_APP="$ARCHIVE_DIR/MonoHui-Kit-installed-$(date +%Y%m%d-%H%M%S).app"
    if ! mv "$INSTALL_DIR" "$PREVIOUS_APP"; then
        echo "   ❌ 旧版本无法移出 /Applications，中止安装"
        exit 1
    fi
    touch "$PREVIOUS_APP" 2>/dev/null || true
    echo "   📦 旧版本已归档到 Build/archive"
fi
# cp -R 在目标已存在时会把源目录塞进目标内部，变成 xxx.app/xxx.app，
# 外层 Info.plist 还是旧版本，等于装了个坏包。这里必须断言目标已清空。
if [ -e "$INSTALL_DIR" ]; then
    echo "   ❌ $INSTALL_DIR 仍然存在，中止安装以避免嵌套复制"
    exit 1
fi
if ! cp -R "$APP_BUNDLE" "$INSTALL_DIR"; then
    echo "   ❌ 复制失败，回滚到安装前的版本"
    if [ -n "$PREVIOUS_APP" ]; then
        mv "$PREVIOUS_APP" "$INSTALL_DIR"
    fi
    exit 1
fi
echo "   ✅ 安装完成"
echo "$NEW_VERSION" > "$VERSION_FILE"

# 归档只保留最近 2 份，更早的移入废纸篓（避免 Build/archive 无限增长）
OLD_ARCHIVES="$(ls -1dt "$ARCHIVE_DIR"/*.app 2>/dev/null | tail -n +3 || true)"
if [ -n "$OLD_ARCHIVES" ]; then
    while IFS= read -r old; do
        mv "$old" "$HOME/.Trash/" 2>/dev/null || true
    done <<< "$OLD_ARCHIVES"
fi

# 4. 注册 App 到 Launch Services
echo ""
echo "4️⃣  注册 App..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$INSTALL_DIR" 2>/dev/null || true

# 5. 安装服务菜单（会自动清理旧 workflow + 子目录）
echo ""
echo "5️⃣  安装服务菜单..."
"$INSTALL_DIR/Contents/MacOS/$EXEC_NAME" --install 2>&1 || true

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

# 8. 自动打开 app
echo ""
echo "8️⃣  启动 MonoHui-Kit..."
open "$INSTALL_DIR"
echo "   ✅ 已启动"

# 9. 记录成功时间，供开头的重复执行抑制使用
date +%s > "$STAMP"
