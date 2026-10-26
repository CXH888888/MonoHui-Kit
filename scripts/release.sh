#!/bin/bash
# 发版：取 CHANGELOG 当前版本说明 → 打包 dmg → 提交 → 打 tag → 推送 → 建 GitHub Release 并上传 dmg
#
# 用法：
#   bash deploy.sh              # 先编译、安装、版本 +0.0.1、CHANGELOG 转正式条目
#   bash scripts/release.sh     # 再把这次版本发到 GitHub Release
#
# 只做发布不做编译：dmg 必须对应已经 deploy 过的产物，避免打出一个版本号和代码对不上的包。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

VERSION="$(cat version.txt | xargs)"
TAG="v$VERSION"
DMG="dist/MonoHui-Kit-v$VERSION.dmg"

# ── 前置检查 ────────────────────────────────────────────────
command -v gh >/dev/null 2>&1 || {
    echo "❌ 未安装 gh，请先执行：brew install gh"
    exit 1
}
gh auth status >/dev/null 2>&1 || {
    echo "❌ gh 尚未登录，请先执行：gh auth login"
    exit 1
}

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    Build/MonoHui-Kit.app/Contents/Info.plist 2>/dev/null || echo '')"
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "❌ 构建产物版本 (${APP_VERSION:-无}) 与 version.txt ($VERSION) 不一致"
    echo "   先运行 bash deploy.sh 编译并递增版本，再执行本脚本"
    exit 1
fi

# ── 打包 dmg ────────────────────────────────────────────────
echo ""
echo "📦 打包 dmg..."
bash scripts/build-dmg.sh
if [ ! -f "$DMG" ]; then
    echo "❌ 未生成 $DMG"
    exit 1
fi
echo "   $(du -h "$DMG" | cut -f1)  $DMG"

# ── 发布说明取自 CHANGELOG 对应版本 ──────────────────────────
NOTES="$(awk -v ver="$VERSION" '
    $0 ~ "^## \\[v" ver "\\]" { flag = 1; next }
    flag && /^## \[/ { exit }
    flag { print }
' CHANGELOG.md)"
if [ -z "$(printf '%s' "$NOTES" | tr -d '[:space:]')" ]; then
    echo "⚠️  CHANGELOG 里没有 v$VERSION 的条目，发布说明退回为标题"
    NOTES="MonoHui-Kit $TAG"
fi

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "🔎 dry-run：将发布 $TAG"
    echo "--- 发布说明 ---"
    printf '%s\n' "$NOTES"
    exit 0
fi

# ── 提交代码 ────────────────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    if ! git diff --cached --quiet; then
        git commit -m "release: $TAG"
        echo "   ✅ 已提交"
    fi
else
    echo "   ℹ️  工作区干净，跳过提交"
fi

# ── 打 tag 并推送 ───────────────────────────────────────────
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "   ℹ️  tag $TAG 已存在，复用"
else
    git tag -a "$TAG" -m "MonoHui-Kit $TAG"
    echo "   ✅ 已创建 tag $TAG"
fi
git push origin HEAD
git push origin "$TAG"

# ── 创建 Release 并上传 dmg ─────────────────────────────────
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "   ℹ️  Release $TAG 已存在，覆盖同名附件"
    gh release upload "$TAG" "$DMG" --clobber
else
    gh release create "$TAG" "$DMG" \
        --title "MonoHui-Kit $TAG" \
        --notes "$NOTES"
fi

echo ""
echo "✅ 已发布 $TAG"
gh release view "$TAG" --json url -q .url 2>/dev/null || true
