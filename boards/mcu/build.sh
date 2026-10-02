#!/usr/bin/env bash
# boards/mcu/build.sh -- bare-metal (no OS) k for microcontroller-class CPUs,
# with QEMU stand-ins for the real boards.
#
#   boards/mcu/build.sh           build all into boards/mcu/build/
#   boards/mcu/build.sh --test    also run the goldens in QEMU
#
# Target          ISA (as the board)                 QEMU stand-in       heap
# rv32imafc-virt  RV32IMAFC, ilp32f: ESP32-P4          riscv32 virt, UART  KHEAP=13 (512 KiB)
# rv32imac-virt   RV32IMAC soft-float: RP2350 Hazard3  riscv32 virt, UART  KHEAP=12 (256 KiB)
# m33-an505       Cortex-M33 + FPU: RP2350 Arm cores   mps2-an505, semihost KHEAP=12 (256 KiB)
#
# "RAM" below is .data+.bss+stack: what must fit in the chip's SRAM. Code
# (.text) runs from flash on the real chips (XIP).
# The board-specific parts are only boards/mcu/<target>/{start,plat}.* --
# see docs/hw-bringup/ for replacing them with ESP-IDF or the Pico SDK.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
K="$ROOT/ksrc"; B="$HERE/build"; mkdir -p "$B"
CF="-Ofast -fno-builtin -funsigned-char -fno-unwind-tables -Wno-parentheses -Wno-incompatible-pointer-types
    -Wno-psabi -Wfatal-errors -nostdlib -ffreestanding -fomit-frame-pointer -DKSYS -I$K"
RVLIB=/usr/lib/gcc/riscv64-unknown-elf
QV="qemu-system-riscv32 -M virt -cpu rv32 -m 16M -bios none -display none -monitor none -serial stdio -no-reboot -kernel"
QM="qemu-system-arm -M mps2-an505 -cpu cortex-m33 -display none -monitor none -serial none -chardev stdio,id=c0 -semihosting-config enable=on,target=native,chardev=c0 -no-reboot -kernel"

# name | platform dir | clang flags | libgcc | k flags | qemu prefix | SRAM budget (KB)
TARGETS=(
  "rv32imafc-virt|rv32-virt|--target=riscv32-unknown-elf -march=rv32imafc -mabi=ilp32f -mcmodel=medany|$(ls $RVLIB/*/rv32imafc/ilp32f/libgcc.a 2>/dev/null | head -1)|-DKHEAP=13 -DKOBJ=10|$QV|768"
  "rv32imac-virt|rv32-virt|--target=riscv32-unknown-elf -march=rv32imac -mabi=ilp32 -mcmodel=medany|$(ls $RVLIB/*/rv32imac/ilp32/libgcc.a 2>/dev/null | head -1)|-DKHEAP=12 -DKOBJ=10|$QV|520"
  "m33-an505|m33-an505|--target=thumbv8m.main-none-eabihf -mcpu=cortex-m33 -mfloat-abi=hard -mfpu=fpv5-sp-d16 -mthumb|$(arm-none-eabi-gcc -mthumb -march=armv8-m.main+fp -mfloat-abi=hard -print-libgcc-file-name 2>/dev/null || true)|-DKHEAP=12 -DKOBJ=10|$QM|520"
)

fail=0
for t in "${TARGETS[@]}"; do
    IFS='|' read -r name plat tf libgcc kf qemu budget <<<"$t"
    [[ -f $libgcc ]] || { echo "$name: libgcc not found (apt: gcc-riscv64-unknown-elf / gcc-arm-none-eabi)" >&2; exit 2; }
    clang $CF $tf $kf -c "$K/a.c" -o "$B/a-$name.o"
    clang $CF $tf $kf -c "$K/z.c" -o "$B/z-$name.o" 2>/dev/null
    objs=("$B/a-$name.o" "$B/z-$name.o")
    for src in "$HERE/common/ksys-bare.c" "$HERE/$plat"/*.c "$HERE/$plat"/*.S; do
        [[ -f $src ]] || continue
        o="$B/$(basename "${src%.*}")-$name.o"
        clang $tf -O2 -ffreestanding -nostdlib -c "$src" -o "$o"; objs=("$o" "${objs[@]}")
    done
    ld.lld -T "$HERE/$plat/link.ld" "${objs[@]}" "$libgcc" -o "$B/k-$name.elf"
    read -r text ram < <(size -A "$B/k-$name.elf" | awk '/^\.text/{t=$2} /^\.(data|bss|stack)/{r+=$2} END{print t, r}')
    printf '%-15s text(flash)=%4d KB  RAM=%4d KB of %4d KB\n' "$name" $((text/1024)) $((ram/1024)) "$budget"
    (( ram/1024 <= budget )) || { echo "  over the SRAM budget"; fail=1; }
    if [[ ${1:-} == --test ]]; then
        out="$B/$name.golden.out"
        if timeout 600 python3 "$ROOT/test/drive_qemu.py" "$ROOT/test/golden/basic.k" $qemu "$B/k-$name.elf" > "$out" 2>"$B/$name.err" &&
           diff -q "$ROOT/test/golden/basic.expected" "$out" >/dev/null; then
            echo "  PASS goldens (${qemu%% -kernel*})" | sed 's/ -[a-z].*)/)/'
        else echo "  FAIL goldens (see $out)"; fail=1; fi
    fi
done
exit $fail
