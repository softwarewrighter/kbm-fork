# k on ESP32 with ESP-IDF (ESP32-S3, ESP32-P4)

One ESP-IDF project. k's sources (`ksrc/`, shared with every other target)
are compiled by ESP-IDF's own GCC; nothing prebuilt.

Tested here with **ESP-IDF v5.4.2**: builds for `esp32s3` and `esp32p4`, and
the S3 build passes `test/golden/basic.k` in Espressif's QEMU
(`./test-qemu.sh`). Not yet run on real hardware.

## Build, flash, talk to k

```sh
. $IDF_PATH/export.sh                 # ESP-IDF v5.4.x
cd boards/esp-idf
idf.py set-target esp32s3             # or esp32p4
idf.py build
idf.py -p /dev/ttyUSB0 flash monitor  # Ctrl-] leaves the monitor
```

At k's prompt: `1+2` prints `3`. `\\` reboots the board back into k.

## Defaults

| | ESP32-S3 (N16R8) | ESP32-P4 |
|---|---|---|
| sdkconfig | `sdkconfig.defaults` + `sdkconfig.defaults.esp32s3` | `sdkconfig.defaults` |
| Flash | 16 MB | IDF default |
| k's heap | 4 MiB in octal PSRAM (`K_HEAP=16`) | 256 KiB in internal SRAM (`K_HEAP=12`) |
| Console | UART0 (the board's USB-UART port) | UART0 |

- Heap: `idf.py -DK_HEAP=n build` (heap = 64 << n bytes). Without PSRAM the
  default is 256 KiB; with `CONFIG_SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY` it
  is 4 MiB in PSRAM.
- Console on the chip's native USB port instead: `idf.py menuconfig` >
  Component config > ESP System Settings > Channel for console output >
  USB Serial/JTAG Controller. `components/k/con_esp.c` follows that setting.
- k runs in its own task (32 KB stack), pinned to core 1.

## Files

| File | What |
|---|---|
| `components/k/CMakeLists.txt` | compiles `ksrc/a.c`, `ksrc/z.c` with the GCC flags k needs; heap size and placement |
| `components/k/con_esp.c` | console: blocking UART or USB-Serial-JTAG driver calls |
| `main/main.c` | starts k in its task |
| `test-qemu.sh` | builds a no-PSRAM variant (`build-qemu/`) and runs the goldens in Espressif's QEMU |

Full bring-up plan, acceptance and troubleshooting:
`docs/hw-bringup/esp32-s3.md` (and `esp32-p4.md`).
