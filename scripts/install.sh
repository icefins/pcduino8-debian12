#!/bin/bash
# pcDuino8 Debian 12 SD card installer (run on a Linux host)
# Usage: sudo ./install.sh /dev/sdX pcduino8-debian12-rootfs.tar.xz [boot_dir]
set -euo pipefail

DISK="${1:?usage: sudo ./install.sh /dev/sdX rootfs.tar.xz [boot_dir]}"
TARBALL="${2:?usage: sudo ./install.sh /dev/sdX rootfs.tar.xz [boot_dir]}"
BOOTDIR="${3:-$(dirname "$0")/../boot}"

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
[ -b "$DISK" ] || { echo "not a block device: $DISK"; exit 1; }
[ -f "$TARBALL" ] || { echo "rootfs tarball not found: $TARBALL"; exit 1; }
[ -f "$BOOTDIR/uImage" ] || { echo "boot files not found in $BOOTDIR"; exit 1; }

SIZE=$(blockdev --getsize64 "$DISK")
# pcDuino8 SD: 100GB .. 140GB class (guard against writing the wrong disk)
if [ "$SIZE" -lt 100000000000 ] || [ "$SIZE" -gt 140000000000 ]; then
  echo "ABORT: $DISK size $(numfmt --to=iec "$SIZE") is not a 100-140GB card"
  exit 1
fi
echo "==> target: $DISK ($(numfmt --to=iec "$SIZE"))"
read -r -p "==> THIS WILL ERASE THE CARD. Type 'yes' to continue: " ans
[ "$ans" = "yes" ] || { echo "aborted"; exit 1; }

P1=$(lsblk -nrpo NAME "$DISK" | sed -n 2p || true)
if [ -n "$P1" ]; then
  for m in $(lsblk -nrpo MOUNTPOINT "$DISK" | grep -v '^$'); do umount "$m" || true; done
fi

echo "==> partitioning (matches stock pcDuino8 MBR: type 83, no boot flag)"
sfdisk "$DISK" <<'EOF'
label: dos
start=2048, size=71680, type=83
start=73728, size=65536, type=83
start=139264, type=83
EOF
partprobe "$DISK" || true
sleep 2

P1P="${DISK}1"; P2P="${DISK}2"; P3P="${DISK}3"
# some kernels name them p1/p2/p3
[ -b "$P1P" ] || { P1P="${DISK}p1"; P2P="${DISK}p2"; P3P="${DISK}p3"; }

echo "==> filesystems"
mkfs.vfat -F 16 -n BOOT "$P1P" >/dev/null
mkfs.vfat -F 32 -n KERNEL "$P2P" >/dev/null
mkfs.ext4 -F -L rootfs "$P3P" >/dev/null

echo "==> boot files -> p2"
MP=$(mktemp -d)
mount "$P2P" "$MP"
cp "$BOOTDIR/uImage" "$BOOTDIR/uEnv.txt" "$BOOTDIR/script.bin" "$BOOTDIR/bootlogo.bmp" "$MP/"
sync
umount "$MP"

echo "==> rootfs -> p3 (this takes a while)"
mount "$P3P" "$MP"
tar -xpf "$TARBALL" -C "$MP"
sync
e2fsck -fy "$P3P" >/dev/null || true
umount "$MP"
rmdir "$MP"

echo "==> done. Insert the card into pcDuino8 and power on."
echo "    default login: ssh linaro@<dhcp-ip>  (password: linaro)"
