# Running k on sw-os-ml

Design note for porting kbm's k (k edu on BareMetal-OS, x86-64 + AVX-512)
to **sw-os-ml** (MLOS: a `no_std` Rust OS that boots on aarch64 and x86-64
under QEMU from one tree), with **QEMU aarch64 first** and the hand-written
assembly replaced by Rust.

Status: analysis plus a working portability spike on branch
`spike/portable-k`. Nothing here has been built into an sw-os-ml kernel
yet: this sandbox could not install sw-os-ml's pinned toolchain
(Rust 1.96 + bare targets), so the kernel-side parts are designed from
source, not run.

## 1. What k actually needs from an OS

Read from kbm's sources (`ksrc/`, `s.asm`, `sys.c`):

| Need | kbm on BareMetal | Notes |
| --- | --- | --- |
| Read a line | `b_k` nr 0 → `b_read` → polled `b_input`, echoes each char | No backspace handling. k reads with `read(fd = <bytes written by the ' ' prompt>)`, i.e. fd 1, so on Linux stdin must be a tty. |
| Write bytes | nr 1 → `b_output` | |
| Exit | nr 60 → machine `SHUTDOWN` | Reached from the `\\` command. Does not return. |
| Files (`\l`) | nr 2/3/5/9/11 (open/close/fstat/mmap/munmap) → `-1` | Unsupported on BareMetal; k degrades gracefully. |
| Cycle counter | `rdtsc` (`ut`, for `\t` timing) | aarch64 path in `z.h` uses `cntvct_el0`. |
| Memory | static `_[1<<24]` of 64-byte vectors = **1 GiB BSS** | Buddy allocator in `b.c`, 30 size classes. |
| CPU | `-march=icelake-client`: **960** zmm/mask instructions | Only 8 AVX-512 *builtins*; the rest is compiler-generated from portable vector types. |

That is a very small OS contract. Everything else in k is self-contained
C: no libc, no allocator from the host, no threads.

## 2. What the spike established

On `spike/portable-k` (`test/README.md` has the commands):

1. **AVX-512 is optional.** `ksrc/kvec.h` replaces the 8 builtins
   (`bg bi a4 A0 A2 S6 _q X9`) with plain vector C. `test/kvec_diff.c`
   checks each against the real instruction on 20,000 random inputs: all
   agree bit-for-bit.
2. **The OS boundary is one function.** With `-DKSYS`, all eight OS calls
   go through `U k_sys(U nr, U a..f)` (x86-64 Linux numbering, which kbm's
   `s.asm` already uses). Only integers and pointers cross it.
3. **k runs on Cortex-A72.** The same sources built for aarch64
   (`-mcpu=cortex-a72`, NEON, no SVE) pass the golden transcripts under
   `qemu-aarch64`, identical to the original AVX-512 build run natively and
   to an AVX2-only x86-64 build. Cortex-A72 is the CPU sw-os-ml's
   `mlos run` uses under TCG.
4. **No regression.** `make` still produces a byte-identical `k.app`.

Also found, and worth knowing before trusting kbm's README:

- `make bochs` no longer works on a fresh setup. BareMetal's kernel
  history was squashed (Jan 2026) and its ATA driver removed; Bochs has no
  virtio, so BareMetal HEAD cannot load `k.app`. The Monitor's `setup.sh`
  also curls the API from BareMetal *master*. `test/pin-baremetal-2024.sh`
  rebuilds the Dec-2024 set (the kernel survives only via a PR ref).
- kbm's makefile copies `ksrc/*.[hc]` only when the **makefile** changes
  (`_.h: makefile`), so edits under `ksrc/` silently don't rebuild.
- Floats print as `?.?`: float formatting is stubbed in `z.h` (no libc).

## 3. Where sw-os-ml stands relative to that contract

From `sw-os-ml` at `5feb8c2` (citations are in that repo):

| k needs | sw-os-ml today | Gap |
| --- | --- | --- |
| FP/SIMD | **Off by design.** aarch64 kernel is `aarch64-unknown-none-softfloat`, nothing writes `CPACR_EL1`; x86-64 never sets `CR4.OSFXSR`/`XCR0`. Trap entry saves no FP state on either arch. `docs/design.md`: "Tensor math is userspace's job." | Must enable FP for k and keep the rest of the kernel FP-free. |
| User mode | None: one kernel thread at EL1/ring 0; `mlsh` runs in-kernel. | k would run in-kernel (option A) or needs EL0 (option B). |
| Console line input | UART IRQ → `mlos_queue` (64-byte SPSC) → `mlsh` pumps it; `mlos_line` edits (96 bytes). | Need a blocking `read` for k on top of the same queue. |
| Console output | `mlos_device::Console::write`, polled, `\n` → `\r\n`. | Direct fit. |
| Timer | `GenericTimer::now()` (`cntpct_el0`), TSC on x86. | Direct fit. |
| 1 GiB heap | QEMU `-m 512` (`mlos_image_map::RAM_BYTES`); aarch64 maps RAM in 1 GiB blocks; x86-64 identity-maps only the first 1 GiB. | Shrink k's heap or grow RAM; x86 page tables need more PDPT entries for big heaps. |
| C code in the image | None: no `cc`, `build.rs` only passes the linker script. | Add a C build step for one object. |
| Loader | None (`mlos-elf` is host-only). | Link k into the image (option A). |

