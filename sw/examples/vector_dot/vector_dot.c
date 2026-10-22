/* vector_dot: RVV 1.0 code with the C intrinsics (<riscv_vector.h>).
 *
 * The core implements RVV 1.0 with VLEN = 512 bits and ELEN = 64
 * (docs/CORE.md, "Vector unit"). Code written with vsetvl strip-mining
 * is VLEN-agnostic: the same binary runs on any RVV 1.0 machine.
 * Checks:
 *   1. vlenb = 64 (VLEN 512) and vsetvlmax(e32, m1) = 16 elements
 *   2. int32 dot product (64-bit accumulation, vwmacc) == scalar C for
 *      every length 0..100 and for n = 1000
 *   3. vector byte copy (vle8/vse8) == source for unaligned offsets and
 *      odd lengths, without touching the guard bytes around the copy
 * and prints cycle counts for vector vs scalar code. The vector unit is
 * element-serial today (one element per cycle, a few cycles per vector
 * memory element), so expect correctness rather than a big speedup;
 * the counts show where it stands. */
#include <riscv_vector.h>

#include "sigil.h"

#define N 1000
static int32_t a[N], b[N];
static uint8_t src[4200], dst[4200];

/* Scalar reference; keep GCC from auto-vectorizing it. */
__attribute__((noinline, optimize("no-tree-vectorize"))) static int64_t
dot_scalar(const int32_t *x, const int32_t *y, size_t n) {
  int64_t s = 0;
  for (size_t i = 0; i < n; i++) s += (int64_t)x[i] * y[i];
  return s;
}

/* Vector dot product: per strip, widen-multiply-accumulate into a
 * 64-bit vector accumulator (tail undisturbed so short last strips
 * keep the earlier partial sums), then one reduction at the end. */
__attribute__((noinline)) static int64_t dot_vector(const int32_t *x,
                                                    const int32_t *y, size_t n) {
  size_t vlmax = __riscv_vsetvlmax_e64m8();
  vint64m8_t acc = __riscv_vmv_v_x_i64m8(0, vlmax);
  for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
    vl = __riscv_vsetvl_e32m4(n);
    vint32m4_t vx = __riscv_vle32_v_i32m4(x, vl);
    vint32m4_t vy = __riscv_vle32_v_i32m4(y, vl);
    acc = __riscv_vwmacc_vv_i64m8_tu(acc, vx, vy, vl);
  }
  vint64m1_t zero = __riscv_vmv_v_x_i64m1(0, 1);
  vint64m1_t sum = __riscv_vredsum_vs_i64m8_i64m1(acc, zero, vlmax);
  return __riscv_vmv_x_s_i64m1_i64(sum);
}

/* Vector memcpy: bytes, LMUL = 8 (up to 512 bytes per strip). */
__attribute__((noinline)) static void copy_vector(uint8_t *d, const uint8_t *s,
                                                  size_t n) {
  for (size_t vl; n > 0; n -= vl, s += vl, d += vl) {
    vl = __riscv_vsetvl_e8m8(n);
    __riscv_vse8_v_u8m8(d, __riscv_vle8_v_u8m8(s, vl), vl);
  }
}

int main(void) {
  /* 1. Vector length. */
  uint64_t vlenb = sigil_csr_read(vlenb);
  size_t vl16 = __riscv_vsetvlmax_e32m1();
  sigil_printf("VLEN = %lu bits, e32/m1 holds %lu elements\n",
               (unsigned long)(vlenb * 8), (unsigned long)vl16);
  SIGIL_CHECK(vlenb == 64);
  SIGIL_CHECK(vl16 == 16);

  /* Test data with negative values and large magnitudes. */
  uint32_t x = 1;
  for (int i = 0; i < N; i++) {
    x = x * 1664525u + 1013904223u;
    a[i] = (int32_t)x;
    x = x * 1664525u + 1013904223u;
    b[i] = (int32_t)x >> 8;
  }

  /* 2. Dot product: every short length (strip tails), then N. */
  for (size_t n = 0; n <= 100; n++) SIGIL_CHECK(dot_vector(a, b, n) == dot_scalar(a, b, n));
  sigil_perf_t p = sigil_perf_now();
  int64_t dv = dot_vector(a, b, N);
  sigil_perf_t tv = sigil_perf_since(p);
  p = sigil_perf_now();
  int64_t ds = dot_scalar(a, b, N);
  sigil_perf_t ts = sigil_perf_since(p);
  SIGIL_CHECK(dv == ds);
  sigil_printf("dot(%d x int32) = %ld: vector %lu cycles (%lu instr), "
               "scalar %lu cycles (%lu instr)\n",
               N, (long)dv, (unsigned long)tv.cycles, (unsigned long)tv.instret,
               (unsigned long)ts.cycles, (unsigned long)ts.instret);

  /* 3. Byte copy at unaligned offsets, guard bytes must survive. */
  for (size_t i = 0; i < sizeof src; i++) src[i] = (uint8_t)(i * 37 + 11);
  static const size_t offs[][3] = {{0, 0, 4096}, {1, 3, 4093}, {7, 2, 1}, {5, 5, 777}, {3, 0, 0}};
  for (unsigned t = 0; t < sizeof offs / sizeof offs[0]; t++) {
    size_t so = offs[t][0], d0 = offs[t][1], n = offs[t][2];
    memset(dst, 0xA5, sizeof dst);
    copy_vector(dst + 8 + d0, src + so, n);
    SIGIL_CHECK(memcmp(dst + 8 + d0, src + so, n) == 0);
    for (size_t i = 0; i < 8 + d0; i++) SIGIL_CHECK(dst[i] == 0xA5);
    for (size_t i = 8 + d0 + n; i < sizeof dst; i++) SIGIL_CHECK(dst[i] == 0xA5);
  }
  p = sigil_perf_now();
  copy_vector(dst, src, 4096);
  uint64_t cv = sigil_perf_since(p).cycles;
  p = sigil_perf_now();
  memcpy(dst, src, 4096); /* SDK memcpy: 8 bytes per ld/sd */
  uint64_t cs = sigil_perf_since(p).cycles;
  sigil_printf("copy 4096 bytes: vector (e8) %lu cycles, scalar memcpy %lu cycles\n",
               (unsigned long)cv, (unsigned long)cs);
  return 0;
}
