// ksys-linux.c -- k_sys() for running a -DKSYS build of k as a Linux process,
// on x86-64 or aarch64, without libc. Test scaffolding for the port: it is
// the Linux analog of the k_sys an OS such as sw-os-ml provides in Rust.
//
// Contract (see ksrc/ksys.h): x86-64 Linux syscall numbers in, x86-64
// `struct stat` layout out. On aarch64 the numbers are translated and
// open() becomes openat(AT_FDCWD, ...).
typedef unsigned long U;

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

#elif __aarch64__
static U sc6(U n, U a, U b, U c, U d, U e, U f) {
  register U x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b, x2 __asm__("x2") = c,
                 x3 __asm__("x3") = d, x4 __asm__("x4") = e, x5 __asm__("x5") = f;
  __asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory");
  return x0;
}
enum { A_OPENAT = 56, A_CLOSE = 57, A_READ = 63, A_WRITE = 64, A_FSTAT = 80, A_EXIT = 93,
       A_MUNMAP = 215, A_MMAP = 222 };
U k_sys(U nr, U a, U b, U c, U d, U e, U f) {
  switch (nr) {
  case 0:  return sc6(A_READ, a, b, c, 0, 0, 0);
  case 1:  return sc6(A_WRITE, a, b, c, 0, 0, 0);
  case 2:  return sc6(A_OPENAT, (U)-100, a, b, c, 0, 0);
  case 3:  return sc6(A_CLOSE, a, 0, 0, 0, 0, 0);
  case 5: { // fstat: repack generic (aarch64) stat into the x86-64 layout
    U st[16] = {0};
    U r = sc6(A_FSTAT, a, (U)st, 0, 0, 0, 0);
    if ((long)r < 0) return r;
    U *o = (U *)b;
    for (int i = 0; i < 18; i++) o[i] = 0;
    o[3] = st[2] & 0xffffffff;  // st_mode: aarch64 offset 16 -> x86-64 offset 24
    o[6] = st[6];               // st_size: offset 48 on both
    return 0;
  }
  case 9:  return sc6(A_MMAP, a, b, c, d, e, f);
  case 11: return sc6(A_MUNMAP, a, b, 0, 0, 0, 0);
  case 60: return sc6(A_EXIT, a, 0, 0, 0, 0, 0);
  default: return (U)-38; // -ENOSYS
  }
}
__asm__(".globl _start\n_start:\n mov x29,#0\n ldr x0,[sp]\n add x1,sp,#8\n bl main\n"
        " mov x8,#93\n svc 0\n");
#else
#error "ksys-linux.c: unsupported architecture"
#endif
