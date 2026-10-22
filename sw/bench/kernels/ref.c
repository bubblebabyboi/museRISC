/* Scalar reference implementations (not measured).
 *
 * Built on their own for the scalar ISA at -O1 with neither
 * vectorization nor loop-to-library-call conversion (Makefile), so the
 * reference never runs vector code or the code under test. main.c
 * checks each reference's output against a KAT computed on the host by
 * an independent model (kernels_model.py -> kernels_kat.h), then
 * compares the C and RVV outputs with the reference bit for bit.
 *
 * Every floating-point input is k/16 with 1 <= |k| <= 127, so every
 * product and partial sum in these kernels is exactly representable
 * (in binary32 too): the results do not depend on evaluation order or
 * fusion, and the vector reductions must match exactly. */
#include "kernels.h"

void vadd_i32_ref(int32_t *c, const int32_t *a, const int32_t *b, size_t n) {
  for (size_t i = 0; i < n; i++) c[i] = (int32_t)((uint32_t)a[i] + (uint32_t)b[i]);
}

void vadd_i64_ref(int64_t *c, const int64_t *a, const int64_t *b, size_t n) {
  for (size_t i = 0; i < n; i++) c[i] = (int64_t)((uint64_t)a[i] + (uint64_t)b[i]);
}

void daxpy_ref(size_t n, double a, const double *x, double *y) {
  for (size_t i = 0; i < n; i++) {
    double p = a * x[i];
    y[i] = y[i] + p;
  }
}

void saxpy_ref(size_t n, float a, const float *x, float *y) {
  for (size_t i = 0; i < n; i++) {
    float p = a * x[i];
    y[i] = y[i] + p;
  }
}

double ddot_ref(size_t n, const double *x, const double *y) {
  double s = 0.0;
  for (size_t i = 0; i < n; i++) {
    double p = x[i] * y[i];
    s = s + p;
  }
  return s;
}

uint64_t idot_ref(size_t n, const int32_t *x, const int32_t *y) {
  uint64_t s = 0;
  for (size_t i = 0; i < n; i++) s += (uint64_t)((int64_t)x[i] * (int64_t)y[i]);
  return s;
}

void memcpy_ref(void *d, const void *s, size_t n) {
  uint8_t *dp = d;
  const uint8_t *sp = s;
  for (size_t i = 0; i < n; i++) dp[i] = sp[i];
}

void memset_ref(void *d, int c, size_t n) {
  uint8_t *dp = d;
  for (size_t i = 0; i < n; i++) dp[i] = (uint8_t)c;
}

void dgemm_ref(size_t n, const double *a, const double *b, double *c) {
  for (size_t i = 0; i < n; i++)
    for (size_t j = 0; j < n; j++) {
      double s = 0.0;
      for (size_t k = 0; k < n; k++) {
        double p = a[i * n + k] * b[k * n + j];
        s = s + p;
      }
      c[i * n + j] = s;
    }
}

void sgemm_ref(size_t n, const float *a, const float *b, float *c) {
  for (size_t i = 0; i < n; i++)
    for (size_t j = 0; j < n; j++) {
      float s = 0.0f;
      for (size_t k = 0; k < n; k++) {
        float p = a[i * n + k] * b[k * n + j];
        s = s + p;
      }
      c[i * n + j] = s;
    }
}

void fir_f32_ref(size_t n, size_t taps, const float *h, const float *x, float *y) {
  for (size_t i = 0; i < n; i++) {
    float s = 0.0f;
    for (size_t k = 0; k < taps; k++) {
      float p = h[k] * x[i + k];
      s = s + p;
    }
    y[i] = s;
  }
}

uint32_t mac_i8_ref(size_t n, const int8_t *x, const int8_t *y) {
  uint32_t s = 0;
  for (size_t i = 0; i < n; i++) s += (uint32_t)((int32_t)x[i] * (int32_t)y[i]);
  return s;
}

uint32_t mac_i16_ref(size_t n, const int16_t *x, const int16_t *y) {
  uint32_t s = 0;
  for (size_t i = 0; i < n; i++) s += (uint32_t)((int32_t)x[i] * (int32_t)y[i]);
  return s;
}
