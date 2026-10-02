# kbm tests and portability spike

Everything here runs on a Linux host. Nothing in `ksrc/` changes behavior for
the original BareMetal build: `make` still produces a byte-identical `k.app`.

## What works

| Command | What it shows |
| --- | --- |
| `test/host/run-golden.sh` | k built three ways passes the same golden transcripts: **avx512** (kbm as shipped, native), **x86v3** (portable, AVX2, no zmm), **aarch64** (portable, Cortex-A72 under `qemu-aarch64`). Also runs `kvec_diff`. |
| `test/kvec_diff.c` | Each portable helper in `ksrc/kvec.h` vs the AVX-512 instruction it replaces, 20,000 random inputs each. |
| `test/pin-baremetal-2024.sh` | Rebuilds the Dec-2024 BareMetal set kbm was written against (see below for why HEAD fails). |
| `test/make-serial-image.sh` | Disk image that boots that BareMetal straight into k with the console on COM1. Under QEMU it reaches k and faults `#UD` on the first AVX-512 instruction, as expected for TCG. |

Requirements: clang + lld, an AVX-512 (VBMI2) host for the reference build,
`qemu-user` for aarch64, nasm/mtools for the BareMetal images.

See also `docs/k-on-sw-os-ml.md` for the plan to run k on sw-os-ml.

## The port boundary

- `ksrc/kvec.h` -- portable stand-ins for the 8 AVX-512 helpers in `a.h`
  (`bg bi a4 A0 A2 S6 _q X9`). Used only when `__AVX512F__` is off.
- `ksrc/ksys.h` -- with `-DKSYS`, all of k's OS calls go through one C-ABI
  function `k_sys(nr, a..f)` (x86-64 Linux numbering, which kbm's `s.asm`
  already uses). A host OS implements that one function; for sw-os-ml it
  would be Rust.
- `test/host/ksys-linux.c` -- `k_sys` for Linux on x86-64 and aarch64.

## Golden transcripts

`test/golden/*.k` with `.expected` produced by the avx512 build
(`run-golden.sh --bless`). They record current behavior, including verbs that
report `nyi` and the `?.?` float printer (float formatting is stubbed out in
`z.h` because there is no libc).

## Not working yet

- **kbm under Bochs, end to end.** Two upstream changes broke kbm's README
  path: BareMetal's kernel history was squashed in Jan 2026 and its ATA driver
  removed (virtio-blk only; Bochs has no virtio), and the Monitor/Demo
  `setup.sh` scripts fetch the API from BareMetal *master*. The pinned set
  fixes both, but Ubuntu 24.04's Bochs 2.7 then stalls early in boot
  (its own BIOS crashes; with SeaBIOS + VBE nothing reaches COM1). Next step:
  Bochs 2.8+ built from source with `--enable-evex`, as kbm's README does.
- Bochs 2.7 socket-mode COM1 did not deliver input in testing; `drive_k.py`
  assumes it does.
