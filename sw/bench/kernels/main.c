/* Vector and FP kernels benchmark (issue #56, sw/bench/kernels/README.md).
 *
 * Thirteen kernels, each measured as portable C (kern_c.c; scalar ISA
 * in the default build) and as RVV intrinsics (kern_rvv.c), plus an e8
 * RVV form of memcpy and memset. Per kernel and implementation:
 *
 *   1. one warm-up call (caches and branch state; outside the region),
 *   2. the output is poisoned (in-place kernels: inputs restored),
 *   3. measured region 10*kernel + impl (impl 0 = C, 1 = RVV,
 *      2 = RVV e8): KERNELS_ITERATIONS calls back to back,
 *   4. after all regions: the scalar reference's output must hash to
 *      the host-computed KAT (kernels_kat.h), and the C and RVV outputs
 *      must equal the reference bit for bit (arrays: every byte, plus
 *      64-byte guard bands on both sides left untouched).
 *
 * Any mismatch fails the test; "KERNEL <name> CHECK OK ..." lines and
 * the final "KERNELS CHECK OK" are printed only when every check of
 * that kernel passed. The cycle numbers printed here are the hardware
 * counters (mcycle) of each region: what an F2 run reports. */
#include "kernels.h"
#include "kernels_kat.h"
#include "sigil.h"

#ifndef KERNELS_ITERATIONS
#define KERNELS_ITERATIONS 4
#endif
#define R ((unsigned)KERNELS_ITERATIONS)

/* ---- deterministic inputs: splitmix64 (kernels_model.py mirrors it) */
typedef struct {
  uint64_t x;
} rng_t;

static uint64_t rng_next(rng_t *r) {
  uint64_t z = (r->x += 0x9e3779b97f4a7c15ull);
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ull;
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebull;
  return z ^ (z >> 31);
}

/* One stream per (kernel, array). */
static rng_t rng_seed(unsigned kernel, unsigned array) {
  rng_t r = {0x5349474c4b524e00ull ^ ((uint64_t)kernel << 8) ^ array};
  return r;
}

/* k with 1 <= |k| <= 127; the FP inputs are k/16 (exact products and
 * sums, see ref.c). */
static int fp_k(rng_t *r) {
  int k = (int)((rng_next(r) >> 33) % 254u) - 127;
  return k >= 0 ? k + 1 : k;
}

static void fill_f64(double *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (double)fp_k(&r) * 0.0625;
}
static void fill_f32(float *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (float)fp_k(&r) * 0.0625f;
}
/* int32 in [-2^30, 2^30) and int64 in [-2^62, 2^62): sums of two do not
 * overflow (the C kernels add in the signed type). */
static void fill_i32_half(int32_t *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (int32_t)(rng_next(&r) >> 32) >> 1;
}
static void fill_i64_half(int64_t *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (int64_t)rng_next(&r) >> 1;
}
static void fill_i32(int32_t *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (int32_t)(rng_next(&r) >> 32);
}
static void fill_i16(int16_t *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (int16_t)(rng_next(&r) >> 48);
}
static void fill_i8(int8_t *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (int8_t)(rng_next(&r) >> 56);
}
static void fill_u8(uint8_t *p, size_t n, rng_t r) {
  for (size_t i = 0; i < n; i++) p[i] = (uint8_t)(rng_next(&r) >> 56);
}

/* ---- buffers: a static pool, 64-byte aligned, with a 64-byte guard
 * band before and after each buffer, so consecutive 4 KiB buffers are
 * also skewed by two cache lines. Each buffer's guard bands hold their
 * own byte value, so an overrun that copies another buffer's guard
 * (memcpy reading past its source) is still caught. Reset per kernel. */
#define POOL_BYTES (64u * 1024u)
#define GUARD 64u
#define MAXBUF 8u
#define POISON 0x5A /* differs from every canary() */
static uint8_t pool[POOL_BYTES] __attribute__((aligned(4096)));
static size_t pool_used;
static const uint8_t *buf_ptr[MAXBUF];
static unsigned nbuf;

static size_t round64(size_t n) { return (n + 63u) & ~(size_t)63u; }

/* Guard byte of buffer i: eight distinct values. */
static uint8_t canary(unsigned i) { return (uint8_t)(0xA5 ^ (0x3B * (i + 1))); }

