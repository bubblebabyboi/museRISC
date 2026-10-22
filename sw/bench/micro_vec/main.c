/* micro_vec: vsetvli cost and element-serial vector throughput versus
 * VL, in cycles per vector instruction (../micro_common/README.md).
 * Kernels: kernels.S. Region labels match bench.json.
 *
 * Built without V (micro.mk), so the C code between the kernel calls
 * never touches vector state: a region's operands are loaded by a
 * setup kernel before the window and its result is stored by another
 * after it, then checked against C. */
#include "micro.h"

#define U 32 /* vector instructions per loop trip, kernels.S */
#define VLMAX_E8M8 512

uint64_t k_empty(void);
uint64_t k_vsetvli_same(uint64_t trips, uint64_t avl);
uint64_t k_vsetvli_toggle(uint64_t trips, uint64_t avl);
uint64_t k_vset_e8m8(uint64_t vl);
uint64_t k_vinit_e8(uint64_t vl, const void *a, const void *b);
uint64_t k_vinit_e64(uint64_t vl, const void *a, const void *b);
uint64_t k_vstore_e8(uint64_t vl, void *dst);
uint64_t k_vstore_e64(uint64_t vl, void *dst);
uint64_t k_vadd(uint64_t trips);
uint64_t k_vmul(uint64_t trips);
uint64_t k_vfadd(uint64_t trips);
uint64_t k_vredsum(uint64_t trips);
uint64_t k_vle8(uint64_t trips, const void *src);
uint64_t k_vse8(uint64_t trips, void *dst);

static uint8_t a8[VLMAX_E8M8] __attribute__((aligned(64)));
static uint8_t b8[VLMAX_E8M8] __attribute__((aligned(64)));
static uint8_t out8[VLMAX_E8M8] __attribute__((aligned(64)));
static uint64_t a64[8] __attribute__((aligned(64)));
static uint64_t b64[8] __attribute__((aligned(64)));
static uint64_t out64[8] __attribute__((aligned(64)));

static const uint32_t vls[] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512};
static const char *const vadd_labels[] = {
    "vadd_e8_vl1",  "vadd_e8_vl2",  "vadd_e8_vl4",   "vadd_e8_vl8",   "vadd_e8_vl16",
    "vadd_e8_vl32", "vadd_e8_vl64", "vadd_e8_vl128", "vadd_e8_vl256", "vadd_e8_vl512"};
static const char *const vle_labels[] = {
    "vle8_vl1",  "vle8_vl2",  "vle8_vl4",   "vle8_vl8",   "vle8_vl16",
    "vle8_vl32", "vle8_vl64", "vle8_vl128", "vle8_vl256", "vle8_vl512"};
static const uint32_t vse_vls[] = {1, 8, 64, 512};
static const char *const vse_labels[] = {"vse8_vl1", "vse8_vl8", "vse8_vl64", "vse8_vl512"};

static uint64_t dbits(double d) {
  uint64_t u;
  __builtin_memcpy(&u, &d, sizeof u);
  return u;
}

static void check_bytes(const char *label, const uint8_t *got, const uint8_t *want,
                        uint32_t n) {
  uint64_t bad = 0;
  for (uint32_t i = 0; i < n; i++) bad += got[i] != want[i];
  micro_check(label, "mismatching elements", bad, 0);
}

