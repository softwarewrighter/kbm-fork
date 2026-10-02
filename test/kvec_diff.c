// kvec_diff.c -- differential test: ksrc/kvec.h vs the AVX-512 builtins it
// replaces, on random inputs. Needs an AVX-512 (VBMI) host.
//   clang -O2 -march=icelake-client -funsigned-char -ffreestanding -nostdlib \
//     -fno-builtin -I../ksrc kvec_diff.c host/start-min.S -o kvec_diff
// Prints one line per helper and exits 0 when all agree.
#include "_.h"
U w2(i2 n, i0 *s);   // provided by start-min.S (write(1, s, n))
U tn(i2 a, i2 b) { return 0; }
#define o(f) B(ia32_##f##512)
// Reference (AVX-512) versions, copied from a.h with an R prefix.
UV(Rbg,o(cvtb2mask)(a))UV(Rbi,o(cvtd2mask)(a))
VF(Ra4,o(pshufb)(a,b))VF(RA0,o(permvarqi)(a,b))VF(RA2,o(permvarsi)(a,b))
Vg(RS6,2>i?o(vpermi2varqi)(z0,i?62+I0:63+I0,a):$4(i-2,o(alignd)(a,z0,15),o(alignd)(a,z0,14),o(alignd)(a,z0,12),o(alignd)(a,z0,8)))
VE(R_q,o(sqrtps)(x,4))_F(RX9,-a^B(ia32_pclmulqdq128)((j4){x},~(j4){},0)[0])
#include "kvec.h"

static U seed = 0x9E3779B97F4A7C15;
static U rnd(void) { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed; }
static V rv(void) { V v; for (int k = 0; k < 64; k += 8) *(U *)((i0 *)&v + k) = rnd(); return v; }
static int veq(V a, V b) { for (int k = 0; k < 64; k++) if (a[k] != b[k]) return 0; return 1; }
static void say(const char *s) { i2 n = 0; while (s[n]) n++; w2(n, (i0 *)s); }
static int check(const char *name, int bad) { say(name); say(bad ? " MISMATCH\n" : " ok\n"); return bad; }

int main(void) {
  int fail = 0, N = 20000, b;
  b = 0; for (int t = 0; t < N; t++) { V a = rv(); b |= bg(a) != Rbg(a); } fail |= check("bg  vpmovb2m ", b);
  b = 0; for (int t = 0; t < N; t++) { V a = rv(); b |= bi(a) != Rbi(a); } fail |= check("bi  vpmovd2m ", b);
  b = 0; for (int t = 0; t < N; t++) { V a = rv(), c = rv(); b |= !veq(a4(a, c), Ra4(a, c)); } fail |= check("a4  vpshufb  ", b);
  b = 0; for (int t = 0; t < N; t++) { V a = rv(), c = rv(); b |= !veq(A0(a, c), RA0(a, c)); } fail |= check("A0  vpermb   ", b);
  b = 0; for (int t = 0; t < N; t++) { V a = rv(), c = rv(); b |= !veq(A2(a, c), RA2(a, c)); } fail |= check("A2  vpermd   ", b);
  b = 0; for (int t = 0; t < N; t++) { V a = rv(); for (int i = 0; i < 6; i++) b |= !veq(S6(i, a), RS6(i, a)); } fail |= check("S6  shift-up ", b);
  b = 0; for (int t = 0; t < N; t++) { i6 u = (i6)rv() & 0x3fffffff; e6 x = __builtin_convertvector(u, e6); e6 p = _q(x), q = R_q(x); b |= !veq((V)p, (V)q); } fail |= check("_q  vsqrtps  ", b);
  b = 0; for (int t = 0; t < N; t++) { U a = rnd(), x = rnd(); b |= X9(a, x) != RX9(a, x); } fail |= check("X9  pclmul   ", b);
  say(fail ? "FAIL\n" : "ALL AGREE\n");
  return fail;
}
