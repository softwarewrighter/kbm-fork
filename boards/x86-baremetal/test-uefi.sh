#!/usr/bin/env bash
# boards/x86-baremetal/test-uefi.sh -- boot the serial USB image the way an
# Atomic Pi would: UEFI firmware (OVMF), image attached only as a USB stick,
# no virtio disk, Westmere CPU (no AVX), 2 GB. Types `loadr 1 exec` at the
# Monitor, then runs test/golden/*.k.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
IMG="$HERE/dist/k-usb-serial.img"
[[ -f $IMG ]] || "$HERE/make-usb-image.sh" serial
CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
VARS_SRC=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
[[ -f $CODE ]] || { echo "need OVMF (apt: ovmf; Arch: edk2-ovmf)" >&2; exit 2; }
VARS=$(mktemp); trap 'rm -f "$VARS"' EXIT; cp "$VARS_SRC" "$VARS"
fail=0
for k in "$ROOT"/test/golden/*.k; do
    cp "$VARS_SRC" "$VARS"
    out="$HERE/build/$(basename "$k" .k).uefi.out"
    if K_PRE="loadr;1;exec" timeout 600 python3 "$ROOT/test/drive_qemu.py" "$k" \
        qemu-system-x86_64 -machine q35 -cpu Westmere -m 2048 -display none -monitor none \
        -serial stdio -no-reboot \
        -drive "if=pflash,format=raw,readonly=on,file=$CODE" -drive "if=pflash,format=raw,file=$VARS" \
        -device qemu-xhci,id=xhci -drive "if=none,id=stick,format=raw,snapshot=on,file=$IMG" \
        -device usb-storage,bus=xhci.0,drive=stick > "$out" &&
       diff -u "${k%.k}.expected" "$out"; then
        echo "PASS uefi-usb $(basename "$k")"
    else echo "FAIL uefi-usb $(basename "$k") (see $out)"; fail=1; fi
done
exit $fail
