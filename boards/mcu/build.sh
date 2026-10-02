#!/usr/bin/env bash
# boards/mcu/build.sh -- bare-metal (no OS) k for microcontroller-class CPUs,
# with QEMU stand-ins for the real boards.
#
#   boards/mcu/build.sh           build everything into boards/mcu/build/,
#                                 k libraries into boards/mcu/dist/
#   boards/mcu/build.sh --test    also run the goldens in QEMU
#
# k itself only compiles with clang (it uses clang-only builtins), but board
# SDKs (ESP-IDF, Pico SDK) use GCC. So k is shipped as a clang-built static
# library, dist/libk-<abi>.a (k's main renamed k_main), and the SDK project
# compiles only common/ksys-bare.c plus its own con_getc/con_putc/con_exit.
#
# Targets ("clang" = all clang + ld.lld; "gcc" = GCC glue linked against the
# clang libk.a exactly as an SDK build would, proving the ABI match):
#   rv32imafc-virt        clang  RV32IMAFC ilp32f   ESP32-P4 ISA            KHEAP=13
#   rv32imac-virt         clang  RV32IMAC ilp32     RP2350 Hazard3, C3/C6   KHEAP=12
#   m33-an505             clang  Cortex-M33 hard    RP2350 Arm cores        KHEAP=12
#   rv32imafc-virt-gcc    gcc    as ESP-IDF links   (libk-rv32imafc-ilp32f)
#   m33-an505-softfp-gcc  gcc    as the Pico SDK    (libk-m33-softfp; the SDK
#                                builds RP2350 with -mfloat-abi=softfp)
# RAM = .data+.bss+stack (must fit SRAM); text runs from flash on the chips.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
K="$ROOT/ksrc"; B="$HERE/build"; D="$HERE/dist"; mkdir -p "$B" "$D"
KCF="-Ofast -fno-builtin -funsigned-char -fno-unwind-tables -Wno-parentheses -Wno-incompatible-pointer-types
     -Wno-psabi -Wfatal-errors -nostdlib -ffreestanding -fomit-frame-pointer -DKSYS -Dmain=k_main -I$K"
RVLIB=/usr/lib/gcc/riscv64-unknown-elf
QV="qemu-system-riscv32 -M virt -cpu rv32 -m 16M -bios none -display none -monitor none -serial stdio -no-reboot -kernel"
QM="qemu-system-arm -M mps2-an505 -cpu cortex-m33 -display none -monitor none -serial none -chardev stdio,id=c0 -semihosting-config enable=on,target=native,chardev=c0 -no-reboot -kernel"

RV_IMAFC="--target=riscv32-unknown-elf -march=rv32imafc -mabi=ilp32f -mcmodel=medany"
RV_IMAC="--target=riscv32-unknown-elf -march=rv32imac -mabi=ilp32 -mcmodel=medany"
M33_HARD="--target=thumbv8m.main-none-eabihf -mcpu=cortex-m33 -mfloat-abi=hard -mfpu=fpv5-sp-d16 -mthumb"
M33_SOFTFP="--target=thumbv8m.main-none-eabi -mcpu=cortex-m33 -mfloat-abi=softfp -mfpu=fpv5-sp-d16 -mthumb"