int main(void) {
  const uint64_t trips = micro_trips(U), ops = trips * U;
  unsigned id = 1;
  uint64_t r;
  static uint8_t want8[VLMAX_E8M8];

  for (uint32_t i = 0; i < VLMAX_E8M8; i++) {
    a8[i] = (uint8_t)micro_rand();
    b8[i] = (uint8_t)(micro_rand() | 1);
  }

  MICRO_REGION(id, "empty", ops, k_empty(), r = k_empty());
  micro_check("empty", "result", r, 0);
  id++;

  MICRO_REGION(id, "vsetvli_same", ops, k_vsetvli_same(1, 100), r = k_vsetvli_same(trips, 100));
  micro_check("vsetvli_same", "vl", r, 100);
  id++;
  MICRO_REGION(id, "vsetvli_toggle", ops, k_vsetvli_toggle(1, 100),
               r = k_vsetvli_toggle(trips, 100));
  micro_check("vsetvli_toggle", "vl (e32, m1)", r, 16);
  id++;

  /* vadd.vv e8 m8, v8 += v16, for every VL. */
  for (unsigned k = 0; k < 10; k++, id++) {
    const uint32_t vl = vls[k];
    MICRO_REGION(id, vadd_labels[k], ops,
                 (k_vinit_e8(vl, a8, b8), k_vadd(1), r = k_vinit_e8(vl, a8, b8)),
                 k_vadd(trips));
    micro_check(vadd_labels[k], "vl", r, vl);
    k_vstore_e8(vl, out8);
    for (uint32_t i = 0; i < vl; i++) want8[i] = (uint8_t)(a8[i] + ops * b8[i]);
    check_bytes(vadd_labels[k], out8, want8, vl);
  }

  /* vle8.v (the warm-up loads b8, the region a8). */
  for (unsigned k = 0; k < 10; k++, id++) {
    const uint32_t vl = vls[k];
    MICRO_REGION(id, vle_labels[k], ops, (r = k_vset_e8m8(vl), k_vle8(1, b8)),
                 k_vle8(trips, a8));
    micro_check(vle_labels[k], "vl", r, vl);
    k_vstore_e8(vl, out8);
    check_bytes(vle_labels[k], out8, a8, vl);
  }

  /* vse8.v of v8 = a8 (out8 is cleared after the warm-up). */
  for (unsigned k = 0; k < 4; k++, id++) {
    const uint32_t vl = vse_vls[k];
    MICRO_REGION(id, vse_labels[k], ops,
                 (r = k_vinit_e8(vl, a8, b8), k_vse8(1, out8),
                  __builtin_memset(out8, 0, sizeof out8)),
                 k_vse8(trips, out8));
    micro_check(vse_labels[k], "vl", r, vl);
    check_bytes(vse_labels[k], out8, a8, vl);
  }

  /* SEW = 64, LMUL = 1, VL = 8 (VLMAX). */
  for (int i = 0; i < 8; i++) {
    a64[i] = micro_rand();
    b64[i] = micro_rand() | 1;
  }
  {
    MICRO_REGION(id, "vadd_e64_vl8", ops,
                 (k_vinit_e64(8, a64, b64), k_vadd(1), r = k_vinit_e64(8, a64, b64)),
                 k_vadd(trips));
    micro_check("vadd_e64_vl8", "vl", r, 8);
    k_vstore_e64(8, out64);
    for (int i = 0; i < 8; i++) micro_check("vadd_e64_vl8", "element", out64[i], a64[i] + ops * b64[i]);
    id++;

    MICRO_REGION(id, "vmul_e64_vl8", ops,
                 (k_vinit_e64(8, a64, b64), k_vmul(1), k_vinit_e64(8, a64, b64)),
                 k_vmul(trips));
    k_vstore_e64(8, out64);
    for (int i = 0; i < 8; i++) {
      uint64_t w = a64[i];
      for (uint64_t j = 0; j < ops; j++) w *= b64[i];
      micro_check("vmul_e64_vl8", "element", out64[i], w);
    }
    id++;

    double fa[8], fb[8], fo[8];
    for (int i = 0; i < 8; i++) {
      fa[i] = (double)(i + 1);
      fb[i] = 1.0 / (double)(i + 3);
    }
    MICRO_REGION(id, "vfadd_e64_vl8", ops,
                 (k_vinit_e64(8, fa, fb), k_vfadd(1), k_vinit_e64(8, fa, fb)),
                 k_vfadd(trips));
    k_vstore_e64(8, fo);
    for (int i = 0; i < 8; i++) {
      double x = fa[i];
      for (uint64_t j = 0; j < ops; j++) x = x + fb[i];
      micro_check("vfadd_e64_vl8", "element", dbits(fo[i]), dbits(x));
    }
    id++;

    MICRO_REGION(id, "vredsum_e64_vl8", ops,
                 (k_vinit_e64(8, a64, b64), k_vredsum(1), k_vinit_e64(8, a64, b64)),
                 k_vredsum(trips));
    k_vstore_e64(8, out64);
    uint64_t sum = 0;
    for (int i = 0; i < 8; i++) sum += b64[i];
    micro_check("vredsum_e64_vl8", "element 0", out64[0], a64[0] + ops * sum);
    id++;
  }

  micro_finish(id - 1);
}
