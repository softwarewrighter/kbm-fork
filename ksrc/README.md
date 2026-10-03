# ksrc: k (Arthur Whitney's k edu) and its port layer

`a.c`, `b.c`, `z.c`, `_.h`, `a.h`, `z.h` are k as kbm shipped it, with small,
guarded changes for portability. Added headers:

| File | Purpose |
| --- | --- |
| `kvec.h` | portable stand-ins for the 8 AVX-512 helpers (used without `__AVX512F__`) |
| `ksys.h` | `-DKSYS`: every OS call goes through one C function, `k_sys(nr, a..f)` |
| `kheap.h` | `-DKHEAP=n` / `-DKOBJ=n`: heap and handle-table size, `wsfull` instead of overrun |

## Compilers

k builds with **clang** (any target clang supports) or **GCC**.

clang needs only k's usual flags:
`-Ofast -fno-builtin -funsigned-char -Wno-parentheses -Wno-incompatible-pointer-types -Wno-psabi`.

GCC additionally needs:

```
-Ofast -flax-vector-conversions -fno-strict-aliasing -fno-builtin -funsigned-char
-Wno-incompatible-pointer-types -Wno-attributes -Wno-psabi
-Wno-pointer-to-int-cast -Wno-int-to-pointer-cast -Wno-parentheses
```

- `-flax-vector-conversions`: k converts freely between same-size integer
  vector types.
- `-Wno-incompatible-pointer-types`: k puns pointers everywhere; GCC 14 turns
  this warning into an error by default.
- `-Ofast` (not `-O2`): lets GCC inline vector square roots; without it,
  freestanding builds call a missing `sqrtf`.
- `-fno-strict-aliasing`: belt and braces for the pointer punning (the
  goldens pass with and without it).

### What changed to make GCC work

clang accepts some vector conversions GCC rejects: float<->int vector
reinterpretation, and arithmetic or comparisons between different vector
types (clang converts the right operand to the left operand's type). Those
sites now carry the cast clang applies implicitly. Each edit was checked by
compiling a.c and z.c with clang for 8 targets (x86-64 AVX-512, v3, v2;
aarch64; rv64; armv7; rv32imafc; Cortex-M33) and comparing the object files
byte for byte with the originals: all identical. Where an explicit cast would
change clang's instruction selection (one line in `b.c`, `nz`), clang keeps
the original text under `#if __clang__`.

Also for GCC only:
- `__builtin_convertvector`, `__builtin_elementwise_max/sqrt` have element-loop
  equivalents (`_.h`, `a.h`, `kvec.h`).
- k's four functions named `$e $i $m $q` are renamed (`z.h`): GNU as treats
  `$`-prefixed symbols as ARM mapping symbols, so a pointer to `$e` lost its
  Thumb bit and calling it faulted on Cortex-M.

Verified: GCC-built k passes `test/golden/basic.k` on x86-64 Linux
(`test/host/run-golden.sh`), bare-metal RV32IMAFC and bare-metal Cortex-M33
softfp in QEMU (`boards/mcu/build.sh --test`, `*-gccsrc` targets). The
original BareMetal `k.app` (clang, AVX-512) is still byte-identical.

## Rules for editing these files

- k's macros take most one- and two-letter names (`b`, `f`, `nr`, `x`, ...):
  don't use them as identifiers, and never put a bare comma inside a k macro
  argument (use `;` or extra parentheses).
- After any change: `test/host/run-golden.sh`, `boards/linux/build.sh --test`,
  `boards/mcu/build.sh --test`, and `test/check-kapp-hash.sh`.
