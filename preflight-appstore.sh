#!/bin/bash
# preflight-appstore.sh —— 上传 App Store 之前，对归档做一轮本地预检
#
# 为什么需要它：Apple 的上传后校验（ITMS-xxxxx）只在提交后才告诉你问题，
# 一次往返就是一轮审核周期。本脚本把可在本地发现的问题提前拦住。
#
# 用法：
#   ./preflight-appstore.sh                    # 自动检查最新的归档
#   ./preflight-appstore.sh <路径.xcarchive>   # 检查指定归档
#
# 退出码：0 = 全部通过；1 = 存在必须修复的问题

set -uo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
FAIL=0

ok()   { printf "  ${GRN}✅${RST} %s\n" "$1"; }
bad()  { printf "  ${RED}❌${RST} %s\n" "$1"; FAIL=1; }
warn() { printf "  ${YEL}⚠️ ${RST} %s\n" "$1"; }
note() { printf "  ${DIM}%s${RST}\n" "$1"; }

# ---------- 定位归档 ----------
ARCH="${1:-}"
if [ -z "$ARCH" ]; then
    ARCH=$(find "$HOME/Library/Developer/Xcode/Archives" -maxdepth 2 -name "*.xcarchive" 2>/dev/null \
           | while IFS= read -r p; do printf "%s\t%s\n" "$(stat -f %m "$p")" "$p"; done \
           | sort -rn | head -1 | cut -f2)
fi

if [ -z "$ARCH" ] || [ ! -d "$ARCH" ]; then
    echo "❌ 未找到归档。请先执行 xcodebuild archive，或显式传入 .xcarchive 路径。" >&2
    exit 1
fi

APP=$(find "$ARCH/Products/Applications" -maxdepth 1 -name "*.app" 2>/dev/null | head -1)
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "❌ 归档内未找到 .app：$ARCH/Products/Applications" >&2
    exit 1
fi

echo "归档：$(basename "$ARCH")"
echo "App ：$(basename "$APP")"
echo

# ---------- 1. Info.plist 基本项 ----------
echo "【1】Info.plist 基本项"
PB=/usr/libexec/PlistBuddy
PL="$APP/Contents/Info.plist"

read_key() { $PB -c "Print :$1" "$PL" 2>/dev/null; }

BID=$(read_key CFBundleIdentifier);   [ -n "$BID" ] && ok "CFBundleIdentifier = $BID" || bad "缺 CFBundleIdentifier"
VER=$(read_key CFBundleShortVersionString); [ -n "$VER" ] && ok "版本 = $VER" || bad "缺 CFBundleShortVersionString"
BLD=$(read_key CFBundleVersion);      [ -n "$BLD" ] && ok "build = $BLD" || bad "缺 CFBundleVersion（上架必须有构建号）"
if [ -n "$BLD" ] && [ "$BLD" = "1" ]; then
    warn "build 号为 1，若此前已上传过 1 必须递增，否则 ASC 拒收"
fi
note "重新上传前务必确认此 build 号未被用过"

# ---------- 2. 分类 UTI 合法性 ----------
echo
echo "【2】LSApplicationCategoryType 合法性"
CAT=$(read_key LSApplicationCategoryType)
if [ -z "$CAT" ]; then
    bad "缺 LSApplicationCategoryType"