static void *buf(size_t bytes) {
  size_t span = round64(bytes) + 2u * GUARD;
  if (pool_used + span > POOL_BYTES || nbuf == MAXBUF) sigil_fail("buffer pool exhausted");
  uint8_t *p = pool + pool_used;
  memset(p, canary(nbuf), span);
  pool_used += span;
  buf_ptr[nbuf++] = p + GUARD;
  return p + GUARD;
}

static int guards_ok(const void *buffer, size_t bytes) {
  const uint8_t *q = buffer;
  unsigned i = 0;
  while (i < nbuf && buf_ptr[i] != q) i++;
  if (i == nbuf) return 0;
  for (size_t j = 1; j <= GUARD; j++)
    if (q[-(ptrdiff_t)j] != canary(i)) return 0;
  for (size_t j = bytes; j < round64(bytes) + GUARD; j++)
    if (q[j] != canary(i)) return 0;
  return 1;
}

/* ---- checks ---- */
static uint64_t fnv1a64(const void *p, size_t n) {
  const uint8_t *b = p;
  uint64_t h = 0xcbf29ce484222325ull;
  for (size_t i = 0; i < n; i++) h = (h ^ b[i]) * 0x100000001b3ull;
  return h;
}

static const char *cur; /* kernel being checked */

static void fail_at(const char *what, long idx) {
  sigil_printf("KERNEL %s: %s MISMATCH", cur, what);
  if (idx >= 0) sigil_printf(" at byte %ld", idx);
  sigil_printf("\n");
  sigil_fail(cur);
}

static void check_kat(const void *ref, size_t bytes, uint64_t kat) {
  uint64_t h = fnv1a64(ref, bytes);
  if (h != kat) {
    sigil_printf("KERNEL %s: reference hash %016lx, KAT %016lx\n", cur,
                 (unsigned long)h, (unsigned long)kat);
    fail_at("reference vs KAT", -1);
  }
}

/* Array output: equal to the reference byte for byte, guards intact. */
static void check_out(const char *impl, const void *out, const void *ref, size_t bytes) {
  const uint8_t *a = out, *b = ref;
  for (size_t i = 0; i < bytes; i++)
    if (a[i] != b[i]) fail_at(impl, (long)i);
  if (!guards_ok(out, bytes)) {
    sigil_printf("KERNEL %s: %s wrote outside its output (guard band)\n", cur, impl);
    fail_at(impl, -1);
  }
}

static void check_val(const char *impl, const void *v, const void *ref, size_t bytes) {
  if (memcmp(v, ref, bytes) != 0) fail_at(impl, -1);
}

/* ---- measurement ---- */
enum { IMPL_C, IMPL_RVV, IMPL_RVV8, NIMPL };
static const char *const impl_name[NIMPL] = {"C", "RVV", "RVV-e8"};
static uint64_t cyc[NIMPL], ins[NIMPL];
static unsigned nimpl;

/* Warm-up call, `reset` (poison the output / restore in-place inputs),
 * then region 10*k + impl: R calls. */
#define MEASURE(k, impl, reset, call)                     \
  do {                                                    \
    call;                                                 \
    reset;                                                \
    sigil_perf_begin_id(10u * (k) + (impl));              \
    for (unsigned r_ = 0; r_ < R; r_++) {                 \
      call;                                               \
    }                                                     \
    sigil_perf_t t_ = sigil_perf_end_id(10u * (k) + (impl)); \
    cyc[impl] = t_.cycles;                                \
    ins[impl] = t_.instret;                               \
    if ((impl) + 1u > nimpl) nimpl = (impl) + 1u;         \
  } while (0)

/* "KERNEL <name> <units> <unit>/call: C <cycles>/call <units/cycle>
 * ... speedup <C/RVV>" from the hardware counters, then the expect
 * line. */
static void report(unsigned units, const char *unit) {
  sigil_printf("KERNEL %s %u %s per call:", cur, units, unit);
  for (unsigned i = 0; i < nimpl; i++) {
    sigil_printf(" %s ", impl_name[i]);
    sigil_print_fixed((double)cyc[i] / R, 1);
    sigil_printf(" cyc (IPC ");
    sigil_print_fixed((double)ins[i] / (double)cyc[i], 3);
    sigil_printf(", ");
    sigil_print_fixed((double)units * R / (double)cyc[i], 4);
    sigil_printf(" %s/cyc)", unit);
  }
  for (unsigned i = 1; i < nimpl; i++) {
    sigil_printf(" speedup %s ", impl_name[i]);
    sigil_print_fixed((double)cyc[IMPL_C] / (double)cyc[i], 2);
    sigil_printf("x");
  }
  sigil_printf("\nKERNEL %s CHECK OK %s=%u iterations=%u\n", cur, unit, units, R);
  nimpl = 0;
}

