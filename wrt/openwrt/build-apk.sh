#!/bin/sh
# ============================================================================
# 一条命令构建 workbuddy2api 的 .apk 安装包
#
# 用法：
#   sh openwrt/build-apk.sh <SDK 目录> [应用源码目录]
#
#   <SDK 目录>      OpenWrt 25.12.x SDK（例：openwrt-sdk-25.12.2-x86-64_gcc-14.3.0_musl.Linux-x86_64）
#   [应用源码目录]  含 wb_*.py + dashboard.html 的目录（可选）。
#                   不给就按下面钉死的 commit 从 GitHub 拉取，缓存到 <仓库>/app-src/。
#
# 做的事：
#   1) 准备应用源码（拉取/复用缓存），校验版本号与 Makefile 的 PKG_VERSION 一致
#   2) 只挑 wb_*.py + dashboard.html 同步进 openwrt/workbuddy2api/files/usr/lib/workbuddy2api/
#   3) 把 openwrt/workbuddy2api 拷进 SDK/package/
#   4) make package/workbuddy2api/compile（-j1，低配机器/容器上更稳）
#   5) 产物拷到 <仓库>/apk/workbuddy2api_<版本>_all.apk 并打印 sha256
#
# 注意：构建机必须是 glibc 的 x86_64 Linux（SDK 自带宿主工具是 glibc 二进制，
# 不能在 musl 的 OpenWrt 上直接跑，也不能在 Windows 上跑）。本项目在路由器上
# 用 astrbot 的 Debian 容器（powerfee-build）构建。
# ============================================================================
set -e

# 上游仓库与钉死的版本（要升级时改这三行，并在 Makefile 里同步 PKG_VERSION）
UPSTREAM_REPO="ardeyouxipianyi/workbuddy2api-hub"
PIN_SHA="457e708106f5c780f7a95c90374576eae59d254b"
PIN_VER="1.6.16"

SDK="$1"
APP_SRC="$2"
[ -n "$SDK" ] || { echo "用法: $0 <OpenWrt SDK 目录> [应用源码目录]"; exit 1; }
[ -f "$SDK/rules.mk" ] || { echo "错误: $SDK 不像 OpenWrt SDK 目录（找不到 rules.mk）"; exit 1; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# ---- 1. 应用源码 ------------------------------------------------------------

if [ -z "$APP_SRC" ]; then
	if [ -f "$REPO/app-src/wb_proxy.py" ]; then
		APP_SRC="$REPO/app-src"
		echo "==> 1/5 复用已缓存的源码: $APP_SRC"
	else
		APP_SRC="$REPO/app-src"
		echo "==> 1/5 从 GitHub 拉取上游源码 @ $PIN_SHA"
		mkdir -p "$APP_SRC"
		TMP_TGZ="$(mktemp "${TMPDIR:-/tmp}/wb2api-src.XXXXXX.tar.gz")"
		wget -q -O "$TMP_TGZ" "https://codeload.github.com/$UPSTREAM_REPO/tar.gz/$PIN_SHA" \
			|| { echo "错误: 下载失败（检查网络/DNS）"; rm -f "$TMP_TGZ"; exit 1; }
		tar xzf "$TMP_TGZ" -C "$APP_SRC" --strip-components=1
		rm -f "$TMP_TGZ"
	fi
fi

[ -f "$APP_SRC/wb_proxy.py" ] || { echo "错误: $APP_SRC 里没有 wb_proxy.py"; exit 1; }
[ -f "$APP_SRC/dashboard.html" ] || { echo "错误: $APP_SRC 里没有 dashboard.html"; exit 1; }

DETECTED_VER="$(sed -n 's/.*server_version = "wb-proxy\/\([0-9.]*\)".*/\1/p' "$APP_SRC/wb_proxy.py" | head -n1)"
MAKE_VER="$(sed -n 's/^PKG_VERSION:=//p' "$REPO/openwrt/workbuddy2api/Makefile" | head -n1)"
echo "    源码版本: ${DETECTED_VER:-未知}    Makefile: $MAKE_VER"
[ "$DETECTED_VER" = "$MAKE_VER" ] || {
	echo "错误: 源码版本（${DETECTED_VER:-未知}）与 Makefile PKG_VERSION（$MAKE_VER）不一致。" >&2
	echo "      升级时请同步修改 Makefile 与本脚本顶部的 PIN_SHA / PIN_VER。" >&2
	exit 1
}

# ---- 2. 同步进包目录 --------------------------------------------------------

echo "==> 2/5 同步应用源码进包目录（只带 wb_*.py + dashboard.html）"
DST="$REPO/openwrt/workbuddy2api/files/usr/lib/workbuddy2api"
rm -rf "$DST"
mkdir -p "$DST"
for f in "$APP_SRC"/wb_*.py; do
	cp "$f" "$DST/"
done
cp "$APP_SRC/dashboard.html" "$DST/"
ls "$DST" | wc -l | xargs echo "    文件数:"

# ---- 3. 拷进 SDK ------------------------------------------------------------

echo "==> 3/5 拷进 $SDK/package/"
rm -rf "$SDK/package/workbuddy2api"
cp -R "$REPO/openwrt/workbuddy2api" "$SDK/package/workbuddy2api"

# ---- 4. 编译 ----------------------------------------------------------------

echo "==> 4/5 编译"
cd "$SDK"
[ -f .config ] || make defconfig
make -j1 package/workbuddy2api/compile V=s

# ---- 5. 收集产物 ------------------------------------------------------------

echo "==> 5/5 收集产物到 $REPO/apk/"
mkdir -p "$REPO/apk"
OUT_APK="$(find "$SDK/bin" -name 'workbuddy2api-*.apk' | head -n1)"
[ -n "$OUT_APK" ] || { echo "错误: 没找到 workbuddy2api 的 .apk 产物"; exit 1; }
cp "$OUT_APK" "$REPO/apk/workbuddy2api_${PIN_VER}_all.apk"
echo "    $OUT_APK"
echo "    -> apk/workbuddy2api_${PIN_VER}_all.apk"

echo "==> 完成"
sha256sum "$REPO/apk/"*.apk
