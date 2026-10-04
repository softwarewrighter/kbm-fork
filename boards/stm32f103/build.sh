#!/usr/bin/env bash
# boards/stm32f103/build.sh -- k firmware for an STM32F103C8 board (Cortex-M3,
# 72 MHz, no FPU, 20 KB SRAM), bare metal, no SDK.
#
#   boards/stm32f103/build.sh          -> build/k-stm32f103.{elf,bin,hex}
#   boards/stm32f103/build.sh --test   also build the QEMU stand-in (netduino2,
#                                      same code, F2 USART address) and run the
#                                      goldens on it
#
# Knobs (environment): KHEAP=7 (8 KiB heap), KOBJ=7 (128 handles),
# STACK=6144 (bytes kept free for the stack), FLASH_KB=128 (see link.ld),
# KSTACK_REPORT=1 (print the stack high-water mark on exit).
# Needs gcc-arm-none-eabi (+ libnewlib-arm-none-eabi for libgcc multilibs).
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
K="$ROOT/ksrc"; B="$HERE/build"; mkdir -p "$B"
CC=${CC:-arm-none-eabi-gcc}; OBJCOPY=${CC%gcc}objcopy; SIZE=${CC%gcc}size
KHEAP=${KHEAP:-7}; KOBJ=${KOBJ:-7}; STACK=${STACK:-6144}; FLASH_KB=${FLASH_KB:-128}
ARCH="-mcpu=cortex-m3 -mthumb -mfloat-abi=soft"
# GCC flags k needs (ksrc/README.md), at -Os: smallest code (~85 KB) and, on
# RV32, ~3.7 KiB of stack where -Ofast needed 8.9 KiB (see boards/ch582).
KF="-Os -flax-vector-conversions -fno-strict-aliasing -fno-builtin -funsigned-char -ffreestanding
    -ffunction-sections -fdata-sections -Wno-incompatible-pointer-types -Wno-attributes -Wno-psabi
    -Wno-pointer-to-int-cast -Wno-int-to-pointer-cast -Wno-parentheses
    -DKSYS -Dmain=k_main -DKHEAP=$KHEAP -DKOBJ=$KOBJ -I$K"
PF="-Os -ffreestanding -ffunction-sections -fdata-sections -Wall"
[[ ${KSTACK_REPORT:-0} == 1 ]] && PF="$PF -DKSTACK_REPORT"

$CC $ARCH $KF -c "$K/a.c" -o "$B/a.o"
$CC $ARCH $KF -c "$K/z.c" -o "$B/z.o"
$CC $ARCH -O2 -ffreestanding -c "$ROOT/boards/mcu/common/ksys-bare.c" -o "$B/ksys-bare.o"
$CC $ARCH -O2 -ffreestanding -fno-builtin -c "$ROOT/boards/mcu/common/libc-min.c" -o "$B/libc-min.o"

link() { # name, extra platform flags
    $CC $ARCH $PF $2 -c "$HERE/stm32f1.c" -o "$B/stm32f1-$1.o"
    $CC $ARCH -nostdlib -nostartfiles -Wl,--gc-sections -Wl,-Map="$B/$1.map" -T "$HERE/link.ld" \
        -Wl,--defsym=__stack_size="$STACK" -Wl,--defsym=__flash_size="$((FLASH_KB * 1024))" \
        "$B/stm32f1-$1.o" "$B/ksys-bare.o" "$B/libc-min.o" "$B/a.o" "$B/z.o" -lgcc -o "$B/$1.elf" \
        2> >(grep -v 'RWX\|has a LOAD segment' >&2)
    read -r flash ram < <($SIZE -A "$B/$1.elf" | awk '/^\.(text|ARM\.exidx|data)[ \t]/{f+=$2} /^\.(data|bss)[ \t]/{r+=$2} END{print f, r}')
    printf '%-16s KHEAP=%s KOBJ=%s  flash=%d KB (64 official, %d linked)  RAM=%d KB + %d KB stack of 20\n' \
        "$1" "$KHEAP" "$KOBJ" $((flash / 1024)) "$FLASH_KB" $((ram / 1024)) $((STACK / 1024))
}
link k-stm32f103 ""
$OBJCOPY -O binary "$B/k-stm32f103.elf" "$B/k-stm32f103.bin"
$OBJCOPY -O ihex   "$B/k-stm32f103.elf" "$B/k-stm32f103.hex"

if [[ ${1:-} == --test ]]; then
    link k-qemu-netduino2 "-DKQEMU_F2"
    q="qemu-system-arm -M netduino2 -display none -monitor none -serial stdio -no-reboot -kernel $B/k-qemu-netduino2.elf"
    fail=0
    for g in basic; do
        if timeout 600 python3 "$ROOT/test/drive_qemu.py" "$ROOT/test/golden/$g.k" $q > "$B/$g.out" 2>&1 &&
           diff -q "$ROOT/test/golden/$g.expected" "$B/$g.out" >/dev/null; then
            echo "  PASS $g.k (QEMU netduino2, Cortex-M3)"
        else echo "  FAIL $g.k (see $B/$g.out)"; fail=1; fi
    done
    timeout 300 python3 "$ROOT/test/drive_qemu.py" "$ROOT/test/limits/heap.k" $q 2>&1 | grep -q wsfull &&
        echo "  PASS heap.k -> wsfull" || { echo "  FAIL heap.k (no wsfull)"; fail=1; }
    exit $fail
fi
