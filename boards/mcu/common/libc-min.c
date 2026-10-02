// libc-min.c -- the few libc symbols k needs when there is no libc at all
// (the QEMU stand-ins). Do NOT link this into ESP-IDF or Pico SDK builds:
// their newlib provides these.
#include <stddef.h>
void con_exit(int code);

// Freestanding code may still emit calls to these.
void *memset(void *d, int c, size_t n) {
  unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, size_t n) {
  unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }
void *memmove(void *d, const void *s, size_t n) {
  unsigned char *p = d; const unsigned char *q = s;
  if (p < q) while (n--) *p++ = *q++; else { p += n; q += n; while (n--) *--p = *--q; }
  return d; }
int raise(int sig) { con_exit(128 + sig); return 0; }   // libgcc divide-by-zero
void abort(void) { con_exit(134); for (;;) {} }

// Soft-float targets (no FPU, e.g. RV32IMAC) lower k's vector sqrt to a libm
// sqrtf call, and there is no libm. Weak, so a real libm or hardware path wins.
// Bit-trick estimate plus Newton steps: within an ulp or so of correct.
__attribute__((weak)) float sqrtf(float x) {
  if (x != x || x < 0) return (x - x) / (x - x);       // NaN
  if (x == 0 || x == __builtin_inff()) return x;       // +-0, +inf
  union { float f; unsigned u; } v = {x};
  v.u = (v.u >> 1) + 0x1fc00000u;
  float y = v.f;
  for (int i = 0; i < 6; i++) y = 0.5f * (y + x / y);
  return y;
}
