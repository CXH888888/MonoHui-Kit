#!/bin/bash
# 把 ImageMagick（含核心库、需要的格式插件及其依赖）自包含打包进 App 的
# tools/imagemagick/，使格式转化功能离线可用、不依赖用户系统安装 ImageMagick。
#
# 方案（关键权衡，避免破坏 IM 的模块发现）：
#  - ImageMagick 模块化：PSD/PSB/PNG/JPEG/TIFF 解码在 coders/*.so 插件里，由
#    libMagickCore 用 libltdl 按 configure.xml 的 CODER_PATH 动态加载。
#  - 实测：一旦改写 libMagickCore / libMagickWand 的依赖或 install-name，模块发现
#    即失效（-list format 归零）。因此这两份核心库「原样保留」。
#  - 只重写三类文件的「依赖(LC_LOAD_DYLIB)」指向 bundle 内 lib/：
#      bin/magick   → @loader_path/../lib/<名>
#      coders/filters/*.so → @loader_path/../../../<名>
#      lib/*.副库    → @loader_path/<名>（并把它们的 @rpath 依赖一并归一到 bundle）
#  - 核心库保留的 /opt/homebrew 绝对依赖，在运行时由调用方设置
#    DYLD_LIBRARY_PATH=(bundle)/lib 兜底解析（同 basename 都在 lib/ 里）。
#
# 用法:  bash scripts/package-imagemagick.sh [目标父目录]
#   无参：打进 CompressImages/Sources/App/Resources/tools/imagemagick
#   传参：打进 <参数>/imagemagick（供测试）
set -u

IM="/opt/homebrew/Cellar/imagemagick/7.1.2-30"
IMBIN="/opt/homebrew/bin/magick"
# 源侧(psd/psb/png/jpg/gif/webp/bmp/svg) + 目标侧(png/jpeg/tiff)
NEED_CODERS="png jpeg tiff psd gif webp bmp svg"

[ $# -ge 1 ] && ROOT="$1"/imagemagick || \
  ROOT="$(cd "$(dirname "$0")/../CompressImages/Sources/App/Resources/tools" && pwd)"/imagemagick
BIN="$ROOT/bin"; LIB="$ROOT/lib"
MAGICKCORE="libMagickCore-7.Q16HDRI.10.dylib"
MAGICKWAND="libMagickWand-7.Q16HDRI.10.dylib"
rm -rf "$ROOT"; mkdir -p "$BIN" "$LIB"

is_system() {
  case "$1" in
    /usr/lib/*|/System/Library/*|/Library/Frameworks/*|/System/Cryptexes/*) return 0 ;;
    *) return 1 ;;
  esac
}

# 把任意依赖串(abs/@rpath/@loader_path)解析成一个存在的文件路径（在 brew 前缀里按 basename 找）
resolve_dep() {
  local dep="$1" bn
  if [ "${dep:0:1}" = "/" ] && [ -e "$dep" ]; then echo "$dep"; return; fi
  bn="$(basename "$dep")"
  local found
  found="$(find /opt/homebrew -type f -name "$bn" -path '*/lib/*' 2>/dev/null | head -1)"
  [ -n "$found" ] && echo "$found"
}

# --- 1. 复制主程序与核心库（原样）---
cp "$IMBIN" "$BIN/magick"; chmod +x "$BIN/magick"
cp "$IM/lib/$MAGICKCORE" "$IM/lib/$MAGICKWAND" "$LIB/"

# --- 2. 精简插件目录 ---
MOD_DST="$LIB/ImageMagick/modules-Q16HDRI"
MOD_SRC="$IM/lib/ImageMagick/modules-Q16HDRI"
mkdir -p "$MOD_DST/coders" "$MOD_DST/filters" "$LIB/ImageMagick/config-Q16HDRI"
for c in $NEED_CODERS; do
  for ext in so la; do
    [ -f "$MOD_SRC/coders/$c.$ext" ] && cp "$MOD_SRC/coders/$c.$ext" "$MOD_DST/coders/"
  done
done
cp "$MOD_SRC"/filters/*.so "$MOD_DST/filters/" 2>/dev/null
cp "$IM/lib/ImageMagick/config-Q16HDRI/configure.xml" "$LIB/ImageMagick/config-Q16HDRI/"

# --- 3. BFS 收集所有非系统依赖到 lib/（能从 abs/@rpath/@loader_path 解析的都收集）---
seen_list=()
stack=("$BIN/magick" "$IM/lib/$MAGICKCORE" "$IM/lib/$MAGICKWAND"
       "$MOD_DST"/coders/*.so "$MOD_DST"/filters/*.so)
i=0
while [ $i -lt ${#stack[@]} ]; do
  m="${stack[$i]}"; i=$((i+1))
  [ -e "$m" ] || continue
  name="$(basename "$m")"
  skip=0
  for s in "${seen_list[@]+${seen_list[@]}}"; do [ "$s" = "$name" ] && skip=1 && break; done
  [ $skip = 1 ] && continue
  seen_list+=("$name")
  if [ "$name" != "magick" ] && [[ "$m" == *.dylib || "$m" == *.so ]] && [ ! -e "$LIB/$name" ]; then
    cp -f "$m" "$LIB/" 2>/dev/null
  fi
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    is_system "$dep" && continue
    r="$(resolve_dep "$dep")"
    [ -n "$r" ] && stack+=("$r")
  done < <(otool -L "$m" 2>/dev/null | sed -n '2,$p' | awk '{print $1}')
done
echo "收集依赖库：$(ls "$LIB" | wc -l | tr -d ' ') 个"

# --- 4. 仅改写 sub-dylib 的依赖为 @loader_path/<名>（核心库不动）---
for f in "$LIB"/*.dylib; do
  [ -e "$f" ] || continue
  bn="$(basename "$f")"
  [ "$bn" = "$MAGICKCORE" ] || [ "$bn" = "$MAGICKWAND" ] && continue
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    is_system "$dep" && continue
    install_name_tool -change "$dep" "@loader_path/$(basename "$dep")" "$f" 2>/dev/null
  done < <(otool -L "$f" 2>/dev/null | sed -n '2,$p' | awk '{print $1}')
done

# --- 4b. magick 与插件的非系统依赖 → bundle 内 lib/ 的相对 @loader_path ---
relink() { # $1=file $2=偏移(相对到 lib/)
  local m="$1" off="$2" dep
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    is_system "$dep" && continue
    if [ "$off" = "." ]; then
      install_name_tool -change "$dep" "@loader_path/$(basename "$dep")" "$m" 2>/dev/null
    else
      install_name_tool -change "$dep" "@loader_path/$off/$(basename "$dep")" "$m" 2>/dev/null
    fi
  done < <(otool -L "$m" 2>/dev/null | sed -n '2,$p' | awk '{print $1}')
}
relink "$BIN/magick"             "../lib"
for f in "$MOD_DST"/coders/*.so "$MOD_DST"/filters/*.so; do
  [ -e "$f" ] && relink "$f" "../../.."
done

# --- 5. 重新签名（ad-hoc）---
for f in "$BIN/magick" "$LIB"/*.dylib "$MOD_DST"/coders/*.so "$MOD_DST"/filters/*.so; do
  [ -e "$f" ] && codesign --force --sign - "$f" 2>/dev/null
done

echo "✅ 打包完成 → $ROOT"
du -sh "$ROOT"