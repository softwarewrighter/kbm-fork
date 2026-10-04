# Bring-up plan: ESP32-P4 (ESP-IDF)

Goal: k's REPL on the P4's console, passing the goldens via
`test/drive_serial.py`.

The ESP32-P4 is **RISC-V only**: two RV32IMAFC high-performance cores with a
single-precision FPU, a low-power RISC-V core, and 768 KB of on-chip SRAM.
There is no Arm core and no radio. Boards that offer Wi-Fi add a separate
ESP32-C6 over SDIO; k does not use it.

## Target board: Waveshare ESP32-P4-Module-DEV-KIT

- Module: ESP32-P4NRW32, with **32 MB in-package hex PSRAM** (the largest
  P4 option) and 16 MB NOR flash. It also carries an ESP32-C6.
- Chip revision **v1.x** (the board in hand is believed to be v1.3). Read the
  real value from esptool's `Chip is ESP32-P4 (revision v1.3)` line when
  flashing, and record it under Results.
- Ports: a Type-C **UART** port (USB-UART bridge to UART0; this is the
  console and the flashing port), the P4's native USB (OTG/Serial-JTAG), and
  USB-A host ports. There are BOOT and RST buttons.

### Chip revision vs ESP-IDF and clock

| Chip revision | ESP-IDF | Max CPU clock |
|---|---|---|
| v0.x / v1.x (this board) | v5.4.x works (supports up to v1.99) | **360 MHz** |
| v3.x (newer boards) | needs a newer ESP-IDF (v5.5+); v5.4.x refuses it | 400 MHz |

With ESP-IDF v5.4.2 and `esp32p4`, the build already chooses
`CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_360=y` and `CONFIG_ESP32P4_REV_MIN_1=y`
(it supports revisions v0.1 to v1.99). Do not try to set 400 MHz on a v1.x chip.

## What is ready (verified here, build only)

`boards/esp-idf` (shared with the ESP32-S3; see `boards/esp-idf/README.md`)
compiles k from source with ESP-IDF's GCC. Built with **ESP-IDF v5.4.2** for
`esp32p4` with `sdkconfig.defaults.esp32p4`:

- PSRAM is on: hex mode at 20 MHz, BSS in external memory. k's 4 MiB heap is
  placed as `.ext_ram.bss` at 0x48000000; internal DIRAM is 15% used.
- `-DK_HEAP=18` (16 MiB heap) also links and fits in the 32 MB.

Espressif's QEMU has no ESP32-P4 machine, so the first run will be on the
board. The S3 build of the same project passes the goldens in QEMU.

PSRAM clock: 20 MHz is the only non-experimental choice in v5.4.x. It is slow
but safe. To try 200 MHz, set `CONFIG_IDF_EXPERIMENTAL_FEATURES=y` and
`CONFIG_SPIRAM_SPEED_200M=y` in menuconfig, then rerun the acceptance tests.
Record the result.

(The prebuilt `boards/mcu/dist/libk-rv32imafc-ilp32f.a` is an alternative,
but compiling from source is simpler and is what was tested.)

## Plan

### 0. Prerequisites and safety (read first)

- **ESP-IDF v5.4.x** (v5.4.2 tested), installed the normal way:
  `git clone -b v5.4.2 --recursive https://github.com/espressif/esp-idf`,
  then `./install.sh esp32p4`, then `. ./export.sh` in every shell. Record
  `idf.py --version`. A v3.x chip needs v5.5+ instead (see the table above).
- Python `pyserial` for `test/drive_serial.py`. ESP-IDF's Python environment
  already has it.
- **Find the port.** Connect only the Type-C port labelled **UART**. List
  `ls /dev/ttyUSB* /dev/ttyACM*` (macOS: `ls /dev/cu.*`) before and after
  plugging it in; the new entry is the board. Use that path wherever these
  steps say `/dev/ttyUSB0`.
  - On Linux, if access is denied, add the user to `dialout` (or `uucp` on
    Arch) and log in again.
  - Confirm with `python -m esptool --port <port> chip_id`. It must report
    `ESP32-P4` and print its revision. If it reports any other chip, you
    have the wrong port or board.
