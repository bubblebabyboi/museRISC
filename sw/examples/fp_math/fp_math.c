/* fp_math: double-precision floating point (RV64 F/D, IEEE 754).
 *
 * The startup code turns the FPU on (mstatus.FS); the SDK builds with
 * the lp64d ABI, so doubles live in FP registers. Results are compared
 * bit-for-bit where IEEE 754 fixes them. Checks:
 *   1. fsqrt.d(2) and fsqrt.s(2) are the correctly rounded values
 *   2. Newton's iteration x = (x + 2/x) / 2 reaches sqrt(2) within
 *      1 ulp in at most 6 steps from x = 1
 *   3. e = sum 1/k!, k = 0..20, is within 2 ulp of the double nearest e
 *   4. dot product of 100 doubles (exact in binary) == 2525.0
 *   5. fused multiply-add rounds once: fma(1+2^-30, 1-2^-30, -1) =
 *      -2^-60, where a separate multiply then add gives 0
 *   6. dynamic rounding mode (frm): 1/3 rounded up differs from the
 *      round-to-nearest result by one ulp; the inexact flag is raised
 *   7. conversions: (int64_t)-2.75 = -2 (truncation), 2^53 + 1 to double
 *      rounds to even */
#include "sigil.h"

static uint64_t bits(double d) {
  uint64_t u;
  memcpy(&u, &d, 8);
  return u;
}
static uint32_t bitsf(float f) {
  uint32_t u;
  memcpy(&u, &f, 4);
  return u;
}
/* GCC does not model frm/fflags as inputs/outputs of FP instructions,
 * so it may move a plain `a / b` across a CSR write. An asm volatile
 * divide stays in program order relative to the CSR accesses. */
static inline double fdiv_ordered(double a, double b) {
  double r;
  __asm__ volatile("fdiv.d %0, %1, %2" : "=f"(r) : "f"(a), "f"(b));
  return r;
}

/* Distance in units in the last place between two positive doubles. */
static uint64_t ulps(double x, double y) {
  uint64_t a = bits(x), b = bits(y);
  return a > b ? a - b : b - a;
}

int main(void) {
  /* volatile: keep GCC from folding these at compile time. */
  volatile double two = 2.0, one = 1.0, three = 3.0;
  volatile float twof = 2.0f;

  /* 1. Square roots (hardware fsqrt.d / fsqrt.s). */
  double r2 = __builtin_sqrt(two);
  float r2f = __builtin_sqrtf(twof);
  sigil_printf("sqrt(2) = ");
  sigil_print_fixed(r2, 15);
  sigil_printf(" (0x%016lx), sqrtf(2) = 0x%08x\n", (unsigned long)bits(r2),
               (unsigned)bitsf(r2f));
  SIGIL_CHECK(bits(r2) == 0x3FF6A09E667F3BCDULL);
  SIGIL_CHECK(bitsf(r2f) == 0x3FB504F3u);

  /* 2. Newton's method for sqrt(2). */
  double x = one;
  int steps = 0;
  while (ulps(x, r2) > 1 && steps < 10) {
    x = (x + two / x) * 0.5;
    steps++;
  }
  sigil_printf("Newton: %d steps to within 1 ulp of sqrt(2)\n", steps);
  SIGIL_CHECK(steps <= 6);

  /* 3. e from its series. */
  double e = 0.0, term = one;
  for (int k = 1; k <= 21; k++) {
    e += term;
    term /= (double)k;
  }
  sigil_printf("e ~= ");
  sigil_print_fixed(e, 15);
  sigil_putc('\n');
  SIGIL_CHECK(ulps(e, 2.718281828459045) <= 2);

  /* 4. Dot product: sum over i of i * 0.5, i = 1..100 = 2525 exactly. */
  static double va[100], vb[100];
  for (int i = 0; i < 100; i++) {
    va[i] = (double)(i + 1);
    vb[i] = 0.5;
  }
  sigil_perf_t p = sigil_perf_now();
  double dot = 0.0;
  for (int i = 0; i < 100; i++) dot += va[i] * vb[i];
  sigil_perf_t t = sigil_perf_since(p);
  sigil_printf("dot = ");
  sigil_print_fixed(dot, 1);
  sigil_printf(" in %lu cycles\n", (unsigned long)t.cycles);
  SIGIL_CHECK(dot == 2525.0);

  /* 5. Fused multiply-add (fmadd.d) vs multiply then add. */
  volatile double fa = 1.0 + 0x1p-30, fb = 1.0 - 0x1p-30, fc = -1.0;
  double fused = __builtin_fma(fa, fb, fc);
  volatile double prod = fa * fb; /* rounds to 1.0 */
  double split = prod + fc;
  SIGIL_CHECK(fused == -0x1p-60);
  SIGIL_CHECK(split == 0.0);

  /* 6. Rounding mode and exception flags. */
  sigil_csr_write(fflags, 0);
  double third_rn = fdiv_ordered(one, three);
  uint64_t flags = sigil_csr_read(fflags);
  sigil_csr_write(frm, 3); /* RUP: round towards +infinity */
  double third_up = fdiv_ordered(one, three);
  sigil_csr_write(frm, 0); /* back to RNE */
  SIGIL_CHECK(bits(third_rn) == 0x3FD5555555555555ULL);
  SIGIL_CHECK(bits(third_up) == 0x3FD5555555555556ULL);
  SIGIL_CHECK(flags & 1); /* NX: inexact */
  sigil_csr_write(fflags, 0);
  double four = fdiv_ordered(two * two, one);
  SIGIL_CHECK(four == 4.0 && sigil_csr_read(fflags) == 0);

  /* 7. Conversions. */
  volatile double neg = -2.75;
  volatile int64_t big = (1LL << 53) + 1;
  SIGIL_CHECK((int64_t)neg == -2);
  SIGIL_CHECK((double)big == 0x1p53);
  return 0;
}