static void begin(const char *name) {
  cur = name;
  pool_used = 0;
  nbuf = 0;
}

/* ---- the kernels ---- */
static void k_vadd_i32(void) {
  const size_t n = KN_32, nb = n * sizeof(int32_t);
  begin("vadd_i32");
  int32_t *a = buf(nb), *b = buf(nb), *cc = buf(nb), *cv = buf(nb), *cr = buf(nb);
  fill_i32_half(a, n, rng_seed(1, 0));
  fill_i32_half(b, n, rng_seed(1, 1));
  vadd_i32_ref(cr, a, b, n);
  MEASURE(1, IMPL_C, memset(cc, POISON, nb), vadd_i32_c(cc, a, b, n));
  MEASURE(1, IMPL_RVV, memset(cv, POISON, nb), vadd_i32_rvv(cv, a, b, n));
  check_kat(cr, nb, KAT_VADD_I32);
  check_out("C", cc, cr, nb);
  check_out("RVV", cv, cr, nb);
  report(n, "elem");
}

static void k_vadd_i64(void) {
  const size_t n = KN_64, nb = n * sizeof(int64_t);
  begin("vadd_i64");
  int64_t *a = buf(nb), *b = buf(nb), *cc = buf(nb), *cv = buf(nb), *cr = buf(nb);
  fill_i64_half(a, n, rng_seed(2, 0));
  fill_i64_half(b, n, rng_seed(2, 1));
  vadd_i64_ref(cr, a, b, n);
  MEASURE(2, IMPL_C, memset(cc, POISON, nb), vadd_i64_c(cc, a, b, n));
  MEASURE(2, IMPL_RVV, memset(cv, POISON, nb), vadd_i64_rvv(cv, a, b, n));
  check_kat(cr, nb, KAT_VADD_I64);
  check_out("C", cc, cr, nb);
  check_out("RVV", cv, cr, nb);
  report(n, "elem");
}

/* In place: y is restored after the warm-up, so each region computes
 * y0 + R*a*x, which the reference reproduces (R applications). The KAT
 * covers one application. */
static void k_daxpy(void) {
  const size_t n = KN_64, nb = n * sizeof(double);
  const double a = KN_AXPY_A;
  begin("daxpy");
  double *x = buf(nb), *y0 = buf(nb), *yc = buf(nb), *yv = buf(nb), *yr = buf(nb);
  fill_f64(x, n, rng_seed(3, 0));
  fill_f64(y0, n, rng_seed(3, 1));
  memcpy(yr, y0, nb);
  daxpy_ref(n, a, x, yr);
  check_kat(yr, nb, KAT_DAXPY);
  memcpy(yr, y0, nb);
  for (unsigned r = 0; r < R; r++) daxpy_ref(n, a, x, yr);
  memcpy(yc, y0, nb);
  memcpy(yv, y0, nb);
  MEASURE(3, IMPL_C, memcpy(yc, y0, nb), daxpy_c(n, a, x, yc));
  MEASURE(3, IMPL_RVV, memcpy(yv, y0, nb), daxpy_rvv(n, a, x, yv));
  check_out("C", yc, yr, nb);
  check_out("RVV", yv, yr, nb);
  report(n, "elem");
}

static void k_saxpy(void) {
  const size_t n = KN_32, nb = n * sizeof(float);
  const float a = (float)KN_AXPY_A;
  begin("saxpy");
  float *x = buf(nb), *y0 = buf(nb), *yc = buf(nb), *yv = buf(nb), *yr = buf(nb);
  fill_f32(x, n, rng_seed(4, 0));
  fill_f32(y0, n, rng_seed(4, 1));
  memcpy(yr, y0, nb);
  saxpy_ref(n, a, x, yr);
  check_kat(yr, nb, KAT_SAXPY);
  memcpy(yr, y0, nb);
  for (unsigned r = 0; r < R; r++) saxpy_ref(n, a, x, yr);
  memcpy(yc, y0, nb);
  memcpy(yv, y0, nb);
  MEASURE(4, IMPL_C, memcpy(yc, y0, nb), saxpy_c(n, a, x, yc));
  MEASURE(4, IMPL_RVV, memcpy(yv, y0, nb), saxpy_rvv(n, a, x, yv));
  check_out("C", yc, yr, nb);
  check_out("RVV", yv, yr, nb);
  report(n, "elem");
}

