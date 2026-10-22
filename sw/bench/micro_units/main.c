/* micro_units: M unit and FPU latency and back-to-back throughput in
 * cycles per operation (../micro_common/README.md). Kernels:
 * kernels.S. Every kernel result is checked against the same chain
 * computed in C. Region labels match bench.json. */
#include "micro.h"

#define U 64 /* operations per loop trip, kernels.S */

uint64_t k_empty(void);
uint64_t k_mul_dep(uint64_t trips, uint64_t x, uint64_t y);
uint64_t k_mul_indep(uint64_t trips, uint64_t x, uint64_t y);
uint64_t k_div_dep(uint64_t trips, uint64_t x, uint64_t y);
uint64_t k_div_indep(uint64_t trips, uint64_t x, uint64_t y);
uint64_t k_divw_dep(uint64_t trips, uint64_t x, uint64_t y);
uint64_t k_rem_indep(uint64_t trips, uint64_t x, uint64_t y);
double k_fadd_d_dep(uint64_t trips, double x, double y);
double k_fadd_d_indep(uint64_t trips, double x, double y);
double k_fmul_d_dep(uint64_t trips, double x, double y);
double k_fmadd_d_dep(uint64_t trips, double x, double a, double b);
double k_fdiv_d_dep(uint64_t trips, double x, double y);
double k_fdiv_d_indep(uint64_t trips, double x, double y);
double k_fsqrt_d_dep(uint64_t trips, double x);
double k_fsqrt_d_indep(uint64_t trips, double x);
float k_fdiv_s_dep(uint64_t trips, float x, float y);
float k_fsqrt_s_dep(uint64_t trips, float x);

static uint64_t dbits(double d) {
  uint64_t u;
  __builtin_memcpy(&u, &d, sizeof u);
  return u;
}

static uint64_t fbits(float f) {
  uint32_t u;
  __builtin_memcpy(&u, &f, sizeof u);
  return u;
}

/* C references for the dependent chains (n operations). */
static uint64_t ref_mul(uint64_t x, uint64_t y, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x *= y;
  return x;
}
static double ref_fadd(double x, double y, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x = x + y;
  return x;
}
static double ref_fmul(double x, double y, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x = x * y;
  return x;
}
static double ref_fmadd(double x, double a, double b, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x = __builtin_fma(x, a, b);
  return x;
}
static double ref_fdiv(double x, double y, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x = x / y;
  return x;
}
static double ref_fsqrt(double x, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x = __builtin_sqrt(x);
  return x;
}
static float ref_fdiv_s(float x, float y, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x = x / y;
  return x;
}
static float ref_fsqrt_s(float x, uint64_t n) {
  for (uint64_t i = 0; i < n; i++) x = __builtin_sqrtf(x);
  return x;
}

