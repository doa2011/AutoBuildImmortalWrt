#!/bin/bash
# OpenAppFilter 自动下载脚本
# - 从第三方 release 下载 luci-app-oaf + 语言包
# - 从 tar.gz 提取主程序 appfilter ipk（不含 kmod，kmod 用官方源 kmod-appfilter）
# - build23.sh 中需要额外在 PACKAGES 里加 kmod-appfilter

OAF_PKG_DIR="/home/build/immortalwrt/packages"
TMP_JSON="/tmp/oaf_release.json"

mkdir -p "$OAF_PKG_DIR"

echo "正在获取 OpenAppFilter 最新版本信息..."

# ① 用 GitHub API 获取 release 信息
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

if [ "$API_OK" = false ]; then
    echo "❌ 无法获取版本信息，退出"
    rm -f "$TMP_JSON"
    exit 1
fi

# ② 下载函数
download_pkg() {
    local name="$1"
    local pattern="$2"
    local output="$3"

    local url=""
    url=$(grep -o '"browser_download_url": *"[^"]*'"$pattern"'[^"]*"' "$TMP_JSON" \
          | grep -v '\.apkin"' \
          | grep '_all\.ipk' \
          | head -1 \
          | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')

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

# ③ 从 tar.gz 提取主程序（不含 kmod，kmod 用官方源 kmod-appfilter）
#    注意：这里提取的是 appfilter 主程序，不是 kmod-oaf
KERNEL_URL=""
KERNEL_URL=$(grep -o '"browser_download_url": *"[^"]*mediatek_filogic[^"]*24.10.5[^"]*tar.gz[^"]*"' "$TMP_JSON" \
             | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
if [ -z "$KERNEL_URL" ]; then
    KERNEL_URL=$(grep -o '"browser_download_url": *"[^"]*mediatek_mt7622[^"]*24.10.5[^"]*tar.gz[^"]*"' "$TMP_JSON" \
                 | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
fi

if [ -n "$KERNEL_URL" ]; then
    echo "下载主程序包: $(basename $KERNEL_URL)"
    if curl -sfL "$KERNEL_URL" -o /tmp/oaf_kernel.tar.gz && [ -s /tmp/oaf_kernel.tar.gz ]; then
        KERNEL_DIR=$(tar -tzf /tmp/oaf_kernel.tar.gz 2>/dev/null | head -1 | tr -d '/')
        if [ -n "$KERNEL_DIR" ]; then
            tar -xzf /tmp/oaf_kernel.tar.gz -C /tmp/
            # 只提取主程序 appfilter ipk（不含 kmod-oaf，kmod 用官方源）
            for ipk in "/tmp/${KERNEL_DIR}/"*.ipk; do
                [ -f "$ipk" ] || continue
                fname=$(basename "$ipk")
                case "$fname" in
                    appfilter_*.ipk)
                        mv "$ipk" "$OAF_PKG_DIR/appfilter_aarch64.ipk"
                        echo "  ✅ 提取主程序: $fname -> appfilter_aarch64.ipk"
                        ;;
                    kmod-oaf_*.ipk)
                        echo "  ⏭️ 跳过 kmod（使用官方源 kmod-appfilter）: $fname"
                        ;;
                esac
            done
            rm -rf /tmp/oaf_kernel.tar.gz "/tmp/${KERNEL_DIR}"
        fi
    else
        echo "  ⚠️ 主程序包下载失败，跳过"
        rm -f /tmp/oaf_kernel.tar.gz
    fi
else
    echo "⚠️ 未找到主程序包下载链接，跳过"
fi

# ④ 汇总
echo ""
echo "========================================"
echo "下载完成:"
ls -lh "$OAF_PKG_DIR/"

# 输出包路径（不含 kmod，kmod 由官方源提供）
OAF_PKGS=""
for f in "$OAF_PKG_DIR"/luci-app-oaf_all.ipk \
         "$OAF_PKG_DIR"/luci-i18n-oaf-zh-cn_all.ipk \
         "$OAF_PKG_DIR"/appfilter_aarch64.ipk; do
    [ -s "$f" ] && OAF_PKGS="${OAF_PKGS} $f"
done
echo "OAF_PACKAGES=\"$OAF_PKGS\"" > /tmp/oaf_packages.sh
echo "✅ OAF 包（不含 kmod，kmod 用官方源）: $OAF_PKGS"
echo "========================================"

rm -f "$TMP_JSON"
