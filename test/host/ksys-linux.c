// ksys-linux.c -- k_sys() for running a -DKSYS build of k as a Linux process,
// on x86-64 or aarch64, without libc. Test scaffolding for the port: it is
// the Linux analog of the k_sys an OS such as sw-os-ml provides in Rust.
//
// Contract (see ksrc/ksys.h): x86-64 Linux syscall numbers in, x86-64
// `struct stat` layout out. On aarch64/riscv64 the numbers are translated
// and open() becomes openat(AT_FDCWD, ...). Supports x86-64, aarch64,
// riscv64 and 32-bit ARM (read/write/exit only).
typedef unsigned long U;

// Freestanding builds may still emit calls to these (e.g. riscv64 for
// zero-initialized locals); there is no libc to provide them.
void *memset(void *d, int c, __SIZE_TYPE__ n) {
  unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, __SIZE_TYPE__ n) {
  unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }

#if __x86_64__
static U sc6(U n, U a, U b, U c, U d, U e, U f) {
  register U r10 __asm__("r10") = d, r8 __asm__("r8") = e, r9 __asm__("r9") = f;
  U r;
  __asm__ volatile("syscall" : "=a"(r) : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9)
                   : "rcx", "r11", "memory");
  return r;
}
U k_sys(U nr, U a, U b, U c, U d, U e, U f) { return sc6(nr, a, b, c, d, e, f); }
__asm__(".globl _start\n_start:\n xor %ebp,%ebp\n mov (%rsp),%rdi\n lea 8(%rsp),%rsi\n"
        " and $-16,%rsp\n call main\n mov %eax,%edi\n mov $60,%eax\n syscall\n");

#elif __aarch64__ || (__riscv && __riscv_xlen == 64)
// aarch64 and riscv64 share Linux's generic syscall table and stat layout.
static U sc6(U n, U a, U b, U c, U d, U e, U f) {
#if __aarch64__
  register U nr __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b, x2 __asm__("x2") = c,
                 x3 __asm__("x3") = d, x4 __asm__("x4") = e, x5 __asm__("x5") = f;
  __asm__ volatile("svc 0" : "+r"(x0) : "r"(nr), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory");
#else
  register U nr __asm__("a7") = n, x0 __asm__("a0") = a, x1 __asm__("a1") = b, x2 __asm__("a2") = c,
                 x3 __asm__("a3") = d, x4 __asm__("a4") = e, x5 __asm__("a5") = f;
  __asm__ volatile("ecall" : "+r"(x0) : "r"(nr), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory");
#endif
  return x0;
}
enum { G_OPENAT = 56, G_CLOSE = 57, G_READ = 63, G_WRITE = 64, G_FSTAT = 80, G_EXIT = 93,
       G_MUNMAP = 215, G_MMAP = 222 };
U k_sys(U nr, U a, U b, U c, U d, U e, U f) {
  switch (nr) {
  case 0:  return sc6(G_READ, a, b, c, 0, 0, 0);
  case 1:  return sc6(G_WRITE, a, b, c, 0, 0, 0);
  case 2:  return sc6(G_OPENAT, (U)-100, a, b, c, 0, 0);
  case 3:  return sc6(G_CLOSE, a, 0, 0, 0, 0, 0);
  case 5: { // fstat: repack the generic stat into the x86-64 layout
    U st[16] = {0};
    U r = sc6(G_FSTAT, a, (U)st, 0, 0, 0, 0);
    if ((long)r < 0) return r;
    U *o = (U *)b;
    for (int i = 0; i < 18; i++) o[i] = 0;
    o[3] = st[2] & 0xffffffff;  // st_mode: generic offset 16 -> x86-64 offset 24
    o[6] = st[6];               // st_size: offset 48 on both
    return 0;
  }
  case 9:  return sc6(G_MMAP, a, b, c, d, e, f);
  case 11: return sc6(G_MUNMAP, a, b, 0, 0, 0, 0);
  case 60: return sc6(G_EXIT, a, 0, 0, 0, 0, 0);
  default: return (U)-38; // -ENOSYS
  }
}
#if __aarch64__
__asm__(".globl _start\n_start:\n mov x29,#0\n ldr x0,[sp]\n add x1,sp,#8\n bl main\n"
        " mov x8,#93\n svc 0\n");
#else
__asm__(".globl _start\n_start:\n li s0,0\n ld a0,0(sp)\n addi a1,sp,8\n call main\n"
        " li a7,93\n ecall\n");
#endif

#elif __arm__
// 32-bit ARM EABI (e.g. Luckfox Pico, Cortex-A7). Only read/write/exit:
// enough for the REPL; files report -ENOSYS.
typedef unsigned long long U64;
static unsigned sc3(unsigned n, unsigned a, unsigned b, unsigned c) {
  register unsigned r7 __asm__("r7") = n, r0 __asm__("r0") = a, r1 __asm__("r1") = b, r2 __asm__("r2") = c;
  __asm__ volatile("svc 0" : "+r"(r0) : "r"(r7), "r"(r1), "r"(r2) : "memory");
  return r0;
}
U64 k_sys(U64 nr, U64 a, U64 b, U64 c, U64 d, U64 e, U64 f) {
  switch (nr) {
  case 0:  return (int)sc3(3, a, b, c);   // read; sign-extend errors
  case 1:  return (int)sc3(4, a, b, c);   // write
  case 60: return sc3(1, a, 0, 0);        // exit
  default: return (U64)-38;
  }
}
// libgcc's 64-bit division calls raise(SIGFPE) on divide-by-zero; no libc here.
int raise(int sig) { sc3(1, 128 + sig, 0, 0); return 0; }
__asm__(".globl _start\n_start:\n mov fp,#0\n ldr r0,[sp]\n add r1,sp,#4\n bl main\n"
        " mov r7,#1\n svc 0\n");
#else
#error "ksys-linux.c: unsupported architecture"
#endif
