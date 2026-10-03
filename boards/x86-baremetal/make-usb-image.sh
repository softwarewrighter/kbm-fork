#!/usr/bin/env bash
# boards/x86-baremetal/make-usb-image.sh -- a UEFI USB-stick image that boots
# BareMetal-OS with k, for x86-64 boards without AVX-512 (e.g. Atomic Pi).
#
#   B=../BareMetal-OS boards/x86-baremetal/make-usb-image.sh [screen|serial]
#
# Output: boards/x86-baremetal/dist/k-usb-<console>.img, a FAT32 image with
# EFI/BOOT/BOOTX64.EFI. Write it to a USB stick (see docs/hw-bringup/atomic-pi.md)
# and boot it from the board's UEFI boot menu.
#
# Why this layout: current BareMetal's only disk driver is virtio-blk, so on
# real hardware it cannot read the USB stick or eMMC. The UEFI firmware loads
# BOOTX64.EFI for us, and BOOTX64.EFI carries a 1 MiB RAM drive; k.app lives
# there, so no storage driver is ever needed. At the Monitor prompt:
#   load   (then 1)   exec
# The Monitor auto-runs init.app only from a disk filesystem, not the RAM
# drive, so those three commands are typed by hand.
#
# Consoles:
#   screen  stock kernel: UEFI framebuffer (HDMI) + USB keyboard (xHCI)
#   serial  kernel assembled with -dNO_VGA -dNO_LFB: COM1 is the console
#           (for QEMU testing, or a board with a legacy serial port)
#
# Env: KHEAP (default 22 = 256 MiB heap; unset to use k's original 1 GiB,
#      which needs >= 1.5 GB RAM).
set -euo pipefail
CONSOLE=${1:-screen}
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
B=$(cd -- "${B:-$ROOT/../BareMetal-OS}" && pwd)
SYS="$B/sys"; OUT="$HERE/dist"; W="$HERE/build"; mkdir -p "$OUT" "$W"
KHEAP=${KHEAP-22}

for f in uefi.sys pure64-uefi.sys kernel.sys monitor.bin bmfslite; do
    [[ -e "$SYS/$f" ]] || { echo "missing $SYS/$f: run ./baremetal.sh setup in $B" >&2; exit 1; }
done
command -v mformat >/dev/null || { echo "need mtools" >&2; exit 1; }

echo "[1/4] k.app: make PORTABLE=1 ${KHEAP:+KHEAP=$KHEAP}"
(cd "$ROOT" && make -s PORTABLE=1 ${KHEAP:+KHEAP=$KHEAP} B="$B" >/dev/null)
(( $(objdump -d "$ROOT/k" | grep -cE '%[yz]mm') == 0 )) || { echo "k uses AVX; not for this CPU" >&2; exit 1; }

echo "[2/4] kernel ($CONSOLE console)"
case $CONSOLE in
    screen) cp "$SYS/kernel.sys" "$W/kernel.sys" ;;
    serial) (cd "$B/src/BareMetal/src" && nasm -dNO_VGA -dNO_LFB kernel.asm -o "$W/kernel.sys") ;;
    *) echo "console must be screen or serial" >&2; exit 2 ;;
esac
cat "$SYS/pure64-uefi.sys" "$W/kernel.sys" "$SYS/monitor.bin" > "$W/software-uefi.sys"
(( $(stat -c %s "$W/software-uefi.sys") <= 32768 )) || { echo "Pure64+kernel+Monitor exceeds 32 KiB" >&2; exit 1; }

echo "[3/4] BOOTX64.EFI with k.app in its RAM drive"
dd if=/dev/zero of="$W/ramdrive.img" bs=1M count=1 status=none
cp "$SYS/k.app" "$W/k.app"
(cd "$W" && "$SYS/bmfslite" ramdrive.img initialize >/dev/null && "$SYS/bmfslite" ramdrive.img write k.app >/dev/null)
cp "$SYS/uefi.sys" "$W/BOOTX64.EFI"
dd if="$W/software-uefi.sys" of="$W/BOOTX64.EFI" bs=4096 seek=1 conv=notrunc status=none
dd if="$W/ramdrive.img" of="$W/BOOTX64.EFI" bs=1024 seek=64 conv=notrunc status=none

echo "[4/4] FAT32 USB image"
img="$OUT/k-usb-$CONSOLE.img"
rm -f "$img"; dd if=/dev/zero of="$img" bs=1M count=64 status=none
mformat -i "$img" -F -v KBM ::
mmd -i "$img" ::/EFI ::/EFI/BOOT
mcopy -i "$img" "$W/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mdir -i "$img" ::/EFI/BOOT | grep -i bootx64
echo "OK: $img"
