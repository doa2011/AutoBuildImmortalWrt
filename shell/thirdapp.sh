#!/bin/bash
# OpenAppFilter 自动下载脚本
# 使用 HTML 页面解析（避免 GitHub API rate limit）

OAF_PKG_DIR="/home/build/immortalwrt/packages"
TMP_HTML="/tmp/oaf_release_page.html"

mkdir -p "$OAF_PKG_DIR"

# ① 获取最新 release 页面
curl -sfL "https://github.com/destan19/OpenAppFilter/releases/latest" \
  -o "$TMP_HTML"

# 从 HTML 中提取版本号
OP_LV=$(sed -n 's/.*releases\/tag\/v\([^"]*\).*/\1/p' "$TMP_HTML" | head -1)
if [ -z "$OP_LV" ]; then
    OP_LV=$(grep -o 'releases/tag/v[^"]*' "$TMP_HTML" | head -1 | sed 's/releases\/tag\///')
fi
echo "OpenAppFilter 版本: $OP_LV"

# ② 提取下载链接的辅助函数
get_url() {
    local pattern="$1"
    local url
    url=$(grep -o "[^\"']*${pattern}[^\"']*" "$TMP_HTML" | grep '/download/' | head -1)
    echo "$url"
}

# 下载 LuCI 主包
IPK_URL=$(get_url "luci-app-oaf" | grep '_all\.ipk' | head -1)
if [ -n "$IPK_URL" ]; then
    echo "下载: $(basename $IPK_URL)"
    curl -sfL "https://github.com${IPK_URL}" -o "$OAF_PKG_DIR/luci-app-oaf_all.ipk"
    ls -lh "$OAF_PKG_DIR/luci-app-oaf_all.ipk"
else
    echo "⚠️ 未找到 luci-app-oaf 下载链接"
fi

# ③ 下载语言包
LANG_URL=$(get_url "luci-i18n-oaf" | grep '_all\.ipk' | head -1)
if [ -n "$LANG_URL" ]; then
    echo "下载: $(basename $LANG_URL)"
    curl -sfL "https://github.com${LANG_URL}" -o "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk"
    ls -lh "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk"
else
    echo "⚠️ 未找到语言包下载链接"
fi

# ④ 下载内核模块包（需要获取 releases 页面获取完整 assets）
echo "尝试获取内核模块..."
KERNEL_TGZ_URL=$(grep -o "[^\"']*mediatek[^\"']*openwrt24.10.5[^\"']*tar.gz[^\"']*" "$TMP_HTML" | grep '/download/' | head -1)
if [ -z "$KERNEL_TGZ_URL" ]; then
    # 从 releases 列表页获取完整 assets
    curl -sfL "https://github.com/destan19/OpenAppFilter/releases" \
      -o "$TMP_HTML"
    KERNEL_TGZ_URL=$(grep -o "[^\"']*mediatek_filogic[^\"']*openwrt24.10.5[^\"']*tar.gz[^\"']*" "$TMP_HTML" | grep '/download/' | head -1)
fi

if [ -n "$KERNEL_TGZ_URL" ]; then
    echo "下载: $(basename $KERNEL_TGZ_URL)"
    curl -sfL "https://github.com${KERNEL_TGZ_URL}" -o /tmp/oaf_kernel.tar.gz
    if [ -s /tmp/oaf_kernel.tar.gz ]; then
        KERNEL_DIR=$(tar -tzf /tmp/oaf_kernel.tar.gz 2>/dev/null | head -1 | tr -d '/')
        if [ -n "$KERNEL_DIR" ]; then
            tar -xzf /tmp/oaf_kernel.tar.gz -C /tmp/
            for ipk in /tmp/${KERNEL_DIR}/*.ipk; do
                [ -f "$ipk" ] || continue
                fname=$(basename "$ipk")
                case "$fname" in
                    appfilter_*)   mv "$ipk" "$OAF_PKG_DIR/appfilter_aarch64.ipk" ;;
                    kmod-oaf_*)   mv "$ipk" "$OAF_PKG_DIR/kmod-oaf_aarch64.ipk" ;;
                esac
            done
            rm -rf /tmp/oaf_kernel.tar.gz "/tmp/${KERNEL_DIR}"
        fi
    else
        echo "⚠️ 内核包下载失败或为空"
    fi
else
    echo "⚠️ 未找到内核模块下载链接，跳过"
fi

echo ""
echo "========================================"
echo "下载完成，检查文件..."
ls -lh "$OAF_PKG_DIR/"

# ⑤ 生成包列表
OAF_PKGS=""
for f in "$OAF_PKG_DIR"/luci-app-oaf_all.ipk \
         "$OAF_PKG_DIR"/luci-i18n-oaf-zh-cn_all.ipk \
         "$OAF_PKG_DIR"/appfilter_aarch64.ipk \
         "$OAF_PKG_DIR"/kmod-oaf_aarch64.ipk; do
    [ -s "$f" ] && OAF_PKGS="${OAF_PKGS} $f"
done
echo "OAF_PACKAGES=\"$OAF_PKGS\"" > /tmp/oaf_packages.sh
echo "✅ OAF 包列表: $OAF_PKGS"
echo "========================================"

rm -f "$TMP_HTML"
