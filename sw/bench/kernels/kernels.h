/* Vector and FP kernels benchmark (issue #56): shared declarations.
 *
 * Every kernel has three implementations:
 *   *_c    portable C (kern_c.c), built for the scalar ISA by default
 *          (no V: the scalar baseline), measured;
 *   *_rvv  RVV 1.0 C intrinsics (kern_rvv.c, VLEN-agnostic strip
 *          mining), measured;
 *   *_ref  the scalar reference (ref.c, scalar ISA, -O1), not measured.
 * main.c checks the reference against a host-computed KAT
 * (kernels_kat.h, kernels_model.py) and both measured outputs against
 * the reference, bit for bit.
 *
 * Sizes: every streaming array is 4 KiB, so each kernel's working set
 * fits the default 16 KiB D$ (3 arrays = 12 KiB). */
#ifndef KERNELS_H
#define KERNELS_H

#include <stddef.h>
#include <stdint.h>

#define KN_I8  4096 /* int8 elements in 4 KiB  */
#define KN_I16 2048
#define KN_32  1024 /* int32 / fp32 elements   */
#define KN_64  512  /* int64 / fp64 elements   */
#define KN_MEM 4096 /* memcpy / memset bytes   */
#define KN_GEMM 32  /* C[32][32] = A[32][32] B[32][32] */
#define KN_FIR 1024 /* FIR outputs             */
#define KN_TAPS 16  /* FIR taps                */
#define KN_AXPY_A 0.375 /* axpy scalar a       */

/* 1. c = a + b (int32), 2. (int64) */
void vadd_i32_c(int32_t *c, const int32_t *a, const int32_t *b, size_t n);
void vadd_i32_rvv(int32_t *c, const int32_t *a, const int32_t *b, size_t n);
void vadd_i32_ref(int32_t *c, const int32_t *a, const int32_t *b, size_t n);
void vadd_i64_c(int64_t *c, const int64_t *a, const int64_t *b, size_t n);
void vadd_i64_rvv(int64_t *c, const int64_t *a, const int64_t *b, size_t n);
void vadd_i64_ref(int64_t *c, const int64_t *a, const int64_t *b, size_t n);

/* 3. y = a x + y (fp64), 4. (fp32) */
void daxpy_c(size_t n, double a, const double *x, double *y);
void daxpy_rvv(size_t n, double a, const double *x, double *y);
void daxpy_ref(size_t n, double a, const double *x, double *y);
void saxpy_c(size_t n, float a, const float *x, float *y);
void saxpy_rvv(size_t n, float a, const float *x, float *y);
void saxpy_ref(size_t n, float a, const float *x, float *y);

/* 5. sum x[i] y[i] (fp64) */
double ddot_c(size_t n, const double *x, const double *y);
double ddot_rvv(size_t n, const double *x, const double *y);
double ddot_ref(size_t n, const double *x, const double *y);

/* 6. sum x[i] y[i], int32 x int32 -> int64 (wraps mod 2^64) */
uint64_t idot_c(size_t n, const int32_t *x, const int32_t *y);
uint64_t idot_rvv(size_t n, const int32_t *x, const int32_t *y);
uint64_t idot_ref(size_t n, const int32_t *x, const int32_t *y);

/* 7. memcpy, 8. memset. The C versions are the SDK's memcpy/memset
 * (8-byte words when aligned). rvv: e64 (aligned, n % 8 == 0, the
 * same contract the SDK's word path needs); rvv8: e8, the generic
 * any-alignment idiom (what GCC emits for struct copies). */
void memcpy_c(void *d, const void *s, size_t n);
void memcpy_rvv(void *d, const void *s, size_t n);
void memcpy_rvv8(void *d, const void *s, size_t n);
void memcpy_ref(void *d, const void *s, size_t n);
void memset_c(void *d, int c, size_t n);
void memset_rvv(void *d, int c, size_t n);
void memset_rvv8(void *d, int c, size_t n);
void memset_ref(void *d, int c, size_t n);

/* 9. C = A B, n x n, row-major (fp64), 10. (fp32) */
void dgemm_c(size_t n, const double *a, const double *b, double *c);
void dgemm_rvv(size_t n, const double *a, const double *b, double *c);
void dgemm_ref(size_t n, const double *a, const double *b, double *c);
void sgemm_c(size_t n, const float *a, const float *b, float *c);
void sgemm_rvv(size_t n, const float *a, const float *b, float *c);
void sgemm_ref(size_t n, const float *a, const float *b, float *c);

/* 11. y[i] = sum_k h[k] x[i+k], i < n, k < taps (fp32; x has
 * n + taps - 1 samples) */
void fir_f32_c(size_t n, size_t taps, const float *h, const float *x, float *y);
void fir_f32_rvv(size_t n, size_t taps, const float *h, const float *x, float *y);
void fir_f32_ref(size_t n, size_t taps, const float *h, const float *x, float *y);

/* 12. widening MAC: sum x[i] y[i], int8 x int8 -> int32,
 * 13. int16 x int16 -> int32 (both wrap mod 2^32) */
uint32_t mac_i8_c(size_t n, const int8_t *x, const int8_t *y);
uint32_t mac_i8_rvv(size_t n, const int8_t *x, const int8_t *y);
uint32_t mac_i8_ref(size_t n, const int8_t *x, const int8_t *y);
uint32_t mac_i16_c(size_t n, const int16_t *x, const int16_t *y);
uint32_t mac_i16_rvv(size_t n, const int16_t *x, const int16_t *y);
uint32_t mac_i16_ref(size_t n, const int16_t *x, const int16_t *y);

#endif /* KERNELS_H */
