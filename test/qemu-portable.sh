#!/usr/bin/env bash
# qemu-portable.sh -- run `make PORTABLE=1` kbm on *current* BareMetal under
# QEMU (TCG, no AVX-512): the path that works on a Mac.
#
#   test/qemu-portable.sh            interactive: k on this terminal (serial)
#   test/qemu-portable.sh --test     run test/golden/*.k and diff
#
# Env: B (BareMetal-OS checkout, default ../BareMetal-OS next to kbm-fork),
#      MEM (QEMU -m in MiB, default 2048: k reserves a 1 GiB static heap).
#
# Builds test/out/k-head.img: Pure64 + a serial-console kernel
# (-dNO_VGA -dNO_LFB: COM1 is both stdout and keyboard) + Monitor, FAT32+BMFS
# hybrid, with k stored as init.app, which the Monitor runs at boot.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
B=$(cd -- "${B:-$HERE/../../BareMetal-OS}" && pwd)
SYS="$B/sys"; OUT="$HERE/out"; MEM=${MEM:-2048}
mkdir -p "$OUT"

(cd "$HERE/.." && make -s PORTABLE=1 B="$B" >/dev/null)
(( $(objdump -d "$HERE/../k" | grep -c zmm) == 0 )) || { echo "k still contains AVX-512" >&2; exit 1; }

(cd "$B/src/BareMetal/src" && nasm -dNO_VGA -dNO_LFB kernel.asm -o "$OUT/kernel-head-serial.sys")
cat "$SYS/pure64-bios.sys" "$OUT/kernel-head-serial.sys" "$SYS/monitor.bin" > "$OUT/software-head.sys"
bmfs="$OUT/bmfs-head.img"
dd if=/dev/zero of="$bmfs" bs=1M count=128 status=none
cp "$SYS/k.app" "$OUT/init.app"
(cd "$OUT" && "$SYS/bmfs" "$bmfs" format /force >/dev/null && "$SYS/bmfs" "$bmfs" write init.app >/dev/null)
rm -f "$OUT/init.app"
dd if="$OUT/software-head.sys" of="$bmfs" bs=4096 seek=2 conv=notrunc status=none
fat="$OUT/fat32-head.img"; cp "$SYS/fat32.img" "$fat"
dd if="$SYS/bios.sys" of="$fat" bs=1 count=3 conv=notrunc status=none
dd if="$SYS/bios.sys" of="$fat" bs=1 skip=90 seek=90 count=356 conv=notrunc status=none
dd if="$SYS/bios.sys" of="$fat" bs=1 skip=510 seek=510 count=2 conv=notrunc status=none
cat "$fat" "$bmfs" > "$OUT/k-head.img"; rm -f "$fat"

QEMU=(qemu-system-x86_64 -machine q35 -cpu Westmere -smp 1 -m "$MEM"
      -display none -monitor none -serial stdio -no-reboot
      -drive "id=disk0,file=$OUT/k-head.img,if=none,format=raw,snapshot=on"
      -device virtio-blk-pci,drive=disk0)

if [[ ${1:-} != --test ]]; then
    echo "k on BareMetal (QEMU, serial). Type k; \\\\ exits and shuts down." >&2
    exec "${QEMU[@]}"
fi
fail=0
for k in "$HERE"/golden/*.k; do
    if python3 "$HERE/drive_qemu.py" "$k" "${QEMU[@]}" > "$OUT/$(basename "$k" .k).qemu.out" &&
       diff -u "${k%.k}.expected" "$OUT/$(basename "$k" .k).qemu.out"; then
        echo "PASS qemu-portable $(basename "$k")"
    else echo "FAIL qemu-portable $(basename "$k")"; fail=1; fi
done
exit $fail
