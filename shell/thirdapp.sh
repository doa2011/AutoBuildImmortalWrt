#!/bin/bash
# OpenAppFilter 自动下载脚本
# - 从第三方 release 下载 luci-app-oaf + 语言包
# - 从 tar.gz 提取主程序 appfilter ipk（不含 kmod，kmod 由用户添加到 PACKAGES）
# - build23.sh 中用户需额外在 PACKAGES 里加 kmod-appfilter 或 kmod-oaf

OAF_PKG_DIR="/home/build/immortalwrt/packages"
TMP_JSON="/tmp/oaf_release.json"

mkdir -p "$OAF_PKG_DIR"

echo "正在获取 OpenAppFilter 最新版本信息..."

# ① 获取最新 release 版本
curl -sf https://api.github.com/repos/destan19/OpenAppFilter/releases/latest \
  -o "$TMP_JSON"

OP_LV=$(grep -o '"tag_name": *"[^"]*"' "$TMP_JSON" \
        | sed 's/"tag_name": *"\([^"]*\)"/\1/' | sed 's/^v//')

echo "OpenAppFilter 最新版本: $OP_LV"

# ② LuCI 主包
IPK_URL=$(grep -o '"browser_download_url": *"[^"]*luci-app-oaf[^"]*\.ipk[^"]*"' \
           "$TMP_JSON" | grep -v '\.apkin"' \
           | sed 's/"browser_download_url": *"\([^"]*\)"/\1/' | head -1)
echo "下载: $(basename $IPK_URL)"
wget -q "$IPK_URL" -O "$OAF_PKG_DIR/luci-app-oaf_all.ipk"

# ③ 语言包
LANG_URL=$(grep -o '"browser_download_url": *"[^"]*luci-i18n-oaf[^"]*\.ipk[^"]*"' \
             "$TMP_JSON" | grep -v '\.apkin"' \
             | sed 's/"browser_download_url": *"\([^"]*\)"/\1/' | head -1)
echo "下载: $(basename $LANG_URL)"
wget -q "$LANG_URL" -O "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk"

# ④ 主程序由用户自行安装，此处不再从 tar.gz 提取
# 用户可自行从 releases 下载 appfilter_aarch64.ipk 安装

# ⑤ 汇总
echo ""
echo "========================================"
echo "✅ 下载完成"
ls -lh "$OAF_PKG_DIR/"
echo "========================================"

# 输出包路径（不含主程序和 kmod）
OAF_PKGS=""
for f in "$OAF_PKG_DIR"/luci-app-oaf_all.ipk \
         "$OAF_PKG_DIR"/luci-i18n-oaf-zh-cn_all.ipk; do
    [ -s "$f" ] && OAF_PKGS="${OAF_PKGS} $f"
done
echo "OAF_PACKAGES=\"$OAF_PKGS\"" > /tmp/oaf_packages.sh
echo "✅ OAF 包（不含主程序，主程序由用户自行安装）: $OAF_PKGS"

rm -f "$TMP_JSON"
