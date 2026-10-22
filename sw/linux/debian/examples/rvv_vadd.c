/* User-space vector on Sigil: Zve64d (VLEN 512), not full V. Build
 * with -march=rv64gc_zve64d. Asks the kernel (riscv_hwprobe) whether
 * Zve64d is there, then runs a strip-mined daxpy and an int64 sum
 * with the RVV intrinsics and checks them against scalar code. */
#include <asm/hwprobe.h>
#include <riscv_vector.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

#define N 10007

static double x[N], y[N], yref[N];
static int64_t v[N];

int main(void) {
  struct riscv_hwprobe p = {.key = RISCV_HWPROBE_KEY_IMA_EXT_0};
  if (syscall(__NR_riscv_hwprobe, &p, 1, 0, NULL, 0) != 0) {
    perror("riscv_hwprobe");
    return 1;
  }
  printf("hwprobe: zve32x %d zve64x %d zve64d %d full-v %d\n",
         !!(p.value & RISCV_HWPROBE_EXT_ZVE32X), !!(p.value & RISCV_HWPROBE_EXT_ZVE64X),
         !!(p.value & RISCV_HWPROBE_EXT_ZVE64D), !!(p.value & RISCV_HWPROBE_IMA_V));
  printf("VLEN = %zu bits\n", __riscv_vsetvlmax_e8m1() * 8);

  for (int i = 0; i < N; i++) {
    x[i] = i * 0.5; y[i] = yref[i] = 1000.0 - i; v[i] = (int64_t)i * i - 77;
  }
  const double a = 3.25;
  for (int i = 0; i < N; i++) yref[i] += a * x[i];

  for (size_t i = 0, vl; i < N; i += vl) {          /* y += a * x */
    vl = __riscv_vsetvl_e64m8(N - i);
    vfloat64m8_t vx = __riscv_vle64_v_f64m8(&x[i], vl);
    vfloat64m8_t vy = __riscv_vle64_v_f64m8(&y[i], vl);
    __riscv_vse64_v_f64m8(&y[i], __riscv_vfmacc_vf_f64m8(vy, a, vx, vl), vl);
  }
  int bad = 0;
  for (int i = 0; i < N; i++) bad += y[i] != yref[i];

  int64_t sref = 0;
  for (int i = 0; i < N; i++) sref += v[i];
  vint64m1_t acc = __riscv_vmv_s_x_i64m1(0, 1);
  for (size_t i = 0, vl; i < N; i += vl) {          /* sum of int64 */
    vl = __riscv_vsetvl_e64m8(N - i);
    acc = __riscv_vredsum_vs_i64m8_i64m1(__riscv_vle64_v_i64m8(&v[i], vl), acc, vl);
  }
  int64_t s = __riscv_vmv_x_s_i64m1_i64(acc);

  printf("daxpy %d elements: %d mismatches; int64 sum %lld (scalar %lld)\n", N,
         bad, (long long)s, (long long)sref);
  if (bad || s != sref) { printf("RVV FAIL\n"); return 1; }
  printf("RVV OK\n");
  return 0;
}
