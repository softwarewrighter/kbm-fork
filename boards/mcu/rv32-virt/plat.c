// boards/mcu/rv32-virt/plat.c -- console for QEMU riscv32 `virt`.
// NS16550A UART at 0x10000000 (polled) and the SiFive test device at
// 0x100000 for power-off. On an ESP32-P4 these three functions become
// ESP-IDF console calls (see docs/hw-bringup/esp32-p4.md).
#include <stdint.h>
#define UART ((volatile uint8_t *)0x10000000)
#define LSR_DR 0x01    // receive data ready
#define LSR_THRE 0x20  // transmit holding register empty
#define TEST ((volatile uint32_t *)0x100000)

int con_getc(void) {
  while (!(UART[5] & LSR_DR)) {}
  return UART[0];
}
void con_putc(int c) {
  while (!(UART[5] & LSR_THRE)) {}
  UART[0] = (uint8_t)c;
}
void con_exit(int code) {
  *TEST = code ? ((uint32_t)code << 16) | 0x3333 : 0x5555;  // FAIL / PASS
  for (;;) {}
}
