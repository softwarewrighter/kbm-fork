#!/usr/bin/env bash
# run-golden.sh -- build k five ways and check each against test/golden/.
#
#   avx512   ksrc as kbm ships it (AVX-512 builtins), run natively. Needs an
#            AVX-512 (VBMI2) host. This build defines the goldens.
#   x86v3    -DKSYS, portable kvec.h, -march=x86-64-v3 (AVX2, no zmm).
#   aarch64  -DKSYS, portable kvec.h, Cortex-A72 (Armv8.0 + NEON), run under
#            qemu-aarch64 -- the CPU sw-os-ml uses under TCG.
#   rv64     -DKSYS, rv64gc (no vector), qemu-riscv64 -- e.g. LicheeRV Nano
#            (Sophgo SG2002, T-Head C906; its RVV 0.7.1 isn't targetable).
#   armv7    -DKSYS, Cortex-A7 + NEON, hard-float, 32-bit (ILP32), qemu-arm
#            -- e.g. Luckfox Pico (RV1103). Links libgcc for 64-bit math.
# Also runs kvec_diff: each portable helper vs the AVX-512 instruction.
#
#   test/host/run-golden.sh           verify every build
#   test/host/run-golden.sh --bless   regenerate .expected from the avx512 build
# The goldens characterize *current* behavior (`nyi` verbs, the `?.?` float
# stub) so any port is diffed against what k does today.
set -euo pipefail
# GCC needs these to accept k's style (clang accepts it as is): implicit
# integer-vector conversions, k's pointer punning, clang-only attributes,
# and 32-bit pointers widened into k's 64-bit words.
KGCC_FLAGS="-flax-vector-conversions -fno-strict-aliasing -fno-builtin -Wno-incompatible-pointer-types
  -Wno-attributes -Wno-psabi -Wno-pointer-to-int-cast -Wno-int-to-pointer-cast -Wno-parentheses"
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
K="$HERE/../../ksrc"
cd "$HERE"
mkdir -p build

# The AVX-512 reference build and kvec_diff need an AVX-512 (VBMI2) CPU. On
# other hosts (e.g. a Mac, most laptops) they are skipped: the committed
# .expected files are the reference, and the portable builds are checked
# against them.
HAVE512=0; grep -qw avx512_vbmi2 /proc/cpuinfo 2>/dev/null && HAVE512=1
[[ $HAVE512 == 1 || ${1:-} != --bless ]] || { echo "--bless needs an AVX-512 host" >&2; exit 2; }
for q in qemu-aarch64 qemu-riscv64 qemu-arm; do command -v $q >/dev/null || { echo "$q (qemu-user) not installed" >&2; exit 2; }; done

CF="-Ofast -fno-builtin -funsigned-char -fno-unwind-tables -Wno-parentheses -Wno-incompatible-pointer-types
    -Wno-psabi -Wfatal-errors -nostdlib -ffreestanding -fomit-frame-pointer -fno-pie -I$K"