## 4. Options

**A. k as an in-kernel lane (recommended first).** `mlsh` gets a `k`
command that enters k's REPL on the same console; `\\` returns to `mlsh`.
k is C, compiled once per arch into a static library linked into the
kernel. `k_sys` is Rust.
- Fits the current single-thread, no-userspace model and the existing
  command table (`crates/mlsh/src/commands.rs`).
- Cost: an FP "ownership" invariant inside the kernel (section 5.2).

**B. k as an EL0/ring-3 task.** Matches sw-os-ml's stated design ("tensor
math is userspace's job"): k gets its own address space, `svc`/`syscall`
lands in a Rust handler that implements the same `k_sys` table, and FP
state is saved on the user/kernel boundary.
- Cost: user mode, per-task page tables, syscall entry, FP context switch
  — a milestone of its own on both arches.
- Benefit: a real place for any future user workload, not just k.

**C. Rewrite k in Rust.** Not recommended now. k's value is that it is
Arthur Whitney's interpreter, unchanged; a rewrite loses the golden
equivalence that makes the port checkable.

A is a strict subset of B's work (same `k_sys`, same C build, same tests),
so doing A first does not waste effort: B later moves the same `k_sys`
behind a syscall boundary.

## 5. Design for option A

### 5.1 Components

```
mlsh ──"k"──▶ mlos-k (Rust, forbid(unsafe))      kbm/ksrc (C, unchanged + kvec/ksys)
               │  REPL session: enter/exit,         a.c z.c  ─ clang ─▶ libk.a
               │  line discipline (mlos-line),      (-DKSYS, -mcpu=cortex-a72 /
               │  k_sys dispatch table               -march=x86-64-v2|v3)
               ▼
            mlos-k-ffi (driver-class crate: the only unsafe)
               │  extern "C" k_sys(...) export, k_main import,
               │  FP enable/disable, enter/exit trampoline (naked asm, per arch)
               ▼
            Console / mlos_queue / Timer (existing)
```

Two crates, matching AGENTS.md's rules: policy and parsing in a
`forbid(unsafe)` crate; FFI, FP control registers and the context
trampoline in one driver-class crate with `// SAFETY:` on each block.
Both stay inside the size gate (≤4 modules, ≤4 functions/module target).

### 5.2 FP/SIMD ownership (the key invariant)

- **aarch64:** set `CPACR_EL1.FPEN = 0b11` (+ `isb`) on entry to k, back
  to `0b00` on exit. While k runs, the timer and UART IRQs still fire;
  their handlers are softfloat Rust and never touch V registers, so no FP
  save is needed — *as long as that stays true*.
- **x86-64:** on entry set `CR0.EM=0, MP=1`, `CR4.OSFXSR|OSXMMEXCPT`, and
  for AVX also `CR4.OSXSAVE` + `XCR0 = x87|SSE|AVX`. Same invariant for the
  IRQ stub (it saves no SSE state today).
- **Make the invariant checked, not hoped for:** a test in the pre-commit
  gate disassembles the kernel image and fails if any FP/SIMD register
  appears outside the `libk.a` symbols. That turns "handlers are softfloat"
  into a traceable, enforced property. With FPEN=0 outside k, any stray FP
  use in the kernel also traps instead of silently corrupting k's state.
- Option B replaces this with a normal save/restore on the EL0 boundary.

### 5.3 Entering and leaving k

k's `main` never returns; `\\` calls `exit`. `mlos-k-ffi` provides a
setjmp-style trampoline (callee-saved registers + SP, ~10 instructions per
arch): `k_enter` saves the shell's context, switches to a dedicated k
stack and calls `main`; `k_sys(60, …)` restores it, so `exit` returns to
`mlsh` with FP disabled again. k's heap persists between sessions unless
the command is `k reset`.

### 5.4 `k_sys` in Rust

Same numbers as `ksrc/ksys.h`:

| nr | Behavior in sw-os-ml |
| --- | --- |
| 0 read | Block on `mlos_queue::pop()` + `idle`; edit with `mlos_line` (echo, backspace, CR→LF); return one line including `\n`. Fixes BareMetal's missing backspace. |
| 1 write | `Console::write`. |
| 60 exit | Trampoline back to `mlsh`. |
| 2/5/9 open, fstat, mmap | Phase 3: serve scripts from a read-only table on virtio-blk (the device already exists); until then `-ENOSYS`, as on BareMetal. |
| other | `-ENOSYS`. |

