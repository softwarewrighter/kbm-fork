# Hardware bring-up: k on real boards

Plans for agents (or people) working on a machine with the boards attached
over USB, or with an SD-card writer. Everything up to the board itself has
been built and tested in emulation on branch `spike/portable-k`; what is
left is the last mile on real hardware.

Read this file first, then the board's own plan:

| Board | CPU | Runs k as | Plan |
|---|---|---|---|
| Sipeed LicheeRV Nano | SG2002: T-Head C906 (RV64GC) + Cortex-A53 | static Linux binary | [linux-boards.md](linux-boards.md) |
| Milk-V Duo / Duo 256M / Duo S | CV1800B / SG2002 / SG2000: C906 (RV64GC), A53 on 256M and S; 64 / 256 / 512 MB | static Linux binary | [milkv-duo.md](milkv-duo.md) |
| Luckfox Pico (RV1103) | Cortex-A7, 32-bit, 64 MB | static Linux binary | [linux-boards.md](linux-boards.md) |
| ESP32-S3 (N16R8) | 2x Xtensa LX7 + FPU, 512 KB SRAM, 8 MB octal PSRAM | ESP-IDF project `boards/esp-idf` | [esp32-s3.md](esp32-s3.md) |
| ESP32-P4 (Waveshare ESP32-P4-Module-DEV-KIT, chip v1.x) | 2x RV32IMAFC @ 360 MHz, 768 KB SRAM, 32 MB PSRAM | ESP-IDF project `boards/esp-idf` | [esp32-p4.md](esp32-p4.md) |
| Atomic Pi | Atom x5-Z8350 (x86-64, SSE4.2, no AVX), 2 GB | Linux binary, or BareMetal (kbm proper) from a UEFI USB stick | [atomic-pi.md](atomic-pi.md) |
| Seeed XIAO RP2350 / Pico 2 | 2x Cortex-M33 + FPU, 2x Hazard3 RV32IMAC; 520 KB | bare metal in the Pico SDK | [rp2350.md](rp2350.md) |

## What is already proven (in emulation)

All of these pass the same golden transcripts (`test/golden/basic.k`) that
the original AVX-512 k produces:

| Build | Where tested | Script |
|---|---|---|
| rv64gc Linux (Nano C906) | qemu-riscv64 | `boards/linux/build.sh --test` |
| aarch64 Cortex-A53 Linux (Nano A53) | qemu-aarch64 | same |
| armv7 Cortex-A7 Linux (Luckfox) | qemu-arm, and over `ssh -tt` | same, plus `test-on-board.sh` |
| bare-metal RV32IMAFC (P4 ISA) | qemu-system-riscv32 virt | `boards/mcu/build.sh --test` |
| bare-metal RV32IMAC soft-float (RP2350 RISC-V) | qemu-system-riscv32 virt | same |
| bare-metal Cortex-M33 + FPU (RP2350 Arm) | qemu-system-arm mps2-an505 | same |
| GCC-built glue + clang `libk.a` (ESP-IDF ABI; Pico SDK softfp ABI) | both of the above | same |
| k compiled from source by GCC (RV32IMAFC; Cortex-M33 softfp; x86-64 Linux) | QEMU / native | `boards/mcu/build.sh --test`, `test/host/run-golden.sh` |
| x86-64-v2 Linux (Atomic Pi) | qemu-x86_64 -cpu Westmere | `boards/linux/build.sh --test` |
| BareMetal + k from a UEFI USB stick (Atomic Pi) | OVMF, USB storage only, Westmere | `boards/x86-baremetal/test-uefi.sh` |
| ESP-IDF project, k compiled by IDF's GCC (ESP32-S3) | Espressif QEMU, no PSRAM, 128 KiB heap: basic.k | `boards/esp-idf/test-qemu.sh` |
| ESP-IDF project builds for ESP32-P4, 4 MiB heap in PSRAM | build only (no P4 emulator) | `idf.py set-target esp32p4 build` |
| serial test driver, banner and `--attached` modes | QEMU board on a pty | `test/drive_serial.py` |

