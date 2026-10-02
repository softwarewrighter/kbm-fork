// ksys.h -- k's OS boundary as one C-ABI function, for -DKSYS builds.
//
// The original z.h binds k's eight OS entry points (exit, read, write, close,
// open, fstat, mmap, munmap) with per-OS inline assembly. With KSYS defined
// they all become calls to a single function the host provides:
//
//     U k_sys(U nr, U a, U b, U c, U d, U e, U f);
//
// `nr` uses x86-64 Linux numbering, the numbering kbm's s.asm already speaks:
//   60 exit   0 read   1 write   3 close   2 open   5 fstat   9 mmap  11 munmap
// fstat must fill the x86-64 Linux `struct stat` layout (z.c reads st_mode as
// the low half of word 3 and st_size as word 6). A host that does not support
// a call returns (U)-38 (-ENOSYS); k then treats files as unavailable.
//
// Only integers and pointers cross this boundary, so a k object compiled with
// FP/SIMD enabled can be linked into a softfloat kernel (sw-os-ml): the two
// AArch64 ABIs differ only in how FP arguments are passed.
#ifndef KSYS_H
#define KSYS_H

extern U k_sys(U, U, U, U, U, U, U);
// Variadic like the originals (callers pass 1..6 arguments). Reading past
// the supplied arguments yields unspecified values the host ignores.
#define O(f,i) ZU f(U ks0,...){__builtin_va_list v;__builtin_va_start(v,ks0);\
 U ks1=__builtin_va_arg(v,U);U ks2=__builtin_va_arg(v,U);U ks3=__builtin_va_arg(v,U);\
 U ks4=__builtin_va_arg(v,U);U ks5=__builtin_va_arg(v,U);__builtin_va_end(v);\
 return k_sys(i,ks0,ks1,ks2,ks3,ks4,ks5);}

// Cycle counter for k's \t timing.
#if __x86_64
AS(ut,"rdtsc;shl $32,%rdx;or %rdx,%rax;")
#elif __aarch64__
AS(ut,"mrs x0,cntvct_el0\nmov x1,100\nmul x0,x0,x1\n")
#else
#error "ksys.h: no cycle counter for this architecture"
#endif

#if __AVX512F__
UV(bg,B(ia32_cvtb2mask512)(a))
#else
#define KVEC_BG_ONLY
#include"kvec.h"
#undef KVEC_BG_ONLY
#endif

#endif
