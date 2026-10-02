# Bring-up plan: Linux boards (LicheeRV Nano, Luckfox RV1103)

Both boards run Linux, so k needs no SDK and no driver: a single static,
libc-free binary that makes raw syscalls (`test/host/ksys-linux.c`). Both
builds already pass the goldens under qemu-user; this plan is about getting
them onto the boards and confirming it there.

## Build

```sh
boards/linux/build.sh --test        # builds boards/linux/dist/, runs goldens under qemu-user
```

| Binary | For | Heap | RAM needed (BSS) |
|---|---|---|---|
| `k-licheerv-nano-rv64` | Nano, C906 (RV64GC), normal boot | KHEAP=20, 64 MiB | ~64 MiB |
| `k-licheerv-nano-a53` | Nano, Cortex-A53 (ARM boot mode) | KHEAP=20 | ~64 MiB |
| `k-luckfox-rv1103` | Luckfox Pico RV1103, Cortex-A7 | KHEAP=18, 16 MiB | ~16 MiB |

Change a heap with e.g. `KHEAP_luckfox_rv1103=17 boards/linux/build.sh`.
Linux allocates BSS pages lazily, but it may refuse to start a program whose
BSS exceeds free memory (overcommit heuristics), so size the heap to what
`free -m` reports on the running board, leaving room for the system.

k reads input from its terminal (it calls `read` on fd 1), so run it from a
real terminal: serial console, `ssh -t`, or `adb shell`. Piping input into
it does not work.

## LicheeRV Nano (SG2002)

### Goal 1: k on the C906 (RISC-V, the board's default)

1. Prepare the board with Sipeed's Linux image per their docs (SD card).
   Get a shell: USB serial console, or network (USB-RNDIS / Ethernet,
   depending on the board variant). Note the image version.
2. On the board: `uname -m` (expect `riscv64`), `free -m`.
3. Copy the binary: `scp boards/linux/dist/k-licheerv-nano-rv64 root@<nano>:/root/k`
   (or put it on the SD card's root filesystem from the bring-up machine).
4. Smoke test on the board: `/root/k`, then type `1+2` (expect `3`) and
   `\\` to exit.
5. Acceptance over ssh, from the bring-up machine:
   `boards/linux/test-on-board.sh root@<nano> /root/k`
   Use key-based ssh (`BatchMode=yes` is set).
6. Heap limit: run `test/limits/heap.k` the same way (k should print
   `wsfull`). Note KHEAP=20 normally will not hit it; build a
   `KHEAP_licheerv_nano_rv64=12` copy to see `wsfull`.
7. Optional, performance: k's `\t expr` reports a timing, but its counter
   scaling was written for x86 TSCs, so treat numbers as relative only.
   Compare a heavier expression (e.g. `x:!1000000` then `x*x`) between
   the board and qemu-riscv64, using wall-clock time.

Notes:
- The C906 also has a draft vector extension (RVV 0.7.1). clang targets
  RVV 1.0 only, so the build is scalar `rv64gc`. That is deliberate.
- If the image's kernel lacks something (unlikely for a static binary),
  record `dmesg` output.

### Goal 2 (investigation): k on the A53

The SG2002 can boot its Cortex-A53 instead of the C906. Whether Sipeed's
images or SDK support this on the Nano, and how to select it, is **not
verified**. Steps:
1. Search Sipeed/Sophgo docs for ARM boot on SG2002 (the related
   SG2000/Milk-V Duo S documents a boot-core switch).
2. If an ARM image exists, repeat Goal 1 with `k-licheerv-nano-a53`.
3. Record what you found either way; that is a useful result.

## Luckfox Pico (RV1103)

The RV1103's application core is a 32-bit Cortex-A7 (it also has a small
RISC-V MCU core, which is not used here). The board has 64 MB of RAM, much
of it used by the system and camera stack, hence the 16 MiB heap.

1. Flash Luckfox's Buildroot (or Ubuntu) image per their docs (SD card or
   SPI NAND, depending on the model). Note image version and model.
2. Get a shell: `adb shell` over USB if the image enables adb (Luckfox's
   Buildroot images usually do), serial console, or ssh over USB-RNDIS.
3. On the board: `uname -m` (expect `armv7l`), `free -m`, and
   `cat /proc/cpuinfo | grep -i features` (expect `neon vfpv4`; the build
   uses hard-float NEON).
4. Copy: `adb push boards/linux/dist/k-luckfox-rv1103 /root/k` (or scp).
   `chmod +x /root/k`.
5. Smoke test: `adb shell` then `/root/k`, `1+2`, `\\`.
6. Acceptance:
   - over ssh: `boards/linux/test-on-board.sh root@<luckfox> /root/k`
   - over adb (adb shell allocates a tty when run interactively):
     `python3 test/host/run_host.py "adb shell -t /root/k" test/golden/basic.k | tail -n +2 | diff test/golden/basic.expected -`
     (if `-t` is rejected by your adb, try `adb shell` with the command
     quoted; the requirement is a tty on the remote side)
7. Heap limit: `test/limits/heap.k` with a `KHEAP_luckfox_rv1103=12` build
   should print `wsfull`.

Risks to watch:
- If the binary will not start ("cannot allocate memory" or killed), lower
  the heap (`KHEAP_luckfox_rv1103=17` or `16`).
- `ld.lld` links ARM libgcc for 64-bit math; if the kernel reports an
  illegal instruction, capture `dmesg` and the faulting address and check it
  with `llvm-objdump -d`.

## Results

(Fill in per board: date, board revision, image version, build command,
heap, acceptance pass/fail, notes.)
