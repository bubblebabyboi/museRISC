/* Kernels in portable C: the measured "C" implementations.
 *
 * Written the way plain C code is written, with no hand unrolling or
 * intrinsics. The Makefile compiles this file on its own with
 * KERNELS_C_MARCH (default: the scalar ISA, no V) and KERNELS_C_OPT
 * (default -O2), so in the default build these are the scalar
 * baseline; the "autovec" variant builds the same source with V at -O3 for
 * GCC's auto-vectorizer. Floating-point expressions contract to fused
 * multiply-adds (GCC's default -ffp-contract=fast for GNU C), like the
 * RVV vfmacc forms. */
#include "sigil.h" /* memcpy, memset */

#include "kernels.h"

void vadd_i32_c(int32_t *c, const int32_t *a, const int32_t *b, size_t n) {
  for (size_t i = 0; i < n; i++) c[i] = a[i] + b[i];
}

void vadd_i64_c(int64_t *c, const int64_t *a, const int64_t *b, size_t n) {
  for (size_t i = 0; i < n; i++) c[i] = a[i] + b[i];
}

void daxpy_c(size_t n, double a, const double *x, double *y) {
  for (size_t i = 0; i < n; i++) y[i] = a * x[i] + y[i];
}

void saxpy_c(size_t n, float a, const float *x, float *y) {
  for (size_t i = 0; i < n; i++) y[i] = a * x[i] + y[i];
}

double ddot_c(size_t n, const double *x, const double *y) {
  double s = 0.0;
  for (size_t i = 0; i < n; i++) s += x[i] * y[i];
  return s;
}

uint64_t idot_c(size_t n, const int32_t *x, const int32_t *y) {
  uint64_t s = 0;
  for (size_t i = 0; i < n; i++) s += (uint64_t)((int64_t)x[i] * y[i]);
  return s;
}

/* The SDK's library routines (sw/sdk/lib/runtime.c): what a program
 * calls for memcpy/memset. */
void memcpy_c(void *d, const void *s, size_t n) { memcpy(d, s, n); }
void memset_c(void *d, int c, size_t n) { memset(d, c, n); }

void dgemm_c(size_t n, const double *a, const double *b, double *c) {
  for (size_t i = 0; i < n; i++)
    for (size_t j = 0; j < n; j++) {
      double s = 0.0;
      for (size_t k = 0; k < n; k++) s += a[i * n + k] * b[k * n + j];
      c[i * n + j] = s;
    }
}

void sgemm_c(size_t n, const float *a, const float *b, float *c) {
  for (size_t i = 0; i < n; i++)
    for (size_t j = 0; j < n; j++) {
      float s = 0.0f;
      for (size_t k = 0; k < n; k++) s += a[i * n + k] * b[k * n + j];
      c[i * n + j] = s;
    }
}

void fir_f32_c(size_t n, size_t taps, const float *h, const float *x, float *y) {
  for (size_t i = 0; i < n; i++) {
    float s = 0.0f;
    for (size_t k = 0; k < taps; k++) s += h[k] * x[i + k];
    y[i] = s;
  }
}

uint32_t mac_i8_c(size_t n, const int8_t *x, const int8_t *y) {
  uint32_t s = 0;
  for (size_t i = 0; i < n; i++) s += (uint32_t)((int32_t)x[i] * y[i]);
  return s;
}

uint32_t mac_i16_c(size_t n, const int16_t *x, const int16_t *y) {
  uint32_t s = 0;
  for (size_t i = 0; i < n; i++) s += (uint32_t)((int32_t)x[i] * y[i]);
  return s;
}
