# Bring-up plan: ESP32-P4 (ESP-IDF)

Goal: k's REPL on the P4's console, passing the goldens via
`test/drive_serial.py`. The P4 is RV32IMAFC with a single-precision FPU and
768 KB of on-chip SRAM; many dev boards add PSRAM.

## What is ready

**Use the ESP-IDF project in `boards/esp-idf`** (shared with the ESP32-S3,
see `boards/esp-idf/README.md`). It compiles k from source with ESP-IDF's
GCC; verified to build for `esp32p4` with ESP-IDF v5.4.2 (256 KiB heap in
internal SRAM, 60% of DIRAM used). There is no ESP32-P4 machine in
Espressif's QEMU, so its first run will be on the board. The S3 build of the
same project passes the goldens in QEMU.

(The prebuilt `boards/mcu/dist/libk-rv32imafc-ilp32f.a` remains an
alternative, but compiling from source is simpler and is what was tested.)

## Plan

### 1. Build and flash

```sh
. $IDF_PATH/export.sh                  # ESP-IDF v5.4.x with esp32p4 support
cd boards/esp-idf
rm -f sdkconfig                        # if set-target was run for another chip
idf.py set-target esp32p4
idf.py build
idf.py -p <port> flash monitor         # Ctrl-] to quit
```

Smoke test at k's prompt: `1+2` -> `3`. Find the console port: the P4 dev
board's USB-UART port is the default (UART0); for the native USB port see
the console note in `boards/esp-idf/README.md`.

### 2. Memory

The P4 build keeps k's heap in internal SRAM (256 KiB). For more, enable
PSRAM in menuconfig (Component config > ESP PSRAM) together with
"Allow .bss segment placed in external memory"
(`CONFIG_SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY`); `components/k` then puts a
4 MiB heap in PSRAM automatically. Override with `idf.py -DK_HEAP=n build`.
`idf.py size` shows whether it fits.

### 3. Notes

- k runs in its own task with a 32 KB stack, pinned to core 1
  (`main/main.c`); FreeRTOS handles the FPU context.

### 4. Test

1. `idf.py flash`, then close any monitor so the port is free.
2. From the repo root:
   `python3 test/drive_serial.py --reset test/golden/basic.k <port> | diff test/golden/basic.expected -`
   and the same with `test/golden/big.k` / `big.expected`. `--reset` pulses
   RTS to reset the board; otherwise press RESET after starting it, or use
   `--attached` if k is already at its prompt.
3. Heap limit: an `idf.py -DK_HEAP=11 build` with `test/limits/heap.k`
   should print `wsfull` (then `con_exit` restarts the board; expected).

## Known gaps / risks

- ABI: if ESP-IDF builds with a different `-mabi` the link fails loudly;
  rebuild libk to match (see step 1.3).
- `\t` timing uses `rdcycle`; if the P4 traps on it in its privilege mode,
  replace `ut` in `ksrc/ksys.h` for this target with a call through
  `k_sys` to `esp_cpu_get_cycle_count()` (and say so in this file).
- Float results are not covered by the goldens (k prints `?.?`).

## Results

(date, board, IDF version, console type, heap/PSRAM settings, acceptance
pass/fail, notes)
