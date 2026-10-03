#!/usr/bin/env bash
# boards/linux/build.sh -- static, libc-free k binaries for the Linux boards.
#
#   boards/linux/build.sh            build all into boards/linux/dist/
#   boards/linux/build.sh --test     also run the goldens on each under qemu-user
#
# Each binary needs nothing on the board: no libc, no Python. Copy it over
# (scp or SD card) and run it from a terminal (k reads from its tty).
#
# Heap (-DKHEAP, see ksrc/kheap.h) is sized to leave the board's Linux room:
#   licheerv-nano-rv64   SG2002 C906 (RV64GC)      256 MB RAM -> KHEAP=20 (64 MiB)
#   licheerv-nano-a53    SG2002 Cortex-A53 (ARM boot mode)    -> KHEAP=20
#   luckfox-rv1103       RV1103 Cortex-A7 (32-bit), 64 MB RAM -> KHEAP=18 (16 MiB)
#   atomicpi-x86v2       Atom x5-Z8350 (SSE4.2, no AVX), 2 GB  -> KHEAP=20 (64 MiB)
#                        tested under qemu-x86_64 -cpu Westmere (no AVX either)
# Override with KHEAP_<NAME>=n, e.g. KHEAP_luckfox_rv1103=17.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
K="$ROOT/ksrc"; HOST="$ROOT/test/host"
OUT="$HERE/dist"; OBJ="$HERE/build"
mkdir -p "$OUT" "$OBJ"

CF="-Ofast -fno-builtin -funsigned-char -fno-unwind-tables -Wno-parentheses -Wno-incompatible-pointer-types
    -Wno-psabi -Wfatal-errors -nostdlib -ffreestanding -fomit-frame-pointer -fno-pie -DKSYS -I$K"

# name | clang target flags | default KHEAP | qemu-user runner | extra link inputs
BOARDS=(
  "licheerv-nano-rv64|--target=riscv64-linux-gnu -march=rv64gc -mabi=lp64d|20|qemu-riscv64 -cpu rv64|"
  "licheerv-nano-a53|--target=aarch64-linux-gnu -mcpu=cortex-a53|20|qemu-aarch64 -cpu cortex-a53|"
  "atomicpi-x86v2|--target=x86_64-linux-gnu -march=x86-64-v2|20|qemu-x86_64 -cpu Westmere|"
  "luckfox-rv1103|--target=armv7a-linux-gnueabihf -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard|18|qemu-arm -cpu cortex-a7|LIBGCC_ARM"
)
LIBGCC_ARM=$(ls /usr/lib/gcc-cross/arm-linux-gnueabihf/*/libgcc.a 2>/dev/null | head -1 || true)

fail=0
for b in "${BOARDS[@]}"; do
    IFS='|' read -r name tflags kheap runner extra <<<"$b"
    var="KHEAP_${name//-/_}"; kheap=${!var:-$kheap}
    link=()
    if [[ $extra == LIBGCC_ARM ]]; then
        [[ -n $LIBGCC_ARM ]] || { echo "need ARM libgcc (apt: libgcc-13-dev-armhf-cross)" >&2; exit 2; }
        link=("$LIBGCC_ARM")
    fi
    clang $CF $tflags -DKHEAP="$kheap" -c "$K/a.c" -o "$OBJ/a-$name.o"
    clang $CF $tflags -DKHEAP="$kheap" -c "$K/z.c" -o "$OBJ/z-$name.o" 2>/dev/null
    clang $tflags -O2 -ffreestanding -nostdlib -fno-pie -fno-builtin -c "$HOST/ksys-linux.c" -o "$OBJ/ks-$name.o"
    ld.lld -static "$OBJ/z-$name.o" "$OBJ/a-$name.o" "$OBJ/ks-$name.o" "${link[@]}" -o "$OUT/k-$name"
    bss=$(llvm-size -A "$OUT/k-$name" 2>/dev/null | awk '/\.bss/{print $2}' || size -A "$OUT/k-$name" | awk '/\.bss/{print $2}')
    printf '%-20s KHEAP=%-2s file=%6s B  RAM(bss)=%s B\n' "$name" "$kheap" "$(stat -c %s "$OUT/k-$name")" "$bss"
    if [[ ${1:-} == --test ]]; then
        got=$(K_STEP=${K_STEP:-1.5} python3 "$HOST/run_host.py" "$runner $OUT/k-$name" "$ROOT/test/golden/basic.k" | tail -n +2)
        if diff -q "$ROOT/test/golden/basic.expected" <(printf '%s\n' "$got") >/dev/null; then
            echo "  PASS goldens under ${runner%% *}"
        else echo "  FAIL goldens under ${runner%% *}"; fail=1; fi
    fi
done
(cd "$OUT" && sha256sum k-* > SHA256SUMS)
exit $fail
