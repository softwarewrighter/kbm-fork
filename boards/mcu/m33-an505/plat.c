// boards/mcu/m33-an505/plat.c -- console via Arm semihosting (bkpt 0xab).
// QEMU forwards these calls to its terminal, so no UART address is assumed.
// On an RP2350 these three functions become Pico SDK stdio calls
// (getchar/putchar over UART or USB CDC); see docs/hw-bringup/rp2350.md.
#include <stdint.h>
static int semi(int op, const void *arg) {
  register int r0 __asm__("r0") = op;
  register const void *r1 __asm__("r1") = arg;
  __asm__ volatile("bkpt 0xab" : "+r"(r0) : "r"(r1) : "memory");
  return r0;
}
enum { SYS_WRITEC = 0x03, SYS_READC = 0x07, SYS_EXIT = 0x18 };

int con_getc(void) { return semi(SYS_READC, 0); }
void con_putc(int c) { char ch = (char)c; semi(SYS_WRITEC, &ch); }
void con_exit(int code) {
  (void)code;
  semi(SYS_EXIT, (const void *)0x20026);   // ADP_Stopped_ApplicationExit
  for (;;) {}
}