- **What is allowed without asking the human.** Exception to the rule in
  `README.md`: on ESP32 chips the boot ROM is in mask ROM and cannot be
  overwritten. `idf.py flash` (bootloader at 0x2000, partition table,
  app) and `idf.py app-flash` are routine and recoverable through
  BOOT+RST, so run them freely on this board.
- **Never, without explicit approval from the human:**
  - `espefuse.py` in any form (eFuses are one-time and permanent);
  - enabling Secure Boot or Flash Encryption in menuconfig;
  - `idf.py erase-flash` / `esptool erase_flash` (recoverable, but it
    erases anything else stored on the board).
- Work on branch `hw/esp32p4` off `spike/portable-k`. Commit and push after
  each step that produces a result.

### 1. Build and flash

```sh
. $IDF_PATH/export.sh                  # ESP-IDF v5.4.x (chip v1.x); v5.5+ for v3.x
cd boards/esp-idf
rm -f sdkconfig                        # if set-target was run for another chip
idf.py set-target esp32p4
idf.py build                           # expect "k: heap 2^16 x 64 bytes"
idf.py -p /dev/ttyUSB0 flash monitor   # UART Type-C port; Ctrl-] to quit
```

If esptool cannot connect, hold BOOT, tap RST, release BOOT, and retry.
After flashing in that mode, tap RST to start the app.

**Stop and report to the human** (do not work around these):
- esptool reports a chip revision outside v0.1–v1.99 for this ESP-IDF.
- PSRAM is not found or its memtest fails. As a diagnostic only, you may try
  the no-PSRAM build (step 2, last row) and report both results.
- A boot loop that a rebuild of an unchanged tree does not fix.

Check the boot log for:
- The chip revision line.
- PSRAM detection: something like `esp_psram: Found 32MB PSRAM device`, with
  the memtest passing.
- Errors from `esp_psram` or `mmu`.

Smoke test at k's prompt: `1+2` -> `3`, `3^!10`, `\\` (reboots into k).

### 2. Memory

| Setting | Heap |
|---|---|
| default (`sdkconfig.defaults.esp32p4`) | 4 MiB in PSRAM (`K_HEAP=16`) |
| `idf.py -DK_HEAP=18 build` | 16 MiB in PSRAM |
| PSRAM disabled in menuconfig + `-DK_HEAP=12` | 256 KiB internal SRAM |

`idf.py size` shows where it goes. CMake caches `K_HEAP`, so pass it again
to change back.

### 3. Notes

- k runs in its own task with a 32 KB stack, pinned to core 1
  (`main/main.c`). FreeRTOS handles the FPU context.

### 4. Test

1. `idf.py flash`, then close any monitor so the port is free.
2. From the repo root:
   `python3 test/drive_serial.py --reset test/golden/basic.k /dev/ttyUSB0 | diff test/golden/basic.expected -`
   and the same with `test/golden/big.k` / `big.expected`.
   - `--reset` pulses RTS to reset the board.
   - If the board does not reset that way, press RST after starting the
     command.
   - Use `--attached` if k is already at its prompt.
3. Heap limit: an `idf.py -DK_HEAP=11 build flash` with `test/limits/heap.k`
   should print `wsfull`. `con_exit` then restarts the board, which is
   expected. Rebuild with `-DK_HEAP=16` afterwards.

## Known gaps / risks

- **Timing with `\t`:** it uses `rdcycle`. If the P4 traps on it in its
  privilege mode, replace `ut` in `ksrc/ksys.h` for this target with a call
  through `k_sys` to `esp_cpu_get_cycle_count()`, and say so in this file.
- **Floats:** results are not covered by the goldens (k prints `?.?`).
- **Chip revision:** a v3.x chip with ESP-IDF v5.4.x fails at boot or flash
  with a revision error. Use ESP-IDF v5.5+ for that chip.

## Results

(date, board, chip revision, IDF version, console port, PSRAM detected,
heap setting, basic.k / big.k / heap.k pass/fail, notes)
