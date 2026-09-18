#!/bin/bash
# SciToolbox App Icon 生成脚本（App Store 版）
# 用法：./make-appicon.sh [源SVG] [输出前缀]
#   - 默认源：SciToolbox-appicon.svg（不透明全出血，App 图标不允许透明区域）
#   - 产物：AppIcon.icns（打包用）+ AppIcon_1024.png（App Store 上架素材，无 alpha）
# 依赖：swift（NSImage 光栅化）、sips、iconutil

set -e
cd "$(dirname "$0")"

SRC="${1:-SciToolbox-appicon.svg}"
PREFIX="${2:-AppIcon}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "🔧 光栅化 SVG → 1024 PNG（无 alpha）..."
sips -s format png "$SRC" --out "$WORK/icon_1024_raw.png" >/dev/null

# 无条件压平 alpha（幂等）：App Store 上架素材不允许透明通道；用 CoreGraphics 栅格合成
echo "   ├ 压平 alpha"
swift - "$WORK/icon_1024_raw.png" "$WORK/icon_1024.png" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func run(_ srcPath: String, _ outPath: String) {
    let srcURL = URL(fileURLWithPath: srcPath)
    let outURL = URL(fileURLWithPath: outPath)
    guard let src = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("decode") }
    let px = img.width > img.height ? img.width : img.height
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("ctx") }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let out = ctx.makeImage() else { fatalError("make") }
    guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("dest") }
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write") }
}
run(CommandLine.arguments[1], CommandLine.arguments[2])
SWIFT

echo "📦 生成 iconset 与 icns..."
mkdir -p "$WORK/${PREFIX}.iconset"
sips -z 16 16   "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_16x16.png"   >/dev/null
sips -z 32 32   "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_32x32.png"   >/dev/null
sips -z 64 64   "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$WORK/icon_1024.png" --out "$WORK/${PREFIX}.iconset/icon_512x512.png" >/dev/null
cp "$WORK/icon_1024.png" "$WORK/${PREFIX}.iconset/icon_512x512@2x.png"

iconutil -c icns "$WORK/${PREFIX}.iconset" -o "${PREFIX}.icns"

# App Store 上架素材：1024x1024 无 alpha PNG
cp "$WORK/icon_1024.png" "${PREFIX}_1024.png"

# 同步 iconset 目录（源码留档）
rm -rf "${PREFIX}.iconset"
cp -R "$WORK/${PREFIX}.iconset" "${PREFIX}.iconset"

echo "✅ 完成：${PREFIX}.icns / ${PREFIX}_1024.png / ${PREFIX}.iconset/"
sips -g hasAlpha "${PREFIX}_1024.png" | tail -1