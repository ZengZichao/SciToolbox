#!/bin/bash
# make-screenshots.sh —— 把任意尺寸的截图归一化为 App Store Connect 要求的精确像素
#
# 为什么需要它：Mac 屏幕是 1.54:1（如 3024×1964），而 ASC 只接受 16:10 的固定像素
# （1280×800 / 1440×900 / 2560×1600 / 2880×1800）。直接拉伸会改变宽高比导致画面变形。
# 本脚本先等比缩放到不超过目标尺寸，再用白色补边到精确像素。
#
# 用法：
#   ./make-screenshots.sh 截图1.png 截图2.png 截图3.png
#   ./make-screenshots.sh -w 1280 -h 800 截图1.png
#   ./make-screenshots.sh --crop 截图1.png      # 改为裁切而非补边（无白边，但会裁掉少量边缘）
#   ./make-screenshots.sh -o 输出目录 截图1.png
#
# 输出：AppStoreScreenshots/ 下的 名称-2880x1800.png

set -euo pipefail

TARGET_W=2880
TARGET_H=1800
OUT_DIR="AppStoreScreenshots"
MODE="pad"          # pad | crop
PAD_COLOR="FFFFFF"

FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        -w) TARGET_W="$2"; shift 2 ;;
        -h) TARGET_H="$2"; shift 2 ;;
        -o) OUT_DIR="$2"; shift 2 ;;
        --crop) MODE="crop"; shift ;;
        --pad)  MODE="pad";  shift ;;
        --help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            FILES+=("$1"); shift ;;
    esac
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "用法：./make-screenshots.sh [-w 宽] [-h 高] [-o 输出目录] [--crop] 截图1.png [截图2.png ...]" >&2
    exit 1
fi

# 校验目标尺寸是否为 ASC 认可的规格
case "${TARGET_W}x${TARGET_H}" in
    1280x800|1440x900|2560x1600|2880x1800) ;;
    *) echo "⚠️  ${TARGET_W}x${TARGET_H} 不是 App Store 认可的规格。" >&2
       echo "    允许：1280x800 / 1440x900 / 2560x1600 / 2880x1800" >&2
       exit 1 ;;
esac

mkdir -p "$OUT_DIR"

ok=0
for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "❌ 找不到文件：$f"
        continue
    fi

    sw=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
    sh=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/{print $2}')
    if [ -z "$sw" ] || [ -z "$sh" ]; then
        echo "❌ 无法读取尺寸：$f"
        continue
    fi

    # 计算缩放后的尺寸
    # 注意：printf 必须带 \n —— 否则 read 在 EOF 返回非零，set -e 会静默终止脚本
    read -r nw nh factor < <(awk -v w="$sw" -v h="$sh" -v TW="$TARGET_W" -v TH="$TARGET_H" -v M="$MODE" 'BEGIN{
        if (M == "crop") { s = (TW/w > TH/h) ? TW/w : TH/h }
        else             { s = (TW/w < TH/h) ? TW/w : TH/h }
        printf "%d %d %.4f\n", int(w*s+0.5), int(h*s+0.5), s
    }')

    base=$(basename "$f")
    base="${base%.*}"
    out="$OUT_DIR/${base}-${TARGET_W}x${TARGET_H}.png"

    sips --resampleHeightWidth "$nh" "$nw" "$f" --out "$out" >/dev/null 2>&1

    if [ "$MODE" = "pad" ]; then
        sips --padToHeightWidth "$TARGET_H" "$TARGET_W" --padColor "$PAD_COLOR" "$out" >/dev/null 2>&1
    else
        sips --cropToHeightWidth "$TARGET_H" "$TARGET_W" "$out" >/dev/null 2>&1
    fi

    fw=$(sips -g pixelWidth  "$out" | awk '/pixelWidth/{print $2}')
    fh=$(sips -g pixelHeight "$out" | awk '/pixelHeight/{print $2}')

    if [ "$fw" = "$TARGET_W" ] && [ "$fh" = "$TARGET_H" ]; then
        printf "✅ %-34s %sx%s → %sx%s  (%s)\n" "$(basename "$f")" "$sw" "$sh" "$fw" "$fh" "$MODE"
        ok=$((ok+1))
    else
        printf "❌ %-34s 结果尺寸异常：%sx%s\n" "$(basename "$f")" "$fw" "$fh"
    fi

    # 放大提示
    awk -v s="$factor" 'BEGIN{ if (s > 1.0001) print "   ⚠️  源图偏小，已放大 —— 可能不够清晰，建议在高分辨率显示器上重截" }'
done

echo
echo "完成 $ok / ${#FILES[@]} 张，输出目录：$OUT_DIR/"
echo "上传前可再核对：sips -g pixelWidth -g pixelHeight $OUT_DIR/*.png"
