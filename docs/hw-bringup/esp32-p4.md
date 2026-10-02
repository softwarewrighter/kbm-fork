# Bring-up plan: ESP32-P4 (ESP-IDF)

Goal: k's REPL on the P4's console, passing the goldens via
`test/drive_serial.py`. The P4 is RV32IMAFC with a single-precision FPU and
768 KB of on-chip SRAM; many dev boards add PSRAM.

## What is ready

- `boards/mcu/dist/libk-rv32imafc-ilp32f.a`: k compiled by clang for the
  P4's ISA and float ABI (ilp32f), `main` renamed `k_main`. Built by
  `boards/mcu/build.sh`.
- `boards/mcu/common/ksys-bare.c`: k's OS layer (line input with echo and
  backspace, output, exit) over three functions you provide.
- Verified in QEMU: the same library linked by **GCC** with GCC-compiled
  glue (`rv32imafc-virt-gcc` target) passes the goldens. That is the same
  link ESP-IDF will do.

## Plan

### 1. Toolchain and a blank project

1. Install an ESP-IDF release that supports the P4: `idf.py --list-targets`
   must include `esp32p4`. Note the version.
2. `idf.py create-project k_p4` (or start from `examples/get-started/hello_world`),
   `idf.py set-target esp32p4`, build, flash, `idf.py monitor`: confirm the
   board's console works and which port it is on (`/dev/ttyACM0` for
   USB-Serial-JTAG, `/dev/ttyUSB0` for a USB-UART bridge).
3. Check the float ABI ESP-IDF uses:
   `riscv32-esp-elf-gcc -Q --help=target -march=... | grep mabi` after a
   build (or read the compile flags in `build/compile_commands.json`).
   Expect `ilp32f`. If it differs, rebuild libk with matching flags.

### 2. Add k

Layout (a component holding the prebuilt library and the glue):

```
k_p4/
  main/main.c                    app_main -> start k
  components/k/
    CMakeLists.txt
    libk-rv32imafc-ilp32f.a      copy from boards/mcu/dist/
    ksys-bare.c                  copy from boards/mcu/common/ (NOT libc-min.c)
    con_esp.c                    the three console functions
```

`components/k/CMakeLists.txt` (starting point; adjust to your IDF version):

```cmake
idf_component_register(SRCS "ksys-bare.c" "con_esp.c"
                       INCLUDE_DIRS "."
                       REQUIRES driver esp_driver_uart)   # or esp_driver_usb_serial_jtag
add_prebuilt_library(kcore "${CMAKE_CURRENT_SOURCE_DIR}/libk-rv32imafc-ilp32f.a")
target_link_libraries(${COMPONENT_LIB} PRIVATE kcore)
```

`con_esp.c`: use the console driver's blocking read/write directly rather
than stdio, so there is no line buffering or CRLF translation in the way
(ksys-bare.c already echoes and sends `\r\n`). For USB-Serial-JTAG:

```c
#include "driver/usb_serial_jtag.h"
#include "esp_system.h"
int  con_getc(void) { uint8_t c; while (usb_serial_jtag_read_bytes(&c, 1, portMAX_DELAY) != 1) {} return c; }
void con_putc(int c) { uint8_t b = c; usb_serial_jtag_write_bytes(&b, 1, portMAX_DELAY); }
void con_exit(int code) { (void)code; esp_restart(); }
// call usb_serial_jtag_driver_install() once before starting k
```

For a UART console, the equivalents are `uart_driver_install`,
`uart_read_bytes(UART_NUM_0, &c, 1, portMAX_DELAY)` and `uart_write_bytes`.
API names move between IDF versions; check the installed headers.

`main/main.c`:

```c
void kmain(void);                       // from ksys-bare.c: calls k_main
static void k_task(void *arg) { kmain(); }
void app_main(void) {
    /* install the console driver here */
    xTaskCreate(k_task, "k", 32 * 1024, NULL, 5, NULL);   // k needs a real stack
}
```

The default main-task stack is far too small for k; run it in its own task
with 32 KB (or raise `CONFIG_ESP_MAIN_TASK_STACK_SIZE`). FreeRTOS on the P4
handles FPU context for tasks; no manual FPU enable is needed.

### 3. Memory

k's library defaults to KHEAP=13 (512 KiB heap, about 553 KB with tables
and stack). With ESP-IDF's own use of SRAM that may not fit:

- First bring-up: rebuild a smaller library,
  `KFLAGS_rv32imafc_ilp32f="-DKHEAP=12 -DKOBJ=10" boards/mcu/build.sh`
  (256 KiB heap), and copy the new `.a`.
- Then PSRAM, if the board has it: enable PSRAM in menuconfig plus the
  option that allows `.bss` in external RAM (`CONFIG_SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY`
  in current IDF), and build libk with
  `-DKHEAP=18 -DKHEAP_ATTR='__attribute__((section(".ext_ram.bss")))'`
  (16 MiB). Confirm the section name against IDF's `EXT_RAM_BSS_ATTR` in
  `esp_attr.h` for your version.
- `idf.py size` shows whether it fits; a link error about DRAM overflow
  means the heap is too big for internal RAM.

### 4. Test

1. `idf.py flash`, then close any monitor so the port is free.
2. Start the driver, then reset the board (EN button):
   `python3 test/drive_serial.py test/golden/basic.k /dev/ttyACM0 | diff test/golden/basic.expected -`
   (opening the port may itself reset the board; that is fine, the driver
   waits for k's banner). If k is already running, add `--attached`.
3. Heap limit: a KHEAP=12 build with `test/limits/heap.k` should print
   `wsfull` (then `con_exit` restarts the board; that is expected).

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