static void k_ddot(void) {
  const size_t n = KN_64, nb = n * sizeof(double);
  begin("ddot");
  double *x = buf(nb), *y = buf(nb);
  fill_f64(x, n, rng_seed(5, 0));
  fill_f64(y, n, rng_seed(5, 1));
  double sr = ddot_ref(n, x, y), sc = 0, sv = 0;
  MEASURE(5, IMPL_C, sc = 0, sc = ddot_c(n, x, y));
  MEASURE(5, IMPL_RVV, sv = 0, sv = ddot_rvv(n, x, y));
  check_kat(&sr, sizeof sr, KAT_DDOT);
  check_val("C", &sc, &sr, sizeof sr);
  check_val("RVV", &sv, &sr, sizeof sr);
  report(n, "elem");
}

static void k_idot(void) {
  const size_t n = KN_32, nb = n * sizeof(int32_t);
  begin("idot_i32");
  int32_t *x = buf(nb), *y = buf(nb);
  fill_i32(x, n, rng_seed(6, 0));
  fill_i32(y, n, rng_seed(6, 1));
  uint64_t sr = idot_ref(n, x, y), sc = 0, sv = 0;
  MEASURE(6, IMPL_C, sc = 0, sc = idot_c(n, x, y));
  MEASURE(6, IMPL_RVV, sv = 0, sv = idot_rvv(n, x, y));
  check_kat(&sr, sizeof sr, KAT_IDOT_I32);
  check_val("C", &sc, &sr, sizeof sr);
  check_val("RVV", &sv, &sr, sizeof sr);
  report(n, "elem");
}

static void k_memcpy(void) {
  const size_t n = KN_MEM;
  begin("memcpy");
  uint8_t *s = buf(n), *dc = buf(n), *dv = buf(n), *d8 = buf(n), *dr = buf(n);
  fill_u8(s, n, rng_seed(7, 0));
  memcpy_ref(dr, s, n);
  MEASURE(7, IMPL_C, memset(dc, POISON, n), memcpy_c(dc, s, n));
  MEASURE(7, IMPL_RVV, memset(dv, POISON, n), memcpy_rvv(dv, s, n));
  MEASURE(7, IMPL_RVV8, memset(d8, POISON, n), memcpy_rvv8(d8, s, n));
  check_kat(dr, n, KAT_MEMCPY);
  check_out("C", dc, dr, n);
  check_out("RVV", dv, dr, n);
  check_out("RVV-e8", d8, dr, n);
  report(n, "byte");
}

static void k_memset(void) {
  const size_t n = KN_MEM;
  const int c = 0x3C;
  begin("memset");
  uint8_t *dc = buf(n), *dv = buf(n), *d8 = buf(n), *dr = buf(n);
  memset_ref(dr, c, n);
  MEASURE(8, IMPL_C, memset(dc, POISON, n), memset_c(dc, c, n));
  MEASURE(8, IMPL_RVV, memset(dv, POISON, n), memset_rvv(dv, c, n));
  MEASURE(8, IMPL_RVV8, memset(d8, POISON, n), memset_rvv8(d8, c, n));
  check_kat(dr, n, KAT_MEMSET);
  check_out("C", dc, dr, n);
  check_out("RVV", dv, dr, n);
  check_out("RVV-e8", d8, dr, n);
  report(n, "byte");
}

static void k_dgemm(void) {
  const size_t n = KN_GEMM, nb = n * n * sizeof(double);
  begin("dgemm");
  double *a = buf(nb), *b = buf(nb), *cc = buf(nb), *cv = buf(nb), *cr = buf(nb);
  fill_f64(a, n * n, rng_seed(9, 0));
  fill_f64(b, n * n, rng_seed(9, 1));
  dgemm_ref(n, a, b, cr);
  MEASURE(9, IMPL_C, memset(cc, POISON, nb), dgemm_c(n, a, b, cc));
  MEASURE(9, IMPL_RVV, memset(cv, POISON, nb), dgemm_rvv(n, a, b, cv));
  check_kat(cr, nb, KAT_DGEMM);
  check_out("C", cc, cr, nb);
  check_out("RVV", cv, cr, nb);
  report(n * n * n, "mac");
}