libk() { # abi-name, clang flags, k flags -> dist/libk-<abi>.a
    # Override k flags per ABI, e.g. KFLAGS_rv32imafc_ilp32f="-DKHEAP=12 -DKOBJ=10"
    local abi=$1 tf=$2 kf=$3 var="KFLAGS_${1//-/_}"; kf=${!var:-$kf}
    clang $KCF $tf $kf -c "$K/a.c" -o "$B/a-$abi.o"
    clang $KCF $tf $kf -c "$K/z.c" -o "$B/z-$abi.o" 2>/dev/null
    rm -f "$D/libk-$abi.a"; llvm-ar rcs "$D/libk-$abi.a" "$B/a-$abi.o" "$B/z-$abi.o" 2>/dev/null ||
        ar rcs "$D/libk-$abi.a" "$B/a-$abi.o" "$B/z-$abi.o"
}
report() { # name, elf, budget KB
    local text ram; read -r text ram < <(size -A "$2" | awk '/^\.text/{t=$2} /^\.(data|bss|stack)/{r+=$2} END{print t, r}')
    printf '%-21s text(flash)=%4d KB  RAM=%4d KB of %4d KB\n' "$1" $((text/1024)) $((ram/1024)) "$3"
    (( ram/1024 <= $3 )) || { echo "  over the SRAM budget"; fail=1; }
}
gtest() { # name, elf, qemu prefix
    [[ ${TEST:-0} == 1 ]] || return 0
    local out="$B/$1.golden.out"
    if timeout 600 python3 "$ROOT/test/drive_qemu.py" "$ROOT/test/golden/basic.k" $3 "$2" > "$out" 2>"$B/$1.err" &&
       diff -q "$ROOT/test/golden/basic.expected" "$out" >/dev/null; then
        echo "  PASS goldens (${3%% -*} ${3#* -M } )" | sed -E 's/ -[a-z].*\)/)/; s/ \)/)/'
    else echo "  FAIL goldens (see $out)"; fail=1; fi
}
clang_target() { # name, platform dir, clang flags, abi, libgcc, qemu, budget
    local name=$1 plat=$2 tf=$3 abi=$4 libgcc=$5 qemu=$6 budget=$7 objs=()
    for src in "$HERE/common/ksys-bare.c" "$HERE/common/libc-min.c" "$HERE/$plat"/*.c "$HERE/$plat"/*.S; do
        [[ -f $src ]] || continue
        local o="$B/$(basename "${src%.*}")-$name.o"
        clang $tf -O2 -ffreestanding -nostdlib -c "$src" -o "$o"; objs+=("$o")
    done
    ld.lld -T "$HERE/$plat/link.ld" "${objs[@]}" "$D/libk-$abi.a" "$libgcc" -o "$B/k-$name.elf"
    report "$name" "$B/k-$name.elf" "$budget"; gtest "$name" "$B/k-$name.elf" "$qemu"
}
gcc_target() { # name, platform dir, gcc driver, gcc flags, abi, qemu, budget
    local name=$1 plat=$2 cc=$3 gf=$4 abi=$5 qemu=$6 budget=$7 srcs=()
    for src in "$HERE/common/ksys-bare.c" "$HERE/common/libc-min.c" "$HERE/$plat"/*.c "$HERE/$plat"/*.S; do
        [[ -f $src ]] && srcs+=("$src")
    done
    $cc $gf -O2 -ffreestanding -nostdlib -nostartfiles -T "$HERE/$plat/link.ld" "${srcs[@]}" \
        "$D/libk-$abi.a" -lgcc -o "$B/k-$name.elf"
    report "$name" "$B/k-$name.elf" "$budget"; gtest "$name" "$B/k-$name.elf" "$qemu"
}

[[ ${1:-} == --test ]] && TEST=1
fail=0
libk rv32imafc-ilp32f "$RV_IMAFC" "-DKHEAP=13 -DKOBJ=10"
libk rv32imac-ilp32   "$RV_IMAC"  "-DKHEAP=12 -DKOBJ=10"
libk m33-hard         "$M33_HARD" "-DKHEAP=12 -DKOBJ=10"
libk m33-softfp       "$M33_SOFTFP" "-DKHEAP=12 -DKOBJ=10"

clang_target rv32imafc-virt rv32-virt "$RV_IMAFC" rv32imafc-ilp32f "$(ls $RVLIB/*/rv32imafc/ilp32f/libgcc.a | head -1)" "$QV" 768
clang_target rv32imac-virt  rv32-virt "$RV_IMAC"  rv32imac-ilp32  "$(ls $RVLIB/*/rv32imac/ilp32/libgcc.a | head -1)" "$QV" 520
clang_target m33-an505      m33-an505 "$M33_HARD" m33-hard \
    "$(arm-none-eabi-gcc -mthumb -march=armv8-m.main+fp -mfloat-abi=hard -print-libgcc-file-name)" "$QM" 520
gcc_target rv32imafc-virt-gcc rv32-virt riscv64-unknown-elf-gcc "-march=rv32imafc -mabi=ilp32f -mcmodel=medany" \
    rv32imafc-ilp32f "$QV" 768
gcc_target m33-an505-softfp-gcc m33-an505 arm-none-eabi-gcc "-mthumb -mcpu=cortex-m33 -mfloat-abi=softfp -mfpu=fpv5-sp-d16" \
    m33-softfp "$QM" 520
(cd "$D" && sha256sum libk-*.a > SHA256SUMS)
exit $fail
