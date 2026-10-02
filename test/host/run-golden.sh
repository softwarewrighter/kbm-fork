#!/usr/bin/env bash
# run-golden.sh -- build k three ways and check each against test/golden/.
#
#   avx512   ksrc as kbm ships it (AVX-512 builtins), run natively. Needs an
#            AVX-512 (VBMI2) host. This build defines the goldens.
#   x86v3    -DKSYS, portable kvec.h, -march=x86-64-v3 (AVX2, no zmm).
#   aarch64  -DKSYS, portable kvec.h, Cortex-A72 (Armv8.0 + NEON), run under
#            qemu-aarch64 -- the CPU sw-os-ml uses under TCG.
# Also runs kvec_diff: each portable helper vs the AVX-512 instruction.
#
#   test/host/run-golden.sh           verify every build
#   test/host/run-golden.sh --bless   regenerate .expected from the avx512 build
# The goldens characterize *current* behavior (`nyi` verbs, the `?.?` float
# stub) so any port is diffed against what k does today.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
K="$HERE/../../ksrc"
cd "$HERE"
mkdir -p build

grep -qw avx512_vbmi2 /proc/cpuinfo || { echo "host CPU lacks AVX-512 (VBMI2): cannot build the reference k" >&2; exit 2; }
command -v qemu-aarch64 >/dev/null || { echo "qemu-aarch64 (qemu-user) not installed" >&2; exit 2; }

CF="-Ofast -fno-builtin -funsigned-char -fno-unwind-tables -Wno-parentheses -Wno-incompatible-pointer-types
    -Wno-psabi -Wfatal-errors -nostdlib -ffreestanding -fomit-frame-pointer -fno-pie -I$K"
kbuild() { # name, flags...
    local n=$1; shift
    clang $CF "$@" -c "$K/a.c" -o "build/a-$n.o"
    clang $CF "$@" -c "$K/z.c" -o "build/z-$n.o"
}
# avx512: original code path, b_k = raw syscall (host-linux.S)
kbuild avx512 -march=icelake-client
clang -c host-linux.S -o build/s-avx512.o
ld.lld -static build/s-avx512.o build/a-avx512.o build/z-avx512.o -o build/k-avx512
# portable builds: k_sys from ksys-linux.c
kbuild x86v3 -march=x86-64-v3 -DKSYS
clang -O2 -ffreestanding -nostdlib -fno-pie -c ksys-linux.c -o build/ks-x86v3.o
ld.lld -static build/z-x86v3.o build/a-x86v3.o build/ks-x86v3.o -o build/k-x86v3
A64="--target=aarch64-linux-gnu -mcpu=cortex-a72"
kbuild aarch64 $A64 -DKSYS
clang $A64 -O2 -ffreestanding -nostdlib -fno-pie -c ksys-linux.c -o build/ks-aarch64.o
ld.lld -static build/z-aarch64.o build/a-aarch64.o build/ks-aarch64.o -o build/k-aarch64
(( $(objdump -d build/k-x86v3 | grep -c zmm) == 0 )) || { echo "x86v3 build contains AVX-512" >&2; exit 1; }

fail=0
clang -O2 -march=icelake-client -funsigned-char -ffreestanding -nostdlib -fno-builtin -fno-pie \
      -Wno-parentheses -Wno-incompatible-pointer-types -I"$K" ../kvec_diff.c start-min.S \
      -static -fuse-ld=lld -o build/kvec_diff
if build/kvec_diff >build/kvec_diff.out; then echo "PASS kvec_diff (8 helpers == AVX-512)"; else cat build/kvec_diff.out; fail=1; fi

declare -A RUN=([avx512]="build/k-avx512" [x86v3]="build/k-x86v3"
                [aarch64]="qemu-aarch64 -cpu cortex-a72 build/k-aarch64")
for k in ../golden/*.k; do
    exp=${k%.k}.expected
    for b in avx512 x86v3 aarch64; do
        # Drop the banner line: it embeds the build date (__DATE__).
        got=$(K_STEP=${K_STEP:-1.5} python3 run_host.py "${RUN[$b]}" "$k" | tail -n +2)
        if [[ ${1:-} == --bless ]]; then
            [[ $b == avx512 ]] && { printf '%s\n' "$got" > "$exp"; echo "BLESSED $k"; }
            continue
        fi
        if diff -u "$exp" <(printf '%s\n' "$got") > "build/$(basename "$k" .k)-$b.diff"; then
            echo "PASS $b $(basename "$k")"
        else
            echo "FAIL $b $(basename "$k")  (see build/$(basename "$k" .k)-$b.diff)"; fail=1
        fi
    done
done
exit $fail