int main(void) {
  const uint64_t trips = micro_trips(U), ops = trips * U;
  /* 63 significant quotient bits for the full-length divides (the
   * divider iterates over significant quotient digits only). */
  const uint64_t big = 0x7123456789abcdefull, big32 = 0x71234567ull;
  const uint64_t m = 0x9E3779B97F4A7C15ull, x0 = 0x0123456789abcdefull;
  uint64_t r;
  double d;
  float f;

  MICRO_REGION(1, "empty", ops, k_empty(), r = k_empty());
  micro_check("empty", "result", r, 0);

  MICRO_REGION(2, "mul_dep", ops, k_mul_dep(1, 1, 1), r = k_mul_dep(trips, x0, m));
  micro_check("mul_dep", "product", r, ref_mul(x0, m, ops));
  MICRO_REGION(3, "mul_indep", ops, k_mul_indep(1, 1, 1), r = k_mul_indep(trips, x0, m));
  micro_check("mul_indep", "product", r, x0 * m);

  MICRO_REGION(4, "div_dep", ops, k_div_dep(1, 1, 1), r = k_div_dep(trips, big, 1));
  micro_check("div_dep", "quotient", r, big);
  MICRO_REGION(5, "div_indep", ops, k_div_indep(1, 1, 1), r = k_div_indep(trips, big, 1));
  micro_check("div_indep", "quotient", r, big);
  MICRO_REGION(6, "div_short", ops, k_div_indep(1, 1, 1), r = k_div_indep(trips, 3, 7));
  micro_check("div_short", "quotient", r, 0);
  MICRO_REGION(7, "divw_dep", ops, k_divw_dep(1, 1, 1), r = k_divw_dep(trips, big32, 1));
  micro_check("divw_dep", "quotient", r, big32);
  MICRO_REGION(8, "rem_indep", ops, k_rem_indep(1, 1, 1), r = k_rem_indep(trips, big, 3));
  micro_check("rem_indep", "remainder", r, big % 3);

  const double one = 1.0, tiny = 0x1p-30, grow = 1.0 + 0x1p-20;
  MICRO_REGION(9, "fadd_d_dep", ops, k_fadd_d_dep(1, 0, 0), d = k_fadd_d_dep(trips, one, tiny));
  micro_check("fadd_d_dep", "sum", dbits(d), dbits(ref_fadd(one, tiny, ops)));
  MICRO_REGION(10, "fadd_d_indep", ops, k_fadd_d_indep(1, 0, 0),
               d = k_fadd_d_indep(trips, one, tiny));
  micro_check("fadd_d_indep", "sum", dbits(d), dbits(one + tiny));
  MICRO_REGION(11, "fmul_d_dep", ops, k_fmul_d_dep(1, 0, 0), d = k_fmul_d_dep(trips, one, grow));
  micro_check("fmul_d_dep", "product", dbits(d), dbits(ref_fmul(one, grow, ops)));
  MICRO_REGION(12, "fmadd_d_dep", ops, k_fmadd_d_dep(1, 0, 0, 0),
               d = k_fmadd_d_dep(trips, 0.5, 1.0 - 0x1p-10, 0x1p-10));
  micro_check("fmadd_d_dep", "result", dbits(d),
              dbits(ref_fmadd(0.5, 1.0 - 0x1p-10, 0x1p-10, ops)));
  MICRO_REGION(13, "fdiv_d_dep", ops, k_fdiv_d_dep(1, 1, 1), d = k_fdiv_d_dep(trips, 3.0, grow));
  micro_check("fdiv_d_dep", "quotient", dbits(d), dbits(ref_fdiv(3.0, grow, ops)));
  MICRO_REGION(14, "fdiv_d_indep", ops, k_fdiv_d_indep(1, 1, 1),
               d = k_fdiv_d_indep(trips, 1.0, 3.0));
  micro_check("fdiv_d_indep", "quotient", dbits(d), dbits(1.0 / 3.0));
  MICRO_REGION(15, "fsqrt_d_dep", ops, k_fsqrt_d_dep(1, 1), d = k_fsqrt_d_dep(trips, 1e300));
  micro_check("fsqrt_d_dep", "root", dbits(d), dbits(ref_fsqrt(1e300, ops)));
  MICRO_REGION(16, "fsqrt_d_indep", ops, k_fsqrt_d_indep(1, 1), d = k_fsqrt_d_indep(trips, 2.0));
  micro_check("fsqrt_d_indep", "root", dbits(d), dbits(__builtin_sqrt(2.0)));
  MICRO_REGION(17, "fdiv_s_dep", ops, k_fdiv_s_dep(1, 1, 1),
               f = k_fdiv_s_dep(trips, 3.0f, 1.0f + 0x1p-12f));
  micro_check("fdiv_s_dep", "quotient", fbits(f), fbits(ref_fdiv_s(3.0f, 1.0f + 0x1p-12f, ops)));
  MICRO_REGION(18, "fsqrt_s_dep", ops, k_fsqrt_s_dep(1, 1), f = k_fsqrt_s_dep(trips, 1e30f));
  micro_check("fsqrt_s_dep", "root", fbits(f), fbits(ref_fsqrt_s(1e30f, ops)));

  micro_finish(18);
}