Not proven anywhere yet: anything on real silicon, the SDK projects
themselves (ESP-IDF, Pico SDK), floating-point *results* (k prints every
float as `?.?`, so the goldens cannot see them), and performance.

## How the pieces fit

```
ksrc/          k itself (Whitney's C; clang or GCC) + kvec.h (portable SIMD helpers),
               ksys.h (all OS calls -> k_sys()), kheap.h (heap size, wsfull)
boards/linux/  k_sys = Linux syscalls (test/host/ksys-linux.c); static, no libc
boards/mcu/    k_sys = boards/mcu/common/ksys-bare.c over three functions:
                   int  con_getc(void);   void con_putc(int c);   void con_exit(int code);
               dist/libk-<abi>.a = k compiled by clang (k_main instead of main)
test/golden/   the transcripts every build must reproduce
```

**k compiles with clang or GCC.** An SDK project (GCC) can either add
`ksrc/a.c` and `ksrc/z.c` to its build with the GCC flags in
`ksrc/README.md` (verified in QEMU for the P4's RV32IMAFC and the Pico SDK's
Cortex-M33 softfp ABI), or link the prebuilt `boards/mcu/dist/libk-<abi>.a`.
Either way it also compiles `ksys-bare.c` and its own `con_*` functions.

## Tools on the bring-up machine

- clang + lld (any recent; tested with 18), GNU make, Python 3 with
  `pyserial` (`pip install pyserial`)
- For rebuilding: `qemu-user` + `qemu-system-misc`/`-arm`,
  `gcc-riscv64-unknown-elf`, `gcc-arm-none-eabi`, `libgcc-13-dev-armhf-cross`
  (Debian/Ubuntu names). Run the emulated suites before touching hardware:
  `test/host/run-golden.sh`, `boards/linux/build.sh --test`,
  `boards/mcu/build.sh --test`.
- Per board: ESP-IDF v5.4.x, Pico SDK + picotool, adb or ssh, an SD
  writer. See each plan.

## Acceptance (same for every board)

1. `test/golden/basic.k` reproduces `test/golden/basic.expected` exactly on
   the board (and `big.k`/`big.expected` when the heap is >= 256 KiB),
   through one of:
   - `boards/linux/test-on-board.sh user@board /path/to/k` (ssh)
   - `python3 test/drive_serial.py [--reset] test/golden/basic.k /dev/ttyACM0 | diff test/golden/basic.expected -`
2. `test/limits/heap.k` ends in `wsfull` (not a crash or a hang) at the
   board's configured heap.
3. Record in the board's plan file, under "Results": date, board revision,
   image/SDK version, exact build command, heap setting, pass/fail, and
   anything that differed from this plan.

## Working rules for agents

- Work on a branch off `spike/portable-k`, e.g. `hw/<board>`. Commit small
  steps and **push regularly** so the work is visible and backed up.
- Post a short status update at least every ~10 minutes of work.
- **SD cards and flashing are destructive.** Identify the target device
  with `lsblk` (or `diskutil list` on macOS) before and after inserting the
  card, confirm its size matches, and never write to a device you have not
  identified that way. Never write to a disk that holds a mounted system
  partition. Ask the human before reflashing a board's bootloader or
  erasing flash beyond the application region. Exception: on ESP32 boards,
  `idf.py flash` (which rewrites ESP-IDF's second-stage bootloader) is
  routine. Never burn eFuses or enable secure boot or flash encryption
  without approval (see esp32-p4.md, step 0).
- Keep the ksrc/ changes minimal and guarded. The original kbm build must
  stay byte-identical: `test/check-kapp-hash.sh <pinned BareMetal>`.
- If something in a plan is wrong for the real board (a pin, a config
  name, an SDK API), fix the plan in the same commit as the code.
