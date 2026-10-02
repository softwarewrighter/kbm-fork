// ksys-bare.c -- k_sys for running k with no OS (microcontrollers).
//
// Implements the k_sys contract (ksrc/ksys.h) on top of three functions a
// platform provides, so moving k to a new board means writing only those:
//
//   int  con_getc(void);      blocking: next byte from the console
//   void con_putc(int c);     write one byte to the console
//   void con_exit(int code);  stop (power off, reset, or spin)
//
// On ESP-IDF or the Pico SDK these map to getchar/putchar (UART or USB
// serial); in the QEMU stand-ins they are a 16550 UART or semihosting.
// Line input does what a terminal driver would: echo, CR -> LF, backspace.
// Files (\l) are not supported: open etc. return -ENOSYS, as on BareMetal.
//
// Plain C with no libc dependency: compiles with clang or with an SDK's GCC.
// Without an SDK, also link libc-min.c (memset etc.); with one, don't.
#include <stddef.h>
typedef unsigned long long U;   // must match ksrc/_.h

int con_getc(void);
void con_putc(int c);
void con_exit(int code);
int k_main(int, char **);   // k's main, renamed at build time (-Dmain=k_main)

static U read_line(char *s, U n) {
  U i = 0;
  while (i < n) {
    int c = con_getc();
    if (c == '\r') c = '\n';
    if (c == 0x7f || c == 8) {                // backspace / delete
      if (i) { i--; con_putc(8); con_putc(' '); con_putc(8); }
      continue;
    }
    con_putc(c == '\n' ? '\r' : c);
    if (c == '\n') con_putc('\n');
    s[i++] = (char)c;
    if (c == '\n') break;
  }
  return i;                                   // includes the '\n', like read(2)
}

static U write_bytes(const char *s, U n) {
  for (U i = 0; i < n; i++) {
    if (s[i] == '\n') con_putc('\r');
    con_putc((unsigned char)s[i]);
  }
  return n;
}

U k_sys(U nr, U a, U b, U c, U d, U e, U f) {
  (void)a; (void)d; (void)e; (void)f;
  switch (nr) {
  case 0:  return read_line((char *)(size_t)b, c);
  case 1:  return write_bytes((const char *)(size_t)b, c);
  case 60: con_exit((int)a); return 0;
  default: return (U)-38;                     // -ENOSYS
  }
}

// Called by the platform's startup code after .bss is zeroed and the FPU is on.
void kmain(void) {
  static char *argv[] = {"k", 0};
  k_main(1, argv);
  con_exit(0);
}