static void k_sgemm(void) {
  const size_t n = KN_GEMM, nb = n * n * sizeof(float);
  begin("sgemm");
  float *a = buf(nb), *b = buf(nb), *cc = buf(nb), *cv = buf(nb), *cr = buf(nb);
  fill_f32(a, n * n, rng_seed(10, 0));
  fill_f32(b, n * n, rng_seed(10, 1));
  sgemm_ref(n, a, b, cr);
  MEASURE(10, IMPL_C, memset(cc, POISON, nb), sgemm_c(n, a, b, cc));
  MEASURE(10, IMPL_RVV, memset(cv, POISON, nb), sgemm_rvv(n, a, b, cv));
  check_kat(cr, nb, KAT_SGEMM);
  check_out("C", cc, cr, nb);
  check_out("RVV", cv, cr, nb);
  report(n * n * n, "mac");
}

static void k_fir(void) {
  const size_t n = KN_FIR, t = KN_TAPS, nb = n * sizeof(float);
  begin("fir_f32");
  float *h = buf(t * sizeof(float)), *x = buf((n + t - 1) * sizeof(float));
  float *yc = buf(nb), *yv = buf(nb), *yr = buf(nb);
  fill_f32(h, t, rng_seed(11, 0));
  fill_f32(x, n + t - 1, rng_seed(11, 1));
  fir_f32_ref(n, t, h, x, yr);
  MEASURE(11, IMPL_C, memset(yc, POISON, nb), fir_f32_c(n, t, h, x, yc));
  MEASURE(11, IMPL_RVV, memset(yv, POISON, nb), fir_f32_rvv(n, t, h, x, yv));
  check_kat(yr, nb, KAT_FIR_F32);
  check_out("C", yc, yr, nb);
  check_out("RVV", yv, yr, nb);
  report(n * t, "mac");
}

static void k_mac_i8(void) {
  const size_t n = KN_I8;
  begin("mac_i8");
  int8_t *x = buf(n), *y = buf(n);
  fill_i8(x, n, rng_seed(12, 0));
  fill_i8(y, n, rng_seed(12, 1));
  uint32_t sr = mac_i8_ref(n, x, y), sc = 0, sv = 0;
  MEASURE(12, IMPL_C, sc = 0, sc = mac_i8_c(n, x, y));
  MEASURE(12, IMPL_RVV, sv = 0, sv = mac_i8_rvv(n, x, y));
  check_kat(&sr, sizeof sr, KAT_MAC_I8);
  check_val("C", &sc, &sr, sizeof sr);
  check_val("RVV", &sv, &sr, sizeof sr);
  report(n, "mac");
}

static void k_mac_i16(void) {
  const size_t n = KN_I16, nb = n * sizeof(int16_t);
  begin("mac_i16");
  int16_t *x = buf(nb), *y = buf(nb);
  fill_i16(x, n, rng_seed(13, 0));
  fill_i16(y, n, rng_seed(13, 1));
  uint32_t sr = mac_i16_ref(n, x, y), sc = 0, sv = 0;
  MEASURE(13, IMPL_C, sc = 0, sc = mac_i16_c(n, x, y));
  MEASURE(13, IMPL_RVV, sv = 0, sv = mac_i16_rvv(n, x, y));
  check_kat(&sr, sizeof sr, KAT_MAC_I16);
  check_val("C", &sc, &sr, sizeof sr);
  check_val("RVV", &sv, &sr, sizeof sr);
  report(n, "mac");
}

int main(void) {
  sigil_printf("kernels: VLEN=%lu bits, %u calls per region\n",
               (unsigned long)(sigil_csr_read(vlenb) * 8), R);
  k_vadd_i32();
  k_vadd_i64();
  k_daxpy();
  k_saxpy();
  k_ddot();
  k_idot();
  k_memcpy();
  k_memset();
  k_dgemm();
  k_sgemm();
  k_fir();
  k_mac_i8();
  k_mac_i16();
  sigil_printf("KERNELS CHECK OK kernels=13 iterations=%u\n", R);
  sigil_pass();
}
