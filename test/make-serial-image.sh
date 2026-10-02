#!/usr/bin/env bash
# make-serial-image.sh -- build a headless (serial-console) BareMetal disk
# image that boots straight into k, for automated testing of kbm.
#
# Targets the Dec-2024 BareMetal set kbm was written against
# (see pin-baremetal-2024.sh). In that version:
#   - the kernel's b_output writes to COM1 and b_input polls COM1,
#   - the Monitor's ui_init unconditionally repoints b_output (0x100018)
#     at its framebuffer renderer,
#   - the Monitor auto-runs the program when BMFS holds exactly one file.
# So the only change needed for a serial console is a Monitor variant
# without that one redirect. It is assembled here, into test/out/; the
# BareMetal checkout is left untouched.
#
# Inputs : $B (default ../../BareMetal-OS-2024) with sys/ built, and
#          `make B=$B` run in kbm-fork (sys/k.app exists).
# Output : test/out/k-serial.img  (FAT32+BMFS hybrid disk, BIOS boot)
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
B=$(cd -- "${B:-$HERE/../../BareMetal-OS-2024}" && pwd)
SYS="$B/sys"
OUT="$HERE/out"
mkdir -p "$OUT"

for f in k.app pure64-bios.sys kernel.sys bios.sys fat32.img bmfs; do
    [[ -e "$SYS/$f" ]] || { echo "missing $SYS/$f (run pin-baremetal-2024.sh and make B=$B first)" >&2; exit 1; }
done

echo "[1/4] assembling Monitor variant that leaves stdout on COM1"
mon="$OUT/monitor-src"
rm -rf "$mon"; cp -r "$B/src/BareMetal-Monitor/src" "$mon"
redirect='^\s*mov \[0x100018\], rax'
n=$(grep -cE "$redirect" "$mon/ui/ui.asm" || true)
(( n == 1 )) || { echo "expected exactly one stdout redirect in ui.asm, found $n" >&2; exit 1; }
sed -i -E "s/$redirect/\t; (serial test image) stdout left on COM1/" "$mon/ui/ui.asm"
(cd "$mon" && nasm monitor.asm -o "$OUT/monitor-serial.bin")

echo "[2/4] concatenating Pure64 + kernel + Monitor"
cat "$SYS/pure64-bios.sys" "$SYS/kernel.sys" "$OUT/monitor-serial.bin" > "$OUT/software-serial.sys"
size=$(stat -c %s "$OUT/software-serial.sys")
(( size <= 32768 )) || { echo "software image too large: $size bytes" >&2; exit 1; }

echo "[3/4] creating BMFS volume holding only k.app (so the Monitor auto-runs it)"
bmfs="$OUT/bmfs-serial.img"
dd if=/dev/zero of="$bmfs" bs=1M count=128 status=none
cp "$SYS/k.app" "$OUT/k.app"
(cd "$OUT" && "$SYS/bmfs" "$bmfs" format /force >/dev/null && "$SYS/bmfs" "$bmfs" write k.app >/dev/null)
rm -f "$OUT/k.app"
dd if="$OUT/software-serial.sys" of="$bmfs" bs=4096 seek=2 conv=notrunc status=none

echo "[4/4] assembling FAT32+BMFS hybrid disk with the BIOS MBR"
# Same layout baremetal.sh builds for baremetal_os.img: the Monitor looks
# for BMFS at a 128 MiB offset, i.e. after the FAT32 partition.
fat="$OUT/fat32-serial.img"
cp "$SYS/fat32.img" "$fat"
dd if="$SYS/bios.sys" of="$fat" bs=1 count=3 conv=notrunc status=none
dd if="$SYS/bios.sys" of="$fat" bs=1 skip=90 seek=90 count=356 conv=notrunc status=none
dd if="$SYS/bios.sys" of="$fat" bs=1 skip=510 seek=510 count=2 conv=notrunc status=none
cat "$fat" "$bmfs" > "$OUT/k-serial.img"
rm -f "$fat"
"$SYS/bmfs" "$bmfs" list 2>/dev/null || true
echo "OK: $OUT/k-serial.img"
