#!/bin/bash
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "$0")/../MonoHuiKit/Sources/App/Resources/tools" && pwd)"
TMPDIR="/tmp/compressimages-dl"
mkdir -p "$TOOLS_DIR" "$TMPDIR"

echo "📦 下载压缩工具 (ARM64)..."
cd "$TMPDIR"

# 1. pngquant - lossy PNG
if [ ! -x "$TOOLS_DIR/pngquant" ]; then
  echo "  → pngquant"
  curl -sL -o pngquant.tar.bz2 https://pngquant.org/pngquant.tar.bz2
  mkdir -p pngquant_extract
  tar -xjf pngquant.tar.bz2 -C pngquant_extract 2>/dev/null || \
    (cd pngquant_extract && bzip2 -dc ../pngquant.tar.bz2 | tar -xf -)
  cp pngquant_extract/pngquant "$TOOLS_DIR/pngquant" 2>/dev/null || \
    cp $(find pngquant_extract -name "pngquant" -type f) "$TOOLS_DIR/pngquant" 2>/dev/null
  chmod +x "$TOOLS_DIR/pngquant"
fi

# 2. oxipng - lossless PNG
if [ ! -x "$TOOLS_DIR/oxipng" ]; then
  echo "  → oxipng"
  curl -sL -o oxipng.tar.gz https://github.com/oxipng/oxipng/releases/download/v10.1.1/oxipng-10.1.1-aarch64-apple-darwin.tar.gz
  tar -xzf oxipng.tar.gz
  cp oxipng-10.1.1-aarch64-apple-darwin/oxipng "$TOOLS_DIR/oxipng"
  chmod +x "$TOOLS_DIR/oxipng"
fi

# 3. gifsicle
if [ ! -x "$TOOLS_DIR/gifsicle" ]; then
  echo "  → gifsicle"
  curl -sL -o gifsicle \
    https://raw.githubusercontent.com/imagemin/gifsicle-bin/v7.0.1/vendor/macos/gifsicle
  cp gifsicle "$TOOLS_DIR/gifsicle"
  chmod +x "$TOOLS_DIR/gifsicle"
fi

# 4. cwebp (from libwebp)
if [ ! -x "$TOOLS_DIR/cwebp" ]; then
  echo "  → cwebp"
  curl -sL -o libwebp.tar.gz \
    https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0-mac-arm64.tar.gz
  tar -xzf libwebp.tar.gz
  cp libwebp-1.6.0-mac-arm64/bin/cwebp "$TOOLS_DIR/cwebp"
  chmod +x "$TOOLS_DIR/cwebp"
fi

# 5. avifenc (from libavif)
if [ ! -x "$TOOLS_DIR/avifenc" ]; then
  echo "  → avifenc"
  curl -sL -o avifenc.zip \
    https://github.com/AOMediaCodec/libavif/releases/download/v1.4.2/macOS-artifacts.zip
  unzip -q -o avifenc.zip -d avifenc_extract 2>/dev/null || unzip -q avifenc.zip
  cp $(find . -name "avifenc" -type f) "$TOOLS_DIR/avifenc" 2>/dev/null
  chmod +x "$TOOLS_DIR/avifenc" 2>/dev/null || true
fi

# 6. cjxl (from libjxl) - try multiple sources
if [ ! -x "$TOOLS_DIR/cjxl" ]; then
  echo "  → cjxl (via brew if available)"
  # Try to get cjxl from the system or a pre-built source
  if command -v brew &>/dev/null; then
    if brew list jpeg-xl &>/dev/null 2>&1; then
      cp "$(brew --prefix)/bin/cjxl" "$TOOLS_DIR/cjxl" 2>/dev/null
    else
      echo "  ⚠ cjxl not found, installing via brew (one-time)..."
      brew install jpeg-xl 2>/dev/null || echo "  ⚠ Failed to install jpeg-xl via brew"
      command -v cjxl &>/dev/null && cp "$(command -v cjxl)" "$TOOLS_DIR/cjxl" 2>/dev/null
    fi
  fi
fi

# 7. mozjpeg (cjpeg + djpeg + jpegtran + dylib)
if [ ! -x "$TOOLS_DIR/cjpeg" ] || [ ! -x "$TOOLS_DIR/djpeg" ]; then
  echo "  → mozjpeg (via brew)"
  if command -v brew &>/dev/null; then
    if ! brew list mozjpeg &>/dev/null 2>&1; then
      brew install mozjpeg 2>/dev/null || echo "  ⚠ Failed to install mozjpeg"
    fi
    MOZ_VER=$(ls /opt/homebrew/Cellar/mozjpeg/ 2>/dev/null | head -1)
    MOZ_DIR="/opt/homebrew/Cellar/mozjpeg/$MOZ_VER"
    if [ -d "$MOZ_DIR" ]; then
      cp "$MOZ_DIR/bin/cjpeg" "$TOOLS_DIR/cjpeg"
      cp "$MOZ_DIR/bin/djpeg" "$TOOLS_DIR/djpeg"
      cp "$MOZ_DIR/bin/jpegtran" "$TOOLS_DIR/jpegtran" 2>/dev/null || true
      cp "$MOZ_DIR/lib/libjpeg.62.3.0.dylib" "$TOOLS_DIR/lib/"
      ln -sf libjpeg.62.3.0.dylib "$TOOLS_DIR/lib/libjpeg.62.dylib"
      chmod +x "$TOOLS_DIR/cjpeg" "$TOOLS_DIR/djpeg"
      chmod +x "$TOOLS_DIR/jpegtran" 2>/dev/null || true

      # Fix libpng reference from absolute to @rpath
      install_name_tool -change \
        /opt/homebrew/opt/libpng/lib/libpng16.16.dylib \
        @rpath/libpng16.16.dylib \
        "$TOOLS_DIR/cjpeg" 2>/dev/null || true

      # Re-sign
      codesign --force --sign - "$TOOLS_DIR/cjpeg" "$TOOLS_DIR/djpeg" 2>/dev/null || true
      codesign --force --sign - "$TOOLS_DIR/jpegtran" 2>/dev/null || true

      echo "  ✓ mozjpeg $MOZ_VER"
    fi
  fi
fi

# 8. svgop (standalone SVGO via QuickJS ~1.9MB)
if [ ! -x "$TOOLS_DIR/svgop" ]; then
  echo "  → svgop"
  curl -sL -o svgop-qjs-macos.zip \
    https://github.com/twardoch/svgop/releases/download/0.8.0/svgop-qjs-macos.zip
  unzip -q -o svgop-qjs-macos.zip -d svgop_extract 2>/dev/null
  cp $(find svgop_extract -name "svgop*" -type f -perm +111 2>/dev/null | head -1) "$TOOLS_DIR/svgop" 2>/dev/null || \
    cp svgop_extract/svgop "$TOOLS_DIR/svgop" 2>/dev/null || true
  chmod +x "$TOOLS_DIR/svgop" 2>/dev/null || true
fi

echo ""
echo "✅ 工具下载完成"
echo "   📁 $TOOLS_DIR"
ls -lh "$TOOLS_DIR"/ 2>/dev/null
