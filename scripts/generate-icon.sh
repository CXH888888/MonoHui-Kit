#!/bin/bash
set -euo pipefail

SRC_PNG="$(cd "$(dirname "$0")/.." && pwd)/1103-MonoHui-Kit-logo-iOS-Default-1024x1024@1x.png"
ICON_DIR="$(cd "$(dirname "$0")/.." && pwd)/Build/icon.iconset"
OUTPUT_DIR="$(cd "$(dirname "$0")/../MonoHuiKit" && pwd)/Sources/App/Resources"

mkdir -p "$ICON_DIR" "$OUTPUT_DIR"

for size in 16 32 64 128 256 512; do
  sips -z $size $size "$SRC_PNG" --out "$ICON_DIR/icon_${size}x${size}.png" &>/dev/null
  sips -z $((size*2)) $((size*2)) "$SRC_PNG" --out "$ICON_DIR/icon_${size}x${size}@2x.png" &>/dev/null
done
sips -z 1024 1024 "$SRC_PNG" --out "$ICON_DIR/icon_1024x1024.png" &>/dev/null

iconutil -c icns "$ICON_DIR" -o "$OUTPUT_DIR/AppIcon.icns" && \
  echo "✅ App icon generated: $OUTPUT_DIR/AppIcon.icns"
