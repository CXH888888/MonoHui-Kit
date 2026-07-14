#!/bin/bash
# 创建本地代码签名证书（全自动，无需手动操作）
# 用于 QuickActions 代码签名，更新后 TCC 权限不失效
# 只需运行一次

set -euo pipefail

CERT_NAME="QuickActions Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP_DIR="/tmp/quickactions-cert"

echo "🔑 QuickActions 本地签名证书自动创建"
echo "═══════════════════════════════════════════════════════"
echo ""

# 1. 检查是否已存在（即使不被信任，只要证书存在就可以用）
CERT_FINGERPRINT=$(security find-identity -p codesigning 2>/dev/null | grep -E "[0-9A-F]{40}" | grep "$CERT_NAME" | awk '{print $2}')
if [ -n "$CERT_FINGERPRINT" ]; then
    echo "✅ 证书已存在: $CERT_NAME"
    echo "   指纹: $CERT_FINGERPRINT"
    echo "   无需重复创建，直接 bash deploy.sh 即可"
    exit 0
fi

echo "📋 正在自动创建证书..."
echo "   证书名: $CERT_NAME"
echo "   钥匙串: $KEYCHAIN"
echo "   有效期: 10 年"
echo ""

# 检查 openssl
if ! command -v openssl &> /dev/null; then
    echo "❌ 未找到 openssl，请先安装 (brew install openssl)"
    exit 1
fi

# 创建临时目录
mkdir -p "$TMP_DIR"

# 生成证书私钥和证书
cat > "$TMP_DIR/cert.conf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = x509_ext

[dn]
CN = $CERT_NAME

[x509_ext]
extendedKeyUsage = codeSigning
basicConstraints = CA:TRUE
keyUsage = keyCertSign, nonRepudiation, digitalSignature, keyEncipherment
EOF

echo "🔧 生成密钥和证书..."
openssl req -x509 -newkey rsa:2048 -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" \
    -days 3650 -nodes -config "$TMP_DIR/cert.conf" &>/dev/null

# 导入到钥匙串
echo "📥 导入到登录钥匙串..."
security import "$TMP_DIR/cert.pem" -k "$KEYCHAIN" &>/dev/null
security import "$TMP_DIR/key.pem" -k "$KEYCHAIN" -P "" &>/dev/null

# 清理临时文件
rm -rf "$TMP_DIR"

# 验证
echo ""
echo "🔍 验证证书..."
CERT_FINGERPRINT=$(security find-identity -p codesigning 2>/dev/null | grep -E "[0-9A-F]{40}" | grep "$CERT_NAME" | awk '{print $2}')
if [ -n "$CERT_FINGERPRINT" ]; then
    echo "✅ 证书创建成功！"
    echo "   指纹: $CERT_FINGERPRINT"
    echo ""
    echo "📝 后续 bash deploy.sh 会自动使用此证书签名"
    echo "   更新应用后辅助功能权限不会再失效"
else
    echo "❌ 证书创建失败，请重试"
    exit 1
fi

echo ""
echo "💡 接下来可以运行: bash deploy.sh"
