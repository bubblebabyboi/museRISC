/* Kernels with the RVV 1.0 C intrinsics (<riscv_vector.h>): the
 * measured "RVV" implementations.
 *
 * Plain strip-mined loops (vsetvl per strip, LMUL 8 for the widest
 * operand), VLEN-agnostic: the same binary is correct on any RVV 1.0
 * Zve64d machine. On Sigil (VLEN 512) a strip is 64 e64 / 128 e32
 * elements. The dot products accumulate per element in a vector
 * register (tail undisturbed, so a short last strip keeps the other
 * lanes) and reduce once at the end, as vectorized code usually does
 * (mac_i8: see there). Built with the SDK -march (which has V). */
#include <riscv_vector.h>

#include "kernels.h"

void vadd_i32_rvv(int32_t *c, const int32_t *a, const int32_t *b, size_t n) {
  for (size_t vl; n > 0; n -= vl, a += vl, b += vl, c += vl) {
    vl = __riscv_vsetvl_e32m8(n);
    vint32m8_t va = __riscv_vle32_v_i32m8(a, vl);
    vint32m8_t vb = __riscv_vle32_v_i32m8(b, vl);
    __riscv_vse32_v_i32m8(c, __riscv_vadd_vv_i32m8(va, vb, vl), vl);
  }
}

void vadd_i64_rvv(int64_t *c, const int64_t *a, const int64_t *b, size_t n) {
  for (size_t vl; n > 0; n -= vl, a += vl, b += vl, c += vl) {
    vl = __riscv_vsetvl_e64m8(n);
    vint64m8_t va = __riscv_vle64_v_i64m8(a, vl);
    vint64m8_t vb = __riscv_vle64_v_i64m8(b, vl);
    __riscv_vse64_v_i64m8(c, __riscv_vadd_vv_i64m8(va, vb, vl), vl);
  }
}

void daxpy_rvv(size_t n, double a, const double *x, double *y) {
  for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
    vl = __riscv_vsetvl_e64m8(n);
    vfloat64m8_t vx = __riscv_vle64_v_f64m8(x, vl);
    vfloat64m8_t vy = __riscv_vle64_v_f64m8(y, vl);
    __riscv_vse64_v_f64m8(y, __riscv_vfmacc_vf_f64m8(vy, a, vx, vl), vl);
  }
}

void saxpy_rvv(size_t n, float a, const float *x, float *y) {
  for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
    vl = __riscv_vsetvl_e32m8(n);
    vfloat32m8_t vx = __riscv_vle32_v_f32m8(x, vl);
    vfloat32m8_t vy = __riscv_vle32_v_f32m8(y, vl);
    __riscv_vse32_v_f32m8(y, __riscv_vfmacc_vf_f32m8(vy, a, vx, vl), vl);
  }
}

double ddot_rvv(size_t n, const double *x, const double *y) {
  size_t vlmax = __riscv_vsetvlmax_e64m8();
  vfloat64m8_t acc = __riscv_vfmv_v_f_f64m8(0.0, vlmax);
  for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
    vl = __riscv_vsetvl_e64m8(n);
    vfloat64m8_t vx = __riscv_vle64_v_f64m8(x, vl);
    vfloat64m8_t vy = __riscv_vle64_v_f64m8(y, vl);
    acc = __riscv_vfmacc_vv_f64m8_tu(acc, vx, vy, vl);
  }
  vfloat64m1_t z = __riscv_vfmv_s_f_f64m1(0.0, 1);
  vfloat64m1_t s = __riscv_vfredusum_vs_f64m8_f64m1(acc, z, vlmax);
  return __riscv_vfmv_f_s_f64m1_f64(s);
}

uint64_t idot_rvv(size_t n, const int32_t *x, const int32_t *y) {
  size_t vlmax = __riscv_vsetvlmax_e64m8();
  vint64m8_t acc = __riscv_vmv_v_x_i64m8(0, vlmax);
  for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
    vl = __riscv_vsetvl_e32m4(n);
    vint32m4_t vx = __riscv_vle32_v_i32m4(x, vl);
    vint32m4_t vy = __riscv_vle32_v_i32m4(y, vl);
    acc = __riscv_vwmacc_vv_i64m8_tu(acc, vx, vy, vl);
  }
  vint64m1_t z = __riscv_vmv_s_x_i64m1(0, 1);
  vint64m1_t s = __riscv_vredsum_vs_i64m8_i64m1(acc, z, vlmax);
  return (uint64_t)__riscv_vmv_x_s_i64m1_i64(s);
}

/* e64: d, s 8-byte aligned and n % 8 == 0 (main.c only calls it so). */
void memcpy_rvv(void *d, const void *s, size_t n) {
  uint64_t *dp = d;
  const uint64_t *sp = s;
  for (size_t vl, w = n / 8; w > 0; w -= vl, sp += vl, dp += vl) {
    vl = __riscv_vsetvl_e64m8(w);
    __riscv_vse64_v_u64m8(dp, __riscv_vle64_v_u64m8(sp, vl), vl);
  }
}

/* e8: any alignment and length, up to 512 bytes per strip. */
void memcpy_rvv8(void *d, const void *s, size_t n) {
  uint8_t *dp = d;
  const uint8_t *sp = s;
  for (size_t vl; n > 0; n -= vl, sp += vl, dp += vl) {
    vl = __riscv_vsetvl_e8m8(n);
    __riscv_vse8_v_u8m8(dp, __riscv_vle8_v_u8m8(sp, vl), vl);
  }
}

