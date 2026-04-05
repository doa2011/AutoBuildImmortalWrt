#!/bin/bash
# OpenAppFilter 自动下载脚本
# - 从第三方 release 下载 luci-app-oaf + 语言包
# - 从 tar.gz 提取主程序 appfilter ipk（不含 kmod，kmod 由用户添加到 PACKAGES）
# - build23.sh 中用户需额外在 PACKAGES 里加 kmod-appfilter

OAF_PKG_DIR="/home/build/immortalwrt/packages"
TMP_JSON="/tmp/oaf_release.json"

mkdir -p "$OAF_PKG_DIR"

echo "正在获取 OpenAppFilter 最新版本信息..."

# ① 用 Python 获取 release 信息（更可靠）
curl -sf "https://api.github.com/repos/destan19/OpenAppFilter/releases/latest" \
     -o "$TMP_JSON"

OP_LV=$(python3 -c "
import json,sys
d=json.load(open('$TMP_JSON'))
tag=d.get('tag_name','')
print(tag.lstrip('v'))
" 2>/dev/null)

if [ -n "$OP_LV" ]; then
    echo "获取到版本: $OP_LV"
else
    echo "❌ 无法获取版本信息，退出"
    rm -f "$TMP_JSON"
    exit 1
fi

# ② 下载 LuCI 包
URL_LUCI=$(python3 -c "
import json
d=json.load(open('$TMP_JSON'))
for a in d.get('assets',[]):
    n=a.get('name','')
    if 'luci-app-oaf' in n and n.endswith('_all.ipk'):
        print(a.get('browser_download_url',''))
        break
" 2>/dev/null)

if [ -n "$URL_LUCI" ]; then
    echo "下载 luci-app-oaf: $(basename $URL_LUCI)"
    curl -sfL "$URL_LUCI" -o "$OAF_PKG_DIR/luci-app-oaf_all.ipk"
    [ -s "$OAF_PKG_DIR/luci-app-oaf_all.ipk" ] && echo "  ✅ $(ls -lh $OAF_PKG_DIR/luci-app-oaf_all.ipk | awk '{print $5, $9}')"
fi

# ③ 下载语言包
URL_LANG=$(python3 -c "
import json
d=json.load(open('$TMP_JSON'))
for a in d.get('assets',[]):
    n=a.get('name','')
    if 'luci-i18n-oaf' in n and n.endswith('_all.ipk'):
        print(a.get('browser_download_url',''))
        break
" 2>/dev/null)

if [ -n "$URL_LANG" ]; then
    echo "下载语言包: $(basename $URL_LANG)"
    curl -sfL "$URL_LANG" -o "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk"
    [ -s "$OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk" ] && echo "  ✅ $(ls -lh $OAF_PKG_DIR/luci-i18n-oaf-zh-cn_all.ipk | awk '{print $5, $9}')"
fi

# ④ 下载 tar.gz 并提取主程序（不含 kmod）
URL_TAR=$(python3 -c "
import json
d=json.load(open('$TMP_JSON'))
for a in d.get('assets',[]):
    n=a.get('name','')
    # 优先找 mediatek_filogic，再找 mt7622，版本从24开始
    if ('mediatek_filogic' in n or 'mediatek_mt7622' in n) and 'openwrt24' in n and n.endswith('.tar.gz'):
        print(a.get('browser_download_url',''))
        break
" 2>/dev/null)

if [ -n "$URL_TAR" ]; then
    echo "下载主程序包: $(basename $URL_TAR)"
    if curl -sfL "$URL_TAR" -o /tmp/oaf_kernel.tar.gz && [ -s /tmp/oaf_kernel.tar.gz ]; then
        KERNEL_DIR=$(tar -tzf /tmp/oaf_kernel.tar.gz 2>/dev/null | head -1 | tr -d '/')
        if [ -n "$KERNEL_DIR" ]; then
            tar -xzf /tmp/oaf_kernel.tar.gz -C /tmp/
            # 只提取主程序 appfilter ipk，跳过 kmod
            for ipk in "/tmp/${KERNEL_DIR}/"*.ipk; do
                [ -f "$ipk" ] || continue
                fname=$(basename "$ipk")
                case "$fname" in
                    appfilter_*.ipk)
                        mv "$ipk" "$OAF_PKG_DIR/appfilter_aarch64.ipk"
                        echo "  ✅ 提取主程序: $fname -> appfilter_aarch64.ipk"
                        ;;
                    kmod-oaf_*.ipk)
                        echo "  ⏭️ 跳过 kmod（由用户添加 kmod-appfilter）: $fname"
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

# ⑤ 汇总
echo ""
echo "========================================"
echo "下载完成:"
ls -lh "$OAF_PKG_DIR/"

OAF_PKGS=""
for f in "$OAF_PKG_DIR"/luci-app-oaf_all.ipk \
         "$OAF_PKG_DIR"/luci-i18n-oaf-zh-cn_all.ipk \
         "$OAF_PKG_DIR"/appfilter_aarch64.ipk; do
    [ -s "$f" ] && OAF_PKGS="${OAF_PKGS} $f"
done
echo "OAF_PACKAGES=\"$OAF_PKGS\"" > /tmp/oaf_packages.sh
echo "✅ OAF 包（不含 kmod，kmod 由用户添加到 PACKAGES）"
echo "========================================"

rm -f "$TMP_JSON"