`mlos-k` gets host-side `cargo test`s for the line discipline and table,
and — because the spike shows k builds for the host — a host test that
links k with the *Rust* `k_sys` and runs the golden transcripts. That
covers the whole boundary under `cargo test`, before any VM boots.

### 5.5 Memory

- Parametrize the heap: `-DKHEAP_LOG2=N` sizes `_[1<<N]` (default 24 =
  1 GiB, unchanged for kbm). Start at 22 (256 MiB) under the current
  512 MiB `-m`, or raise `RAM_BYTES`.
- **Risk to resolve first:** `b.c` seeds free lists for 30 size classes
  at offsets up to `64 * (2^29 - 1)` from the array base, far beyond even
  the 1 GiB array; they are only touched if a block of that class is ever
  split. Shrinking the array therefore needs a bound check in `m_` (fail
  allocation instead of walking off the end). Write a stress golden that
  allocates to exhaustion before changing the size.
- The heap is BSS, zeroed by boot code 8 bytes at a time — slow for
  hundreds of MiB under TCG. Either zero it lazily on first `k` entry
  with a vector loop, or place it in its own section the boot code skips.
- x86-64: the identity map covers 0–1 GiB; a heap above that needs more
  PDPT entries (`mlos-hal-x86-64/src/entry.s`).

### 5.6 Build

- `build.rs` in `mlos-k-ffi` runs `clang --target=aarch64-none-elf
  -mcpu=cortex-a72 -ffreestanding -nostdlib -fno-builtin -DKSYS ...`
  (or `x86_64-none-elf -march=x86-64-v2`) on `a.c`/`z.c` and emits
  `cargo::rustc-link-lib=static=k`. Use the `cc` crate only if adding a
  dependency is acceptable; a direct `clang` call keeps `Cargo.lock`
  workspace-only as it is today.
- k's source enters sw-os-ml as a git subtree/submodule of kbm-fork's
  `ksrc/` at a pinned commit, so goldens and source move together.
- The k object is FP-enabled while the kernel is softfloat; that link is
  ABI-safe because `k_sys`/`k_main` pass only integers and pointers
  (verified by keeping the boundary in `ksys.h` integer-only).

## 6. Plan

| Phase | Deliverable | Acceptance |
| --- | --- | --- |
| P0 (done) | Portable k + golden harness | `test/host/run-golden.sh` green on avx512, x86v3, aarch64 |
| P1 | `mlos-k` + `mlos-k-ffi` host build: Rust `k_sys`, k linked for the host | `cargo test` runs the goldens through the Rust `k_sys` |
| P2 | aarch64 kernel: `k` command, FP enable, trampoline, heap at 256 MiB | `mlsh.run=k` + scripted input under `mlos run` (TCG, Cortex-A72) matches goldens; FP-confinement check in the gate |
| P3 | x86-64 kernel (microvm, TCG, `-march=x86-64-v2`), SSE/AVX enable | Same goldens on x86-64 |
| P4 | Files: `\l` from virtio-blk | Golden that loads a `.k` script |
| P5 (option B) | EL0/ring-3 k task, syscall entry, FP context switch | Same goldens; FP check relaxed to "saved on boundary" |

Each phase is one sw-os-ml saga step under its agentrail protocol.

## 7. Non-functional notes

- **Reliability / traceability:** goldens are the single source of truth
  for "k behaves the same"; every build (host, aarch64, x86-64, kernel)
  runs the same transcripts. The FP-confinement check makes the one risky
  kernel invariant explicit.
- **Maintainability:** k's sources stay Whitney's code plus two headers;
  all OS adaptation lives in Rust behind one function.
- **Performance:** expect a large drop vs. native AVX-512 under TCG; the
  portable helpers are scalar loops in a few places (`bg`, `A0`, `S6`).
  Profile with k's own `\t` after P2, then replace hot helpers with NEON
  (`vqtbl4q_u8` is a direct match for `vpermb`; `vmull_p64` for `X9`) —
  each guarded by `kvec_diff`. Under HVF on Apple Silicon, k runs at
  native speed.
- **Usability:** `k` inside `mlsh`, `\\` back out; line editing that
  BareMetal lacked.
- **Upgradability:** pinning kbm's `ksrc/` by commit; goldens re-blessed
  only from the reference AVX-512 build.

## 8. Open questions

1. A or B first? A is faster to a demo; B matches sw-os-ml's own design
   statement about where tensor math belongs.
2. Heap size target under the 512 MiB VM, or raise `RAM_BYTES`?
3. Is adding the `cc` crate acceptable, or should `build.rs` call clang
   directly to keep `Cargo.lock` workspace-only?
4. Float printing: keep the `?.?` stub (goldens depend on it) or add a
   small Rust formatter behind a new `k_sys` call (and re-bless)?
