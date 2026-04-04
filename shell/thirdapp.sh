#!/bin/bash
# OpenAppFilter 自动下载脚本
# 使用 HTML 页面解析（避免 GitHub API rate limit）

OAF_PKG_DIR="/home/build/immortalwrt/packages"
TMP_HTML="/tmp/oaf_release_page.html"

mkdir -p "$OAF_PKG_DIR"

# ① 获取最新 release 页面，解析版本和下载链接
curl -sfL "https://github.com/destan19/OpenAppFilter/releases/latest" \
  -o "$TMP_HTML"

# 从 HTML 中提取版本号（如 v6.1.7）
OP_LV=$(grep -o '"tag_name":[ ]*"[^"]*"' "$TMP_HTML" \
        | sed 's/.*"tag_name":[ ]*"v\?\([^"]*\)".*/\1/' | head -1)
# 如果上面方法不行，用备用
if [ -z "$OP_LV" ]; then
    OP_LV=$(grep -o 'tag_name[^,]*' "$TMP_HTML" | head -1 | sed 's/.*>v\?\([^<]*\)<.*/\1/')
fi
# 再试
if [ -z "$OP_LV" ]; then
    OP_LV=$(grep -oP 'releases/tag/v\K[^"]+' "$TMP_HTML" | head -1)
fi

echo "OpenAppFilter 版本: $OP_LV"

# ② 从 release 页面提取所有 .ipk 下载链接
get_download_url() {
    grep -oP 'href="\K[^"]*'"$1"'[^"]*"' "$TMP_HTML" \
    | head -1 | sed 's/.*href="https:\/\/github.com//;s/".*//'
}

# 备用方法：直接从页面HTML提取
IPK_URL=$(grep -o 'href="[^"]*luci-app-oaf[^"]*_all\.ipk[^"]*"' "$TMP_HTML" \
           | sed 's/href="//;s/"//' | head -1)
if [ -z "$IPK_URL" ]; then
    IPK_URL=$(grep -o 'href="/destan19/OpenAppFilter/releases/download/[^"]*luci-app-oaf[^"]*_all\.ipk[^"]*"' "$TMP_HTML" \
               | head -1 | sed 's/href="//;s/"//')
fi
IPK_URL="https://github.com${IPK_URL}"

echo "下载 LuCI: $(basename $IPK_URL)"
wget -q "$IPK_URL" -O "$OAF_PKG_DIR/luci-app-oaf_all.ipk" || {
    echo "⚠️ LuCI 下载失败，尝试备用方式..."
    curl -sfL "$IPK_URL" -o "$OAF_PKG_DIR/luci-app-oaf_all.ipk"
}

# ③ 语言包
LANG_URL=$(grep -o 'href="[^"]*luci-i18n-oaf[^"]*_all\.ipk[^"]*"' "$TMP_HTML" \
           | sed 's/href="//;s/"//' | head -1)
if [ -z "$LANG_URL" ]; then
    LANG_URL=$(grep -o 'href="/destan19/OpenAppFilter/releases/download/[^"]*luci-i18n-oaf[^"]*_all\.ipk[^"]*"' "$TMP_HTML" \
               | head -1 | sed 's/href="//;s/"//')
fi
LANG_URL="https://github.com${LANG_URL}"

echo "下载语言包: $(basename $LANG_URL)"
wget -q "$LANG_URL" -O "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk" || {
    echo "⚠️ 语言包下载失败，尝试备用方式..."
    curl -sfL "$LANG_URL" -o "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk"
}

# ④ 内核模块（HTML 可能需要访问 release 详情页获取完整 assets）
# 先尝试从当前页面找，如果没有则从 releases 列表页获取
KERNEL_TGZ=$(grep -o 'href="[^"]*mediatek[^"]*\.tar\.gz[^"]*"' "$TMP_HTML" \
             | sed 's/href="//;s/"//' | grep 'openwrt24.10.5' | head -1)
if [ -z "$KERNEL_TGZ" ]; then
    # 从 releases 列表页获取（包含更多 assets）
    curl -sfL "https://github.com/destan19/OpenAppFilter/releases" \
      -o "$TMP_HTML"
    KERNEL_TGZ=$(grep -o 'href="[^"]*mediatek_filogic[^"]*openwrt24.10.5[^"]*\.tar\.gz[^"]*"' "$TMP_HTML" \
                 | sed 's/href="//;s/"//' | head -1)
    if [ -z "$KERNEL_TGZ" ]; then
        KERNEL_TGZ=$(grep -o 'href="[^"]*mediatek[^"]*24.10.5[^"]*\.tar\.gz[^"]*"' "$TMP_HTML" \
                     | sed 's/href="//;s/"//' | head -1)
    fi
fi
KERNEL_TGZ="https://github.com${KERNEL_TGZ}"

if [ -n "$KERNEL_TGZ" ] && [ != "$KERNEL_TGZ" ]; then
    echo "下载内核包: $(basename $KERNEL_TGZ)"
    wget -q "$KERNEL_TGZ" -O /tmp/oaf_kernel.tar.gz || {
        echo "⚠️ 内核包下载失败，尝试备用方式..."
        curl -sfL "$KERNEL_TGZ" -o /tmp/oaf_kernel.tar.gz
    }

    if [ -f /tmp/oaf_kernel.tar.gz ] && [ -s /tmp/oaf_kernel.tar.gz ]; then
        KERNEL_DIR=$(tar -tzf /tmp/oaf_kernel.tar.gz 2>/dev/null | head -1 | sed 's/\/$//')
        if [ -n "$KERNEL_DIR" ]; then
            tar -xzf /tmp/oaf_kernel.tar.gz -C /tmp/
            cp "/tmp/${KERNEL_DIR}"/*.ipk "$OAF_PKG_DIR/" 2>/dev/null
            for ipk in "$OAF_PKG_DIR"/appfilter_*.ipk; do
                [ -f "$ipk" ] && mv "$ipk" "$OAF_PKG_DIR/appfilter_aarch64.ipk"
            done
            for ipk in "$OAF_PKG_DIR"/kmod-oaf_*.ipk; do
                [ -f "$ipk" ] && mv "$ipk" "$OAF_PKG_DIR/kmod-oaf_aarch64.ipk"
            done
            rm -rf /tmp/oaf_kernel.tar.gz "/tmp/${KERNEL_DIR}"
        fi
    else
        echo "⚠️ 内核包下载失败或为空，跳过"
        rm -f /tmp/oaf_kernel.tar.gz
    fi
else
    echo "⚠️ 未找到内核模块下载链接，跳过"
fi

# ⑤ 检查下载结果
echo ""
echo "========================================"
echo "下载完成，检查文件..."
ls -lh "$OAF_PKG_DIR/"

# 生成包列表
OAF_PKGS=""
for f in "$OAF_PKG_DIR"/luci-app-oaf_all.ipk "$OAF_PKG_DIR"/luci-i18n-oaf-zh-cn_all.ipk "$OAF_PKG_DIR"/appfilter_aarch64.ipk; do
    [ -s "$f" ] && OAF_PKGS="$OAF_PKGS $f"
done
for f in "$OAF_PKG_DIR"/kmod-oaf_aarch64.ipk; do
    [ -s "$f" ] && OAF_PKGS="$OAF_PKGS $f"
done

echo "OAF_PACKAGES=\"$OAF_PKGS\"" > /tmp/oaf_packages.sh
echo "✅ OAF 包列表已写入 /tmp/oaf_packages.sh"
echo "========================================"

rm -f "$TMP_HTML"
