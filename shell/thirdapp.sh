#!/bin/bash
# OpenAppFilter 自动下载脚本
# 下载并安装到 imagebuilder rootfs

OAF_PKG_DIR="/home/build/immortalwrt/packages"
TMP_JSON="/tmp/oaf_release.json"

mkdir -p "$OAF_PKG_DIR"

# ① 获取最新 release 版本
curl -sf https://api.github.com/repos/destan19/OpenAppFilter/releases/latest \
  -o "$TMP_JSON"

OP_LV=$(grep -o '"tag_name": *"[^"]*"' "$TMP_JSON" \
        | sed 's/"tag_name": *"\([^"]*\)"/\1/' | sed 's/^v//')

echo "OpenAppFilter 最新版本: $OP_LV"

# ② LuCI 主包
IPK_URL=$(grep -o '"browser_download_url": *"[^"]*luci-app-oaf[^"]*\.ipk[^"]*"' \
           "$TMP_JSON" | grep -v '\.apk"' \
           | sed 's/"browser_download_url": *"\([^"]*\)"/\1/' | head -1)
echo "下载: $(basename $IPK_URL)"
wget -q "$IPK_URL" -O "$OAF_PKG_DIR/luci-app-oaf_all.ipk"

# ③ 语言包
LANG_URL=$(grep -o '"browser_download_url": *"[^"]*luci-i18n-oaf[^"]*\.ipk[^"]*"' \
             "$TMP_JSON" | grep -v '\.apk"' \
             | sed 's/"browser_download_url": *"\([^"]*\)"/\1/' | head -1)
echo "下载: $(basename $LANG_URL)"
wget -q "$LANG_URL" -O "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk"

# ④ 平台主程序 + 内核模块（优先 mediatek_filogic，没有则 fallback mt7622）
KERNEL_URL=$(grep -o '"browser_download_url": *"[^"]*openwrt24.10.5[^"]*mediatek_filogic[^"]*"' \
             "$TMP_JSON" | sed 's/"browser_download_url": *"\([^"]*\)"/\1/' | head -1)
if [ -z "$KERNEL_URL" ]; then
    KERNEL_URL=$(grep -o '"browser_download_url": *"[^"]*openwrt24.10.5[^"]*mediatek_mt7622[^"]*"' \
                 "$TMP_JSON" | sed 's/"browser_download_url": *"\([^"]*\)"/\1/' | head -1)
fi
echo "下载: $(basename $KERNEL_URL)"
wget -q "$KERNEL_URL" -O /tmp/oaf_kernel.tar.gz

KERNEL_DIR=$(tar -tzf /tmp/oaf_kernel.tar.gz | head -1 | sed 's/\/$//')
tar -xzf /tmp/oaf_kernel.tar.gz -C /tmp/
cp "/tmp/${KERNEL_DIR}"/*.ipk "$OAF_PKG_DIR/"
mv "$OAF_PKG_DIR"/appfilter_*.ipk "$OAF_PKG_DIR/appfilter_aarch64.ipk"
mv "$OAF_PKG_DIR"/kmod-oaf_*.ipk "$OAF_PKG_DIR/kmod-oaf_aarch64.ipk"

# ⑤ 安装到 imagebuilder rootfs（make image 之前执行）
echo "开始安装到 rootfs..."
cd /home/build/immortalwrt
opkg install --force-depends \
#    $OAF_PKG_DIR/kmod-oaf_aarch64.ipk \
    $OAF_PKG_DIR/appfilter_aarch64.ipk \
    $OAF_PKG_DIR/luci-app-oaf_all.ipk \
    $OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk

echo "✅ OpenAppFilter 安装完成"
echo "========================================"

rm -rf "$TMP_JSON" /tmp/oaf_kernel.tar.gz "/tmp/${KERNEL_DIR}"
