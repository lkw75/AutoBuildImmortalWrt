#!/bin/bash
set -e

# 25.12 x86_64 profile: enabled packages are taken from the selected
# ImmortalWrt feed, plus OpenClash assets pinned and verified below.
source shell/apk-custom-packages.sh
CUSTOM_PACKAGES="${CUSTOM_PACKAGES:-}"

echo "第三方/附加 apk 软件包: $CUSTOM_PACKAGES"
echo "编译固件大小为: ${PROFILE:-1024} MB"
echo "Include Docker: ${INCLUDE_DOCKER:-no}"

mkdir -p /home/build/immortalwrt/files/etc/config

# PPPoE is disabled by default. If it is explicitly enabled, keep the
# credentials in a root-only image file and never print them to build logs.
if [ "${ENABLE_PPPOE:-no}" = "yes" ]; then
  (
    umask 077
    cat > /home/build/immortalwrt/files/etc/config/pppoe-settings <<EOF
enable_pppoe=yes
pppoe_account=${PPPOE_ACCOUNT:-}
pppoe_password=${PPPOE_PASSWORD:-}
EOF
  )
  echo "已创建 PPPoE 配置（凭据已隐藏）"
else
  rm -f /home/build/immortalwrt/files/etc/config/pppoe-settings
  echo "PPPoE 未启用"
fi

# 所选包均来自 ImmortalWrt 25.12.1 官方 feed；本配置不克隆或执行
# 未固定版本的第三方 APK 仓库。
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

if [ "${INCLUDE_DOCKER:-no}" = "yes" ]; then
  PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
  echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

download_and_verify_sha256() {
  local url="$1"
  local destination="$2"
  local expected_sha256="$3"
  curl --fail --location --proto '=https' --retry 3 --silent --show-error "$url" --output "$destination"
  echo "$expected_sha256  $destination" | sha256sum -c -
}

if echo "$PACKAGES" | grep -qw "luci-app-openclash"; then
  echo "已选择 luci-app-openclash；下载已固定并校验的内核和规则数据"
  mkdir -p files/etc/openclash/core /home/build/immortalwrt/packages

  # OpenClash core branch commit e7e4863; verify its exact Git blob ID.
  CORE_ARCHIVE="/tmp/clash-linux-amd64-v1.tar.gz"
  CORE_URL="https://raw.githubusercontent.com/vernesong/OpenClash/e7e4863db2d1095af34489f78a2764388d867092/master/meta/clash-linux-amd64-v1.tar.gz"
  CORE_BLOB_SHA="c8c1e30fbeed7b871c17356cf821b036c0749291"
  curl --fail --location --proto '=https' --retry 3 --silent --show-error "$CORE_URL" --output "$CORE_ARCHIVE"
  [ "$(git hash-object "$CORE_ARCHIVE")" = "$CORE_BLOB_SHA" ] || { echo "OpenClash core integrity check failed" >&2; exit 1; }
  tar -xOzf "$CORE_ARCHIVE" > files/etc/openclash/core/clash_meta
  chmod 0755 files/etc/openclash/core/clash_meta
  rm -f "$CORE_ARCHIVE"

  download_and_verify_sha256 \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/202609072354/geoip.dat" \
    "files/etc/openclash/GeoIP.dat" \
    "4149e607530f91da697bad4696f8c59f0a475af38e69405e4124438c9886c721"
  download_and_verify_sha256 \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/202609072354/geosite.dat" \
    "files/etc/openclash/GeoSite.dat" \
    "2064a1a4074e145d5022ac49f2c30341e7b7cb6c7948da4fdca973b3fa8411b2"
  download_and_verify_sha256 \
    "https://github.com/vernesong/OpenClash/releases/download/v0.47.156/luci-app-openclash-0.47.156.apk" \
    "/home/build/immortalwrt/packages/luci-app-openclash-0.47.156.apk" \
    "1e4f330fc654e0270ac9cfa762af221335567d9b89388219890e8a7745b914ab"
fi

echo "开始构建固件：$PACKAGES"
make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE="${PROFILE:-1024}"
echo "构建成功。"
