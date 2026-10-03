# Bring-up plan: ESP32-S3 (N16R8) with ESP-IDF

The ESP32-S3 has two **Xtensa LX7** cores (neither ARM nor RISC-V) with a
single-precision FPU, 512 KB SRAM; the N16R8 module adds 16 MB flash and
8 MB **octal** PSRAM. Goal: k's REPL on the board's console, passing the
goldens via `test/drive_serial.py`.

## What is already verified (not on hardware)

- `boards/esp-idf` builds for `esp32s3` with ESP-IDF **v5.4.2**: k compiled
  from source by `xtensa-esp32s3-elf-gcc` 14.2. Image 471 KB; internal RAM
  21% used; k's 4 MiB heap linked into PSRAM (`.ext_ram.bss` at
  0x3C070000, zeroed by IDF at boot).
- In Espressif's QEMU (ESP32-S3 machine), a variant without PSRAM (128 KiB
  heap) boots and passes `test/golden/basic.k`:
  `boards/esp-idf/test-qemu.sh`. QEMU could not emulate PSRAM, so the PSRAM
  heap has only been checked at link time.

Not verified: real octal PSRAM, the USB-Serial-JTAG console path, `big.k`
on the board, timing.

## Prerequisites (bring-up machine)

- ESP-IDF v5.4.x installed the normal way (`./install.sh esp32s3`), then
  `. $IDF_PATH/export.sh` in each shell. Record the version (`idf.py --version`).
- Python 3 with `pyserial` for `test/drive_serial.py` (ESP-IDF's Python
  environment already has it).
- The board on USB. Find its port: Linux `ls /dev/ttyUSB* /dev/ttyACM*`
  (add the user to `dialout`/`uucp` if access is denied); macOS
  `ls /dev/cu.*`.

Many N16R8 dev boards (ESP32-S3-DevKitC-1 style) have two USB connectors:
- **UART** (or COM): a USB-UART bridge to UART0, usually `/dev/ttyUSB0`
  (macOS `/dev/cu.usbserial-*` or `/dev/cu.wchusbserial*`). **The default
  console. Use this one.**
- **USB**: the chip's native USB-Serial-JTAG, usually `/dev/ttyACM0`. Only
  the console if you switch it in menuconfig (step 6).

## Steps

1. **Build**
   ```sh
   cd boards/esp-idf
   idf.py set-target esp32s3
   idf.py build
   ```
   Expect "k: heap 2^16 x 64 bytes" in the configure output. If
   `set-target` was run before with another target, delete `sdkconfig` first.

2. **Flash**
   ```sh
   idf.py -p /dev/ttyUSB0 flash
   ```
   If esptool cannot connect: hold BOOT, tap RESET (EN), release BOOT, retry.

3. **Smoke test**
   ```sh
   idf.py -p /dev/ttyUSB0 monitor      # Ctrl-] to quit
   ```
   After the boot log, k prints `... (c)arthur whitney(l)MIT`. Type `1+2`
   (expect `3`), `3^!10` (expect rows `0 1 2`, `3 4 5`, `6 7 8`), `\\`
   (board reboots into k).
   Look for `E (...) octal_psram` errors in the boot log (see Troubleshooting).

4. **Acceptance** (close the monitor first; the port must be free)
   ```sh
   cd ../..
   python3 test/drive_serial.py --reset test/golden/basic.k /dev/ttyUSB0 | diff test/golden/basic.expected -
   python3 test/drive_serial.py --reset test/golden/big.k   /dev/ttyUSB0 | diff test/golden/big.expected -
   ```
   No diff output means pass. `--reset` pulses RTS (wired to EN on these
   boards) so the driver sees k's banner. If the board does not reset that
   way, start the command and press RESET within 60 s, or use `--attached`
   when k is already at its prompt.

5. **Heap limit**: rebuild with a tiny heap and check `wsfull`:
   ```sh
   cd boards/esp-idf && idf.py -DK_HEAP=11 build flash && cd ../..
   python3 test/drive_serial.py --reset test/limits/heap.k /dev/ttyUSB0 | tail -2
   ```
   Expect `wsfull`; the board then reboots (k's exit calls `esp_restart`).
   Rebuild with the default afterwards: `idf.py -DK_HEAP=16 build flash`
   (CMake caches the value).

6. **Optional: console on the native USB port.** `idf.py menuconfig` >
   Component config > ESP System Settings > Channel for console output >
   USB Serial/JTAG Controller; rebuild, flash, repeat steps 3-4 on
   `/dev/ttyACM0`.

7. Record results below; commit to your `hw/esp32s3` branch and push.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `octal_psram: PSRAM ID read error`, then abort | Board's PSRAM is quad, not octal (some "R8" clones) or absent: `idf.py menuconfig` > SPI RAM config > Mode: Quad; or disable SPI RAM (heap drops to 256 KiB internal). |
| Link error: DRAM / `.dram0.bss` overflow | PSRAM was disabled but `K_HEAP` is too big: `idf.py -DK_HEAP=12 build`. |
| Boots, no banner on `/dev/ttyUSB0` | Console is on the other port (step 6), or wrong port. |
| Characters lost when pasting | Paste one line at a time; the drivers wait for each echo. |
| Task watchdog messages during long computations | k should run on core 1 (`main.c`); check `CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1=n` in `sdkconfig`. |
| Flash size warning at boot | Module is not 16 MB: set `idf.py menuconfig` > Serial flasher config > Flash size. |

## Results

(date, board name/revision, module (N16R8?), ESP-IDF version, console port,
heap setting, smoke test, basic.k / big.k / heap.k results, notes)