/* e64: d 8-byte aligned and n % 8 == 0. */
void memset_rvv(void *d, int c, size_t n) {
  uint64_t *dp = d;
  uint64_t w8 = (uint64_t)(uint8_t)c * 0x0101010101010101ull;
  vuint64m8_t v = __riscv_vmv_v_x_u64m8(w8, __riscv_vsetvlmax_e64m8());
  for (size_t vl, w = n / 8; w > 0; w -= vl, dp += vl) {
    vl = __riscv_vsetvl_e64m8(w);
    __riscv_vse64_v_u64m8(dp, v, vl);
  }
}

void memset_rvv8(void *d, int c, size_t n) {
  uint8_t *dp = d;
  vuint8m8_t v = __riscv_vmv_v_x_u8m8((uint8_t)c, __riscv_vsetvlmax_e8m8());
  for (size_t vl; n > 0; n -= vl, dp += vl) {
    vl = __riscv_vsetvl_e8m8(n);
    __riscv_vse8_v_u8m8(dp, v, vl);
  }
}

/* Row i of C = sum_k a[i][k] * row k of B (vfmacc.vf), a strip of
 * columns at a time. */
void dgemm_rvv(size_t n, const double *a, const double *b, double *c) {
  for (size_t i = 0; i < n; i++) {
    const double *ai = a + i * n;
    for (size_t j = 0, vl; j < n; j += vl) {
      vl = __riscv_vsetvl_e64m8(n - j);
      vfloat64m8_t acc = __riscv_vfmv_v_f_f64m8(0.0, vl);
      for (size_t k = 0; k < n; k++)
        acc = __riscv_vfmacc_vf_f64m8(acc, ai[k], __riscv_vle64_v_f64m8(b + k * n + j, vl), vl);
      __riscv_vse64_v_f64m8(c + i * n + j, acc, vl);
    }
  }
}

void sgemm_rvv(size_t n, const float *a, const float *b, float *c) {
  for (size_t i = 0; i < n; i++) {
    const float *ai = a + i * n;
    for (size_t j = 0, vl; j < n; j += vl) {
      vl = __riscv_vsetvl_e32m8(n - j);
      vfloat32m8_t acc = __riscv_vfmv_v_f_f32m8(0.0f, vl);
      for (size_t k = 0; k < n; k++)
        acc = __riscv_vfmacc_vf_f32m8(acc, ai[k], __riscv_vle32_v_f32m8(b + k * n + j, vl), vl);
      __riscv_vse32_v_f32m8(c + i * n + j, acc, vl);
    }
  }
}

/* A strip of outputs at a time: acc += h[k] * x[i+k .. i+k+vl). */
void fir_f32_rvv(size_t n, size_t taps, const float *h, const float *x, float *y) {
  for (size_t i = 0, vl; i < n; i += vl) {
    vl = __riscv_vsetvl_e32m8(n - i);
    vfloat32m8_t acc = __riscv_vfmv_v_f_f32m8(0.0f, vl);
    for (size_t k = 0; k < taps; k++)
      acc = __riscv_vfmacc_vf_f32m8(acc, h[k], __riscv_vle32_v_f32m8(x + i + k, vl), vl);
    __riscv_vse32_v_f32m8(y + i, acc, vl);
  }
}

/* int8 x int8 -> int16 products (vwmul), summed per strip into an
 * int32 scalar by the widening reduction (vwredsum): two widening
 * steps, as RVV has no 4x widening MAC. (Accumulating into int32 lanes
 * with vwadd.wv makes GCC 16 copy the accumulator group with vmv8r.v
 * every strip.) */
uint32_t mac_i8_rvv(size_t n, const int8_t *x, const int8_t *y) {
  vint32m1_t s = __riscv_vmv_s_x_i32m1(0, 1);
  for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
    vl = __riscv_vsetvl_e8m4(n);
    vint8m4_t vx = __riscv_vle8_v_i8m4(x, vl);
    vint8m4_t vy = __riscv_vle8_v_i8m4(y, vl);
    s = __riscv_vwredsum_vs_i16m8_i32m1(__riscv_vwmul_vv_i16m8(vx, vy, vl), s, vl);
  }
  return (uint32_t)__riscv_vmv_x_s_i32m1_i32(s);
}

/* int16 x int16 -> int32 widening multiply-accumulate (vwmacc). */
uint32_t mac_i16_rvv(size_t n, const int16_t *x, const int16_t *y) {
  size_t vlmax = __riscv_vsetvlmax_e32m8();
  vint32m8_t acc = __riscv_vmv_v_x_i32m8(0, vlmax);
  for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
    vl = __riscv_vsetvl_e16m4(n);
    vint16m4_t vx = __riscv_vle16_v_i16m4(x, vl);
    vint16m4_t vy = __riscv_vle16_v_i16m4(y, vl);
    acc = __riscv_vwmacc_vv_i32m8_tu(acc, vx, vy, vl);
  }
  vint32m1_t z = __riscv_vmv_s_x_i32m1(0, 1);
  vint32m1_t s = __riscv_vredsum_vs_i32m8_i32m1(acc, z, vlmax);
  return (uint32_t)__riscv_vmv_x_s_i32m1_i32(s);
}