else
    VALID=$(/usr/bin/python3 -c "
import plistlib,re
d=plistlib.load(open('/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist','rb'))
print('\n'.join(sorted(set(re.findall(r'public\.app-category\.[a-z0-9-]+', repr(d))))))
" 2>/dev/null)
    if printf '%s\n' "$VALID" | grep -qx "$CAT"; then
        ok "$CAT（在系统合法表中）"
    else
        bad "$CAT 不是合法 UTI —— 会导致 ITMS 校验失败（常见错值：educational ≠ education）"
    fi
fi

# ---------- 3. 隐私清单（本项目曾在此翻车）----------
echo
echo "【3】PrivacyInfo.xcprivacy"
PIP="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
if [ ! -f "$PIP" ]; then
    warn "包内没有 PrivacyInfo.xcprivacy（若使用了必要原因 API，Apple 会要求补上）"
else
    note "$(basename "$(dirname "$PIP")")/PrivacyInfo.xcprivacy"
    # 3a 严格 XML 合法性 —— plutil 宽容，Apple 的校验器严格
    if /usr/bin/python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    ET.parse(sys.argv[1])
except ET.ParseError as e:
    print(e); sys.exit(1)
" "$PIP" 2>/tmp/xmlerr; then
        ok "严格 XML 解析通过"
    else
        bad "XML 非法：$(cat /tmp/xmlerr)"
        note "最常见原因：XML 注释里出现了 '--'（如用连字符画的分隔线）—— XML 规范禁止注释内出现双连字符"
    fi
    plutil -lint "$PIP" >/dev/null 2>&1 && ok "plutil 语法通过" || bad "plutil 语法失败"
    # 3b 顶层键只能有四个
    KEYS=$(plutil -convert json -o - "$PIP" 2>/dev/null | /usr/bin/python3 -c "
import json,sys
try: print('\n'.join(sorted(json.load(sys.stdin).keys())))
except Exception: pass")
    ALLOWED="NSPrivacyAccessedAPITypes NSPrivacyCollectedDataTypes NSPrivacyTracking NSPrivacyTrackingDomains"
    EXTRA=""
    while IFS= read -r k; do
        [ -z "$k" ] && continue
        printf '%s' "$ALLOWED" | grep -qw "$k" || EXTRA="$EXTRA $k"
    done <<< "$KEYS"
    if [ -n "$EXTRA" ]; then
        bad "存在非法顶层键：$EXTRA（只允许那四个）"
    else
        ok "顶层键均为合法键"
    fi
    [ -n "$KEYS" ] && note "键：$(echo "$KEYS" | tr '\n' ' ')"
fi

# ---------- 4. 沙盒与权限 ----------
echo
echo "【4】App Sandbox 与签名"
ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | /usr/bin/python3 -c "
import sys,plistlib
try:
    d=plistlib.loads(sys.stdin.buffer.read())
    for k,v in sorted(d.items()):
        if k.startswith('com.apple.security'): print(f'{k}={v}')
except Exception: pass" 2>/dev/null)

if printf '%s' "$ENT" | grep -q "app-sandbox=True"; then
    ok "com.apple.security.app-sandbox = True（Mac App Store 强制）"
else
    bad "未开启 App Sandbox —— 会被拒绝"
fi
printf '%s' "$ENT" | grep -q "network.client=True" && ok "network.client = True" || warn "未声明 network.client（若需联网则必须开启）"
printf '%s' "$ENT" | grep -q "user-selected" && ok "files.user-selected.read-write 已声明" || note "未声明 user-selected（仅导出功能需要）"

codesign -d --verbose=4 "$APP" 2>&1 | grep -q "flags=.*runtime" && ok "硬连运行时已开启" || bad "未开启硬连运行时（--options runtime）"

if codesign -d --entitlements - "$APP" 2>/dev/null | grep -qi "get-task-allow"; then
    bad "含 get-task-allow —— 发行包不允许携带"
else
    ok "无 get-task-allow"
fi

# ---------- 5. 图标 ----------
echo
echo "【5】图标"
ICON=$(read_key CFBundleIconName)
[ -n "$ICON" ] && ok "CFBundleIconName = $ICON" || warn "缺 CFBundleIconName（图标可能不显示）"

CAR="$APP/Contents/Resources/Assets.car"
if [ -f "$CAR" ]; then
    SIZES=$(xcrun --sdk macosx assetutil --info "$CAR" 2>/dev/null | /usr/bin/python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    s=sorted({e.get('PixelWidth') for e in d if isinstance(e,dict) and e.get('Name')=='AppIcon' and e.get('PixelWidth')})
    print(' '.join(map(str,s)))
except Exception: pass")
    if printf '%s' "$SIZES" | grep -qw 1024; then
        ok "Assets.car 含 AppIcon 且覆盖 1024（App Store 图标要求）"
        note "覆盖尺寸：$SIZES"
    else
        bad "Assets.car 缺 1024 图标尺寸（512@2x），App Store 图标校验会失败"
    fi
else
    bad "缺 Assets.car（图标未编译进包）"
fi

# ---------- 6. 构建环境是否为 Beta ----------
echo
echo "【6】构建环境"
if grep -qi beta /Applications/Xcode.app/Contents/version.plist 2>/dev/null \
   || xcrun --sdk macosx --show-sdk-path 2>/dev/null | grep -qi beta; then
    bad "检测到 Beta 版 Xcode 或 SDK —— Apple 会拒收 Beta 工具链构建的包"
else
    ok "Xcode / SDK 非 Beta"
fi

# ---------- 汇总 ----------
echo
if [ "$FAIL" -eq 0 ]; then
    printf "${GRN}全部预检通过，可以上传。${RST}\n"
    exit 0
else
    printf "${RED}存在必须修复的问题，请先处理再上传。${RST}\n"
    exit 1
fi
