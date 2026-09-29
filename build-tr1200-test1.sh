#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/work"
OUT="$ROOT/out"
IB_URL="https://downloads.immortalwrt.org/releases/24.10.6/targets/ramips/mt76x8/immortalwrt-imagebuilder-24.10.6-ramips-mt76x8.Linux-x86_64.tar.zst"
IB_SHA256="cb0bf098dda0ad52fa0af3cd9735c94da05dcbb8fdd8b9f620c4386bc6d346aa"
MOMO_URL="https://github.com/nikkinikki-org/OpenWrt-momo/releases/download/v1.2.1/momo_mipsel_24kc-openwrt-24.10.tar.gz"
PROFILE="cudy_tr1200-v1"
MAX_BYTES=$(( 9961472 )) # 9.5 MiB

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 2; }; }
for t in curl sha256sum tar zstd ar gzip find awk sed grep make; do need "$t"; done

printf '\n[1/7] Download ImmortalWrt 24.10.6 ImageBuilder...\n'
curl -fL --retry 3 -o "$WORK/imagebuilder.tar.zst" "$IB_URL"
echo "$IB_SHA256  $WORK/imagebuilder.tar.zst" | sha256sum -c -

tar --zstd -xf "$WORK/imagebuilder.tar.zst" -C "$WORK"
IB="$(find "$WORK" -maxdepth 1 -type d -name 'immortalwrt-imagebuilder-*' | head -n1)"
[ -n "$IB" ] || { echo "ImageBuilder extraction failed" >&2; exit 3; }

printf '\n[2/7] Download Momo v1.2.1 prebuilt feed for mipsel_24kc / OpenWrt 24.10...\n'
mkdir -p "$WORK/momo"
curl -fL --retry 3 -o "$WORK/momo.tar.gz" "$MOMO_URL"
tar -xzf "$WORK/momo.tar.gz" -C "$WORK/momo"
MOMO_IPKS=( $(find "$WORK/momo" -type f -name '*.ipk' -print) )
[ "${#MOMO_IPKS[@]}" -ge 3 ] || { echo "Expected Momo IPKs were not found" >&2; exit 4; }

printf '\n[3/7] Build RAM-only sing-box compatibility IPK...\n'
"$ROOT/scripts/build-tiny-singbox-ipk.sh" "$WORK/local-ipk" >/dev/null
TINY_IPK="$WORK/local-ipk/sing-box_99.0.0-r1_all.ipk"
[ -f "$TINY_IPK" ] || exit 5
if [ "$(stat -c%s "$TINY_IPK")" -gt 16384 ]; then
  echo "Tiny sing-box IPK unexpectedly exceeds 16 KiB" >&2
  exit 6
fi

printf '\n[4/7] Add local packages to ImageBuilder...\n'
mkdir -p "$IB/packages"
cp -f "${MOMO_IPKS[@]}" "$IB/packages/"
cp -f "$TINY_IPK" "$IB/packages/"
(
  cd "$IB"
  make package_index
)

PACKAGES="\
momo luci-app-momo luci-i18n-momo-zh-cn sing-box \
kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun kmod-dummy \
kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis \
kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim \
luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn \
-luci-app-attendedsysupgrade -attendedsysupgrade-common -luci-i18n-attendedsysupgrade-zh-cn"

printf '\n[5/7] Generate manifest and TR1200 Test1 image...\n'
(
  cd "$IB"
  make manifest PROFILE="$PROFILE" PACKAGES="$PACKAGES" > "$OUT/packages-manifest.txt"
  make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" V=s
)

find "$IB/bin/targets/ramips/mt76x8" -maxdepth 1 -type f \
  \( -name '*cudy_tr1200-v1*sysupgrade.bin' -o -name '*cudy_tr1200-v1*initramfs-kernel.bin' \) \
  -exec cp -f {} "$OUT/" \;

SYSUPGRADE="$(find "$OUT" -maxdepth 1 -type f -name '*cudy_tr1200-v1*sysupgrade.bin' | head -n1)"
INITRAMFS="$(find "$OUT" -maxdepth 1 -type f -name '*cudy_tr1200-v1*initramfs-kernel.bin' | head -n1)"
[ -f "$SYSUPGRADE" ] || { echo "sysupgrade image missing" >&2; exit 7; }

printf '\n[6/7] Audit package list and image size...\n'
for p in momo luci-app-momo luci-i18n-momo-zh-cn sing-box kmod-nft-tproxy kmod-nft-socket kmod-tun kmod-dummy kmod-usb-net-rndis kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim; do
  grep -Eq "^${p}([[:space:]]| - )" "$OUT/packages-manifest.txt" || { echo "Manifest missing: $p" >&2; exit 8; }
done

# Our fake package must be the installed sing-box package; this prevents a real Go binary package from silently replacing it.
if ! grep -E '^sing-box([[:space:]]| - ).*99\.0\.0-r1' "$OUT/packages-manifest.txt" >/dev/null; then
  echo "Wrong sing-box package selected. DO NOT FLASH." >&2
  grep -E '^sing-box' "$OUT/packages-manifest.txt" || true
  exit 9
fi

SIZE="$(stat -c%s "$SYSUPGRADE")"
MIB="$(awk -v n="$SIZE" 'BEGIN { printf "%.3f", n/1048576 }')"
STATUS="PASS"
if [ "$SIZE" -gt "$MAX_BYTES" ]; then STATUS="OVER_9.5_MiB"; fi

cat > "$OUT/build-info.txt" <<INFO
TR1200 Test1
Base: ImmortalWrt 24.10.6 ramips/mt76x8
Profile: cudy_tr1200-v1
Momo: v1.2.1 (OpenWrt 24.10, mipsel_24kc release package)
sing-box package in flash: 99.0.0-r1 wrapper only
Real sing-box core path at runtime: /tmp/sing-box
Core download trigger: only when /usr/bin/sing-box is actually invoked; Momo disabled => no download
Core source (Test1): kiddin9/bin mipsel_24kc via jsDelivr
USB: RNDIS + CDC Ethernet + NCM + MBIM
sysupgrade bytes: $SIZE
sysupgrade MiB: $MIB
9.5 MiB size target: $STATUS
INFO

(
  cd "$OUT"
  sha256sum ./*.bin ./*.ipk 2>/dev/null > SHA256SUMS || sha256sum ./*.bin > SHA256SUMS
)
cp -f "$TINY_IPK" "$OUT/"
cp -f "$TINY_IPK.sha256" "$OUT/"

printf '\n[7/7] Build complete.\n'
echo "sysupgrade: $SYSUPGRADE"
echo "size: $MIB MiB ($SIZE bytes)"
echo "status: $STATUS"
if [ "$STATUS" != PASS ]; then
  echo "WARNING: image exceeds 9.5 MiB target; inspect before flashing." >&2
fi