kbuild() { # name, flags...
    local n=$1; shift
    clang $CF "$@" -c "$K/a.c" -o "build/a-$n.o"
    clang $CF "$@" -c "$K/z.c" -o "build/z-$n.o"
}
# avx512: original code path, b_k = raw syscall (host-linux.S)
if [[ $HAVE512 == 1 ]]; then
kbuild avx512 -march=icelake-client
clang -c host-linux.S -o build/s-avx512.o
ld.lld -static build/s-avx512.o build/a-avx512.o build/z-avx512.o -o build/k-avx512
fi
# portable builds: k_sys from ksys-linux.c
kbuild x86v3 -march=x86-64-v3 -DKSYS
clang -O2 -ffreestanding -nostdlib -fno-pie -c ksys-linux.c -o build/ks-x86v3.o
ld.lld -static build/z-x86v3.o build/a-x86v3.o build/ks-x86v3.o -o build/k-x86v3
A64="--target=aarch64-linux-gnu -mcpu=cortex-a72"
kbuild aarch64 $A64 -DKSYS
clang $A64 -O2 -ffreestanding -nostdlib -fno-pie -c ksys-linux.c -o build/ks-aarch64.o
ld.lld -static build/z-aarch64.o build/a-aarch64.o build/ks-aarch64.o -o build/k-aarch64
RV="--target=riscv64-linux-gnu -march=rv64gc -mabi=lp64d"
kbuild rv64 $RV -DKSYS
clang $RV -O2 -ffreestanding -nostdlib -fno-pie -fno-builtin -c ksys-linux.c -o build/ks-rv64.o
ld.lld -static build/z-rv64.o build/a-rv64.o build/ks-rv64.o -o build/k-rv64
A7="--target=armv7a-linux-gnueabihf -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
LIBGCC_ARM=$(ls /usr/lib/gcc-cross/arm-linux-gnueabihf/*/libgcc.a 2>/dev/null | head -1)
[[ -n $LIBGCC_ARM ]] || { echo "need ARM libgcc (apt: libgcc-13-dev-armhf-cross)" >&2; exit 2; }
kbuild armv7 $A7 -DKSYS
clang $A7 -O2 -ffreestanding -nostdlib -fno-pie -fno-builtin -c ksys-linux.c -o build/ks-armv7.o
ld.lld -static build/z-armv7.o build/a-armv7.o build/ks-armv7.o "$LIBGCC_ARM" -o build/k-armv7
(( $(objdump -d build/k-x86v3 | grep -c zmm) == 0 )) || { echo "x86v3 build contains AVX-512" >&2; exit 1; }

fail=0
if [[ $HAVE512 == 1 ]]; then
clang -O2 -march=icelake-client -funsigned-char -ffreestanding -nostdlib -fno-builtin -fno-pie \
      -Wno-parentheses -Wno-incompatible-pointer-types -I"$K" ../kvec_diff.c start-min.S \
      -static -fuse-ld=lld -o build/kvec_diff
if build/kvec_diff >build/kvec_diff.out; then echo "PASS kvec_diff (8 helpers == AVX-512)"; else cat build/kvec_diff.out; fail=1; fi
else echo "SKIP avx512 build and kvec_diff (host CPU lacks AVX-512)"; fi
BUILDS="x86v3 aarch64 rv64 armv7"; [[ $HAVE512 == 1 ]] && BUILDS="avx512 $BUILDS"
# GCC build of the same sources (k builds with clang or GCC; see ksrc/README.md)
if command -v gcc >/dev/null; then
    GF="-Ofast $KGCC_FLAGS -funsigned-char -fno-unwind-tables -nostdlib -ffreestanding -fomit-frame-pointer -fno-pie -DKSYS -I$K -march=x86-64-v3"
    gcc $GF -c "$K/a.c" -o build/a-gcc.o && gcc $GF -c "$K/z.c" -o build/z-gcc.o
    gcc -O2 -ffreestanding -nostdlib -fno-pie -c ksys-linux.c -o build/ks-gcc.o
    gcc -static -nostdlib -no-pie build/z-gcc.o build/a-gcc.o build/ks-gcc.o -lgcc -o build/k-gcc
    BUILDS="$BUILDS gcc"
fi

declare -A RUN=([avx512]="build/k-avx512" [x86v3]="build/k-x86v3" [gcc]="build/k-gcc"
                [aarch64]="qemu-aarch64 -cpu cortex-a72 build/k-aarch64"
                [rv64]="qemu-riscv64 -cpu rv64 build/k-rv64"
                [armv7]="qemu-arm -cpu cortex-a7 build/k-armv7")
for k in ../golden/*.k; do
    exp=${k%.k}.expected
    for b in $BUILDS; do
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

# Heap and handle limits (ksrc/kheap.h), on the fast native x86v3 build:
# small heaps still pass the goldens, and exhaustion stops with "wsfull"
# instead of writing past the end.
kbuild h12 -march=x86-64-v3 -DKSYS -DKHEAP=12
ld.lld -static build/z-h12.o build/a-h12.o build/ks-x86v3.o -o build/k-h12
kbuild obj4 -march=x86-64-v3 -DKSYS -DKHEAP=12 -DKOBJ=4
ld.lld -static build/z-obj4.o build/a-obj4.o build/ks-x86v3.o -o build/k-obj4
got=$(K_STEP=0.5 python3 run_host.py build/k-h12 ../golden/basic.k | tail -n +2)
if diff -q ../golden/basic.expected <(printf '%s\n' "$got") >/dev/null; then echo "PASS KHEAP=12 (256 KiB) basic.k"; else echo "FAIL KHEAP=12 basic.k"; fail=1; fi
check_full() { # name, binary, script
    if K_STEP=0.5 python3 run_host.py "$2" "$3" | tail -1 | grep -qx wsfull; then echo "PASS $1 -> wsfull"; else echo "FAIL $1 (no wsfull)"; fail=1; fi
}
check_full "heap exhaustion, KHEAP=12" build/k-h12 ../limits/heap.k
check_full "handle exhaustion, KOBJ=4" build/k-obj4 ../limits/handles.k
exit $fail
