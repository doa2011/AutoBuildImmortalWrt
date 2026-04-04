#!/bin/bash
# OpenAppFilter 自动下载脚本
# 优先使用 GitHub API，失败则使用 HTML 解析作为备选

OAF_PKG_DIR="/home/build/immortalwrt/packages"
TMP_JSON="/tmp/oaf_release.json"

mkdir -p "$OAF_PKG_DIR"

echo "正在获取 OpenAppFilter 最新版本信息..."

# ① 优先用 GitHub API 获取 release 信息
API_OK=false
if curl -sf "https://api.github.com/repos/destan19/OpenAppFilter/releases/latest" \
     -o "$TMP_JSON"; then
    OP_LV=$(grep -o '"tag_name":[ ]*"[^"]*"' "$TMP_JSON" \
            | sed 's/.*"tag_name":[ ]*"v\?\([^"]*\)".*/\1/' | head -1)
    if [ -n "$OP_LV" ]; then
        echo "通过 API 获取到版本: $OP_LV"
        API_OK=true
    fi
fi

# ② API 失败则用 HTML 解析
if [ "$API_OK" = false ]; then
    echo "API 不可用，尝试 HTML 解析..."
    curl -sfL "https://github.com/destan19/OpenAppFilter/releases/latest" \
      -o "$TMP_JSON"
    OP_LV=$(grep -o 'releases/tag/v[^"]*' "$TMP_JSON" \
            | sed 's/releases\/tag\///' | head -1)
    if [ -n "$OP_LV" ]; then
        echo "通过 HTML 解析获取到版本: $OP_LV"
        API_OK=true
    fi
fi

if [ "$API_OK" = false ]; then
    echo "❌ 无法获取版本信息，退出"
    rm -f "$TMP_JSON"
    exit 1
fi

# ③ 下载文件
download_pkg() {
    local name="$1"
    local pattern="$2"
    local output="$3"

    local url=""

    # API 模式：从 JSON 中提取
    if [ "$API_OK" = true ]; then
        url=$(grep -o '"browser_download_url": *"[^"]*'"$pattern"'[^"]*"' "$TMP_JSON" \
              | grep -v '\.apkin"' \
              | grep '_all\.ipk' \
              | head -1 \
              | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    fi

    # 备用：从 HTML 提取（虽然可能为空）
    if [ -z "$url" ]; then
        url=$(grep -o "[^\"']*${pattern}[^\"']*\.ipk[^\"']*" "$TMP_JSON" \
              | grep '/download/' | grep '_all\.ipk' | head -1)
    fi

    if [ -n "$url" ]; then
        echo "下载 $name: $(basename $url)"
        curl -sfL "$url" -o "$output"
        if [ -s "$output" ]; then
            echo "  ✅ $(ls -lh "$output" | awk '{print $5, $9}')"
            return 0
        fi
    fi
    echo "  ⚠️ 下载失败或文件为空: $name"
    return 1
}

# LuCI 主包
download_pkg "luci-app-oaf" "luci-app-oaf" "$OAF_PKG_DIR/luci-app-oaf_all.ipk"

# 语言包
download_pkg "语言包" "luci-i18n-oaf" "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk"

# ④ 内核模块（从 tar.gz 提取）
KERNEL_URL=""
if [ "$API_OK" = true ]; then
    KERNEL_URL=$(grep -o '"browser_download_url": *"[^"]*mediatek_filogic[^"]*24.10.5[^"]*tar.gz[^"]*"' "$TMP_JSON" \
                 | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    if [ -z "$KERNEL_URL" ]; then
        KERNEL_URL=$(grep -o '"browser_download_url": *"[^"]*mediatek_mt7622[^"]*24.10.5[^"]*tar.gz[^"]*"' "$TMP_JSON" \
                     | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    fi
fi

if [ -n "$KERNEL_URL" ]; then
    echo "下载内核模块: $(basename $KERNEL_URL)"
    if curl -sfL "$KERNEL_URL" -o /tmp/oaf_kernel.tar.gz && [ -s /tmp/oaf_kernel.tar.gz ]; then
        KERNEL_DIR=$(tar -tzf /tmp/oaf_kernel.tar.gz 2>/dev/null | head -1 | tr -d '/')
        if [ -n "$KERNEL_DIR" ]; then
            tar -xzf /tmp/oaf_kernel.tar.gz -C /tmp/
            for ipk in "/tmp/${KERNEL_DIR}/"*.ipk; do
                [ -f "$ipk" ] || continue
                fname=$(basename "$ipk")
                case "$fname" in
                    appfilter_*)  mv "$ipk" "$OAF_PKG_DIR/appfilter_aarch64.ipk" ;;
                    kmod-oaf_*)   mv "$ipk" "$OAF_PKG_DIR/kmod-oaf_aarch64.ipk" ;;
                esac
            done
            rm -rf /tmp/oaf_kernel.tar.gz "/tmp/${KERNEL_DIR}"
            echo "  ✅ 内核模块解压完成"
        fi
    else
        echo "  ⚠️ 内核模块下载失败，跳过"
        rm -f /tmp/oaf_kernel.tar.gz
    fi
else
    echo "⚠️ 未找到内核模块下载链接，跳过"
fi

# ⑤ 汇总
echo ""
echo "========================================"
echo "下载完成:"
ls -lh "$OAF_PKG_DIR/"

OAF_PKGS=""
for f in "$OAF_PKG_DIR"/luci-app-oaf_all.ipk \
         "$OAF_PKG_DIR"/luci-i18n-oaf-zh-cn_all.ipk \
         "$OAF_PKG_DIR"/appfilter_aarch64.ipk \
         "$OAF_PKG_DIR"/kmod-oaf_aarch64.ipk; do
    [ -s "$f" ] && OAF_PKGS="${OAF_PKGS} $f"
done
echo "OAF_PACKAGES=\"$OAF_PKGS\"" > /tmp/oaf_packages.sh
echo "✅ OAF 包: $OAF_PKGS"
echo "========================================"

rm -f "$TMP_JSON"
