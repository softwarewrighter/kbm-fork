#!/usr/bin/env bash
# boards/ch582/build.sh -- k firmware for the WCH CH582F (RV32IMAC, 32 KB SRAM,
# 448 KB flash), bare metal on WCH's CH583 EVT StdPeriphDriver.
#
#   boards/ch582/build.sh         -> boards/ch582/build/k-ch582.{elf,bin,hex}
#
# Fetches the EVT SDK (github.com/openwch/ch583, Apache-2.0) at a pinned commit
# into boards/ch582/.evt on first use; set CH58X_EVT=/path/to/ch583 to use a
# copy you already have. Compiler: CC=riscv64-unknown-elf-gcc (Debian/Ubuntu
# gcc-riscv64-unknown-elf, default) or CC=riscv-none-elf-gcc (xPack).
#
# RAM budget (32 KB): k's heap 2^KHEAP x 64 B (default KHEAP=8, 16 KiB) +
# handle table 8 B x 2^KOBJ (KOBJ=8, 2 KiB) + k's other statics (~2 KiB) +
# STACK (8 KiB; k peaks at ~3.7 KiB at -Os, see KOPT below). The link
# fails if they do not fit. Smaller: KHEAP=7 (8 KiB heap).
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
K="$ROOT/ksrc"; B="$HERE/build"; mkdir -p "$B"
CC=${CC:-riscv64-unknown-elf-gcc}; OBJCOPY=${OBJCOPY:-${CC%gcc}objcopy}; SIZE=${SIZE:-${CC%gcc}size}
KHEAP=${KHEAP:-8}; KOBJ=${KOBJ:-8}; STACK=${STACK:-8192}
EVT_REPO=https://github.com/openwch/ch583
EVT_REV=bd508ad   # 2025-08-14; the version this was built and tested with

EVT=${CH58X_EVT:-$HERE/.evt}
if [[ ! -d $EVT/EVT/EXAM/SRC ]]; then
    [[ -z ${CH58X_EVT:-} ]] || { echo "CH58X_EVT=$EVT has no EVT/EXAM/SRC" >&2; exit 2; }
    git clone -q "$EVT_REPO" "$EVT"
    git -C "$EVT" checkout -q "$EVT_REV"
fi
SRC=$EVT/EVT/EXAM/SRC
command -v "$CC" >/dev/null || { echo "need $CC (apt: gcc-riscv64-unknown-elf, or set CC)" >&2; exit 2; }

ARCH="-march=rv32imac_zicsr_zifencei -mabi=ilp32 -mcmodel=medlow -msmall-data-limit=8"
# WCH's MounRiver GCC 8 accepts plain rv32imac; newer GCC needs _zicsr.
$CC $ARCH -march=rv32imac_zicsr_zifencei -E -x c /dev/null >/dev/null 2>&1 || ARCH="${ARCH/_zicsr_zifencei/}"
# The SDK headers include <string.h>. xPack and MounRiver toolchains ship a libc;
# Debian's bare gcc-riscv64-unknown-elf does not, so borrow libnewlib-dev's
# (architecture-neutral) headers. Only declarations are used; nothing links libc.
LIBCINC=
if ! echo '#include <string.h>' | $CC $ARCH -E -x c - >/dev/null 2>&1; then
    [[ -f /usr/include/newlib/string.h ]] ||
        { echo "need C library headers: apt install libnewlib-dev (or use an xPack riscv-none-elf-gcc)" >&2; exit 2; }
    LIBCINC="-isystem /usr/include/newlib"
fi
SDKF="$ARCH $LIBCINC -Os -ffunction-sections -fdata-sections -fno-common -DINT_SOFT
      -I$SRC/StdPeriphDriver/inc -I$SRC/RVMSIS -Wno-int-conversion -Wno-implicit-function-declaration"
# GCC flags k needs (ksrc/README.md), but -Os instead of -Ofast: at -Ofast GCC
# inlines k's 64-byte generic vectors into one 6 KB stack frame (k_), and k
# needed 8.9 KB of stack for 1+2. At -Os it peaks at ~3.7 KB (clang -Ofast:
# ~3.5 KB) and the code is half the size. Measured in QEMU (rv32imac-ch582 stand-in).
KOPT=${KOPT:--Os}
KF="$KOPT -flax-vector-conversions -fno-strict-aliasing -fno-builtin -funsigned-char -ffreestanding
    -Wno-incompatible-pointer-types -Wno-attributes -Wno-psabi -Wno-pointer-to-int-cast -Wno-int-to-pointer-cast
    -Wno-parentheses -DKSYS -Dmain=k_main -DKHEAP=$KHEAP -DKOBJ=$KOBJ -I$K"

objs=()
cc1() { local o="$B/$(basename "${1%.*}").o"; $CC $2 -c "$1" -o "$o"; objs+=("$o"); }
cc1 "$K/a.c" "$ARCH $KF"
cc1 "$K/z.c" "$ARCH $KF"
cc1 "$ROOT/boards/mcu/common/ksys-bare.c" "$ARCH -O2 -ffreestanding"
cc1 "$ROOT/boards/mcu/common/libc-min.c"  "$ARCH -O2 -ffreestanding -fno-builtin"
cc1 "$HERE/con_ch58x.c" "$SDKF"
cc1 "$SRC/Startup/startup_CH583.S" "$ARCH"
for f in clk gpio sys pwr uart1; do cc1 "$SRC/StdPeriphDriver/CH58x_$f.c" "$SDKF"; done

# WCH's linker script with k's stack size (it reserves the stack at the top
# of RAM, so an oversized .bss makes the link fail rather than overlap).
sed "s/^__stack_size = [0-9]*;/__stack_size = $STACK;/" "$SRC/Ld/Link.ld" > "$B/link.ld"
$CC $ARCH -nostartfiles -nostdlib -Wl,--gc-sections -Wl,-Map="$B/k-ch582.map" -T "$B/link.ld" \
    "${objs[@]}" "$SRC/StdPeriphDriver/libISP583.a" -lgcc -o "$B/k-ch582.elf"
$OBJCOPY -O binary "$B/k-ch582.elf" "$B/k-ch582.bin"
$OBJCOPY -O ihex   "$B/k-ch582.elf" "$B/k-ch582.hex"
read -r flash ram < <($SIZE -A "$B/k-ch582.elf" | awk '
  /^\.(init|highcode|text|fini|preinit_array|init_array|fini_array|ctors|dtors|data)[ \t]/{f+=$2}
  /^\.(highcode|data|bss|stack)[ \t]/{r+=$2} END{print f, r}')
printf 'k-ch582.elf  KHEAP=%s KOBJ=%s stack=%s  flash=%d KB of 448  RAM=%d KB of 32\n' \
    "$KHEAP" "$KOBJ" "$STACK" $((flash/1024)) $((ram/1024))
