/* RVV multi-buffer SHA-256: 16 independent messages, one per 32-bit
 * lane (e32, LMUL 1: 16 lanes at VLEN 512), with the RVV 1.0 C
 * intrinsics.
 *
 * Every vector register holds one SHA-256 variable for all lanes: the
 * eight working variables a..h and a rolling 16-word message schedule
 * w0..w15, 24 registers, plus a few temporaries. The rounds are
 * unrolled 16 at a time (so the schedule window has fixed register
 * names) and looped 4 times. The core has no vector rotate (Zvbb) or
 * vector SHA-2 (Zvknh), so every rotate is vsrl + vsll + vxor:
 *   Sigma0/Sigma1  6 shifts + 5 xors      sigma0/sigma1  5 shifts + 4 xors
 *   Ch             3 ops                  Maj            4 ops
 * about 36 vector ops per round plus 21 per schedule word: 3,3xx per
 * 64-byte block per lane group. The vector unit is element-serial
 * (docs/CORE.md: an e32 m1 ALU op at vl 16 takes 20 cycles), so this
 * is a throughput kernel for many independent messages, not a latency
 * kernel for one.
 *
 * Message loads (sha256x16_blocks): two strided segment loads
 * (vlsseg8e32, stride = lane stride) bring words 0..7 and 8..15 of each
 * lane's block into w0..w15, and a byte gather (vrgather.vv on e8,
 * index i ^ 3) turns each big-endian word into a native one. */
#include <riscv_vector.h>

#include "sigil.h"
#include "sha256_bench.h"

typedef vuint32m1_t V;

#define VADD(a, b) __riscv_vadd_vv_u32m1((a), (b), vl)
#define VADDX(a, x) __riscv_vadd_vx_u32m1((a), (x), vl)
#define VXOR(a, b) __riscv_vxor_vv_u32m1((a), (b), vl)
#define VAND(a, b) __riscv_vand_vv_u32m1((a), (b), vl)
#define VOR(a, b) __riscv_vor_vv_u32m1((a), (b), vl)
#define VSRL(a, n) __riscv_vsrl_vx_u32m1((a), (n), vl)
#define VSLL(a, n) __riscv_vsll_vx_u32m1((a), (n), vl)
#define VSPLAT(x) __riscv_vmv_v_x_u32m1((x), vl)

/* ror(x, p) ^ ror(x, q) ^ ror(x, r) */
static inline __attribute__((always_inline)) V rot3(V x, unsigned p, unsigned q,
                                                    unsigned r, size_t vl) {
  V y = VXOR(VSRL(x, p), VSLL(x, 32 - p));
  y = VXOR(y, VSRL(x, q));
  y = VXOR(y, VSLL(x, 32 - q));
  y = VXOR(y, VSRL(x, r));
  return VXOR(y, VSLL(x, 32 - r));
}
/* ror(x, p) ^ ror(x, q) ^ (x >> r) */
static inline __attribute__((always_inline)) V rot2shr(V x, unsigned p, unsigned q,
                                                       unsigned r, size_t vl) {
  V y = VXOR(VSRL(x, p), VSLL(x, 32 - p));
  y = VXOR(y, VSRL(x, q));
  y = VXOR(y, VSLL(x, 32 - q));
  return VXOR(y, VSRL(x, r));
}
#define BSIG0(x) rot3((x), 2, 13, 22, vl)
#define BSIG1(x) rot3((x), 6, 11, 25, vl)
#define SSIG0(x) rot2shr((x), 7, 18, 3, vl)
#define SSIG1(x) rot2shr((x), 17, 19, 10, vl)
#define CH(e, f, g) VXOR((g), VAND((e), VXOR((f), (g))))
#define MAJ(a, b, c) VOR(VAND((a), (b)), VAND((c), VOR((a), (b))))

/* One round; the caller rotates the variable names. */
#define RND(a, b, c, d, e, f, g, h, k, w)                                   \
  do {                                                                      \
    V t1_ = VADD(VADD(VADDX(VADD((h), (w)), (k)), BSIG1(e)), CH(e, f, g)); \
    (d) = VADD((d), t1_);                                                   \
    (h) = VADD(VADD(t1_, BSIG0(a)), MAJ(a, b, c));                          \
  } while (0)

/* W[i] = sigma1(W[i-2]) + W[i-7] + sigma0(W[i-15]) + W[i-16], in place
 * in the 16-word window (slot i mod 16). */
#define SCHED(w0, w1, w9, w14) (w0) = VADD(VADD((w0), SSIG0(w1)), VADD((w9), SSIG1(w14)))

#define ROUNDS16(kp)                         \
  RND(a, b, c, d, e, f, g, h, (kp)[0], w0);  \
  RND(h, a, b, c, d, e, f, g, (kp)[1], w1);  \
  RND(g, h, a, b, c, d, e, f, (kp)[2], w2);  \
  RND(f, g, h, a, b, c, d, e, (kp)[3], w3);  \
  RND(e, f, g, h, a, b, c, d, (kp)[4], w4);  \
  RND(d, e, f, g, h, a, b, c, (kp)[5], w5);  \
  RND(c, d, e, f, g, h, a, b, (kp)[6], w6);  \
  RND(b, c, d, e, f, g, h, a, (kp)[7], w7);  \
  RND(a, b, c, d, e, f, g, h, (kp)[8], w8);  \
  RND(h, a, b, c, d, e, f, g, (kp)[9], w9);  \
  RND(g, h, a, b, c, d, e, f, (kp)[10], w10); \
  RND(f, g, h, a, b, c, d, e, (kp)[11], w11); \
  RND(e, f, g, h, a, b, c, d, (kp)[12], w12); \
  RND(d, e, f, g, h, a, b, c, (kp)[13], w13); \
  RND(c, d, e, f, g, h, a, b, (kp)[14], w14); \
  RND(b, c, d, e, f, g, h, a, (kp)[15], w15)

#define SCHED16                    \
  SCHED(w0, w1, w9, w14);          \
  SCHED(w1, w2, w10, w15);         \
  SCHED(w2, w3, w11, w0);          \
  SCHED(w3, w4, w12, w1);          \
  SCHED(w4, w5, w13, w2);          \
  SCHED(w5, w6, w14, w3);          \
  SCHED(w6, w7, w15, w4);          \
  SCHED(w7, w8, w0, w5);           \
  SCHED(w8, w9, w1, w6);           \
  SCHED(w9, w10, w2, w7);          \
  SCHED(w10, w11, w3, w8);         \
  SCHED(w11, w12, w4, w9);         \
  SCHED(w12, w13, w5, w10);        \
  SCHED(w13, w14, w6, w11);        \
  SCHED(w14, w15, w7, w12);        \
  SCHED(w15, w0, w8, w13)

/* The 64 rounds on a..h with the message in w0..w15. */
#define COMPRESS64                                                    \
  for (const uint32_t *kp = sha256_K; kp < sha256_K + 64; kp += 16) { \
    if (kp != sha256_K) {                                             \
      SCHED16;                                                        \
    }                                                                 \
    ROUNDS16(kp);                                                     \
  }

void sha256x16_init(sha256x16_t st) {
  for (int k = 0; k < 8; k++) {
    for (int j = 0; j < SHA256_LANES; j++) st[k][j] = sha256_IV[k];
  }
}

void sha256x16_lane(const sha256x16_t st, unsigned lane, uint32_t h[8]) {
  for (int k = 0; k < 8; k++) h[k] = st[k][lane];
}

void sha256x16_set_lane(sha256x16_t st, unsigned lane, const uint32_t h[8]) {
  for (int k = 0; k < 8; k++) st[k][lane] = h[k];
}

__attribute__((noinline)) void sha256x16_chain(sha256x16_t st, size_t steps,
                                               size_t avl) {
  size_t vl = __riscv_vsetvl_e32m1(avl);
  V h0 = __riscv_vle32_v_u32m1(st[0], vl), h1 = __riscv_vle32_v_u32m1(st[1], vl);
  V h2 = __riscv_vle32_v_u32m1(st[2], vl), h3 = __riscv_vle32_v_u32m1(st[3], vl);
  V h4 = __riscv_vle32_v_u32m1(st[4], vl), h5 = __riscv_vle32_v_u32m1(st[5], vl);
  V h6 = __riscv_vle32_v_u32m1(st[6], vl), h7 = __riscv_vle32_v_u32m1(st[7], vl);
  for (; steps > 0; steps--) {
    /* Message = previous digest + one-block padding for 32 bytes. */
    V w0 = h0, w1 = h1, w2 = h2, w3 = h3, w4 = h4, w5 = h5, w6 = h6, w7 = h7;
    V w8 = VSPLAT(0x80000000u), w9 = VSPLAT(0), w10 = VSPLAT(0), w11 = VSPLAT(0);
    V w12 = VSPLAT(0), w13 = VSPLAT(0), w14 = VSPLAT(0), w15 = VSPLAT(256);
    V a = VSPLAT(sha256_IV[0]), b = VSPLAT(sha256_IV[1]);
    V c = VSPLAT(sha256_IV[2]), d = VSPLAT(sha256_IV[3]);
    V e = VSPLAT(sha256_IV[4]), f = VSPLAT(sha256_IV[5]);
    V g = VSPLAT(sha256_IV[6]), h = VSPLAT(sha256_IV[7]);
    COMPRESS64
    h0 = VADDX(a, sha256_IV[0]);
    h1 = VADDX(b, sha256_IV[1]);
    h2 = VADDX(c, sha256_IV[2]);
    h3 = VADDX(d, sha256_IV[3]);
    h4 = VADDX(e, sha256_IV[4]);
    h5 = VADDX(f, sha256_IV[5]);
    h6 = VADDX(g, sha256_IV[6]);
    h7 = VADDX(h, sha256_IV[7]);
  }
  __riscv_vse32_v_u32m1(st[0], h0, vl);
  __riscv_vse32_v_u32m1(st[1], h1, vl);
  __riscv_vse32_v_u32m1(st[2], h2, vl);
  __riscv_vse32_v_u32m1(st[3], h3, vl);
  __riscv_vse32_v_u32m1(st[4], h4, vl);
  __riscv_vse32_v_u32m1(st[5], h5, vl);
  __riscv_vse32_v_u32m1(st[6], h6, vl);
  __riscv_vse32_v_u32m1(st[7], h7, vl);
}

/* Big-endian 32-bit words -> native: gather bytes i ^ 3 (e8, 4 vl). */
static inline __attribute__((always_inline)) V bswap32v(V x, size_t vl) {
  size_t vb = 4 * vl;
  vuint8m1_t idx = __riscv_vxor_vx_u8m1(__riscv_vid_v_u8m1(vb), 3, vb);
  return __riscv_vreinterpret_v_u8m1_u32m1(
      __riscv_vrgather_vv_u8m1(__riscv_vreinterpret_v_u32m1_u8m1(x), idx, vb));
}

__attribute__((noinline)) void sha256x16_blocks(sha256x16_t st, const uint8_t *base,
                                                size_t lane_stride, size_t nblocks,
                                                size_t avl) {
  size_t vl = __riscv_vsetvl_e32m1(avl);
  for (; nblocks > 0; nblocks--, base += 64) {
    vuint32m1x8_t lo = __riscv_vlsseg8e32_v_u32m1x8((const uint32_t *)base,
                                                    (ptrdiff_t)lane_stride, vl);
    V w0 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 0), vl);
    V w1 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 1), vl);
    V w2 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 2), vl);
    V w3 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 3), vl);
    V w4 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 4), vl);
    V w5 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 5), vl);
    V w6 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 6), vl);
    V w7 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(lo, 7), vl);
    /* Finish words 0..7 before the second segment load: otherwise GCC
     * issues both loads first and spills a register group. */
    __asm__ volatile(""
                     : "+vr"(w0), "+vr"(w1), "+vr"(w2), "+vr"(w3), "+vr"(w4),
                       "+vr"(w5), "+vr"(w6), "+vr"(w7)
                     :
                     : "memory");
    vuint32m1x8_t hi = __riscv_vlsseg8e32_v_u32m1x8((const uint32_t *)(base + 32),
                                                    (ptrdiff_t)lane_stride, vl);
    V w8 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 0), vl);
    V w9 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 1), vl);
    V w10 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 2), vl);
    V w11 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 3), vl);
    V w12 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 4), vl);
    V w13 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 5), vl);
    V w14 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 6), vl);
    V w15 = bswap32v(__riscv_vget_v_u32m1x8_u32m1(hi, 7), vl);
    /* a..h + the schedule fill all registers: the chaining state stays
     * in memory and is added back after the rounds. */
    V a = __riscv_vle32_v_u32m1(st[0], vl), b = __riscv_vle32_v_u32m1(st[1], vl);
    V c = __riscv_vle32_v_u32m1(st[2], vl), d = __riscv_vle32_v_u32m1(st[3], vl);
    V e = __riscv_vle32_v_u32m1(st[4], vl), f = __riscv_vle32_v_u32m1(st[5], vl);
    V g = __riscv_vle32_v_u32m1(st[6], vl), h = __riscv_vle32_v_u32m1(st[7], vl);
    COMPRESS64
    __riscv_vse32_v_u32m1(st[0], VADD(a, __riscv_vle32_v_u32m1(st[0], vl)), vl);
    __riscv_vse32_v_u32m1(st[1], VADD(b, __riscv_vle32_v_u32m1(st[1], vl)), vl);
    __riscv_vse32_v_u32m1(st[2], VADD(c, __riscv_vle32_v_u32m1(st[2], vl)), vl);
    __riscv_vse32_v_u32m1(st[3], VADD(d, __riscv_vle32_v_u32m1(st[3], vl)), vl);
    __riscv_vse32_v_u32m1(st[4], VADD(e, __riscv_vle32_v_u32m1(st[4], vl)), vl);
    __riscv_vse32_v_u32m1(st[5], VADD(f, __riscv_vle32_v_u32m1(st[5], vl)), vl);
    __riscv_vse32_v_u32m1(st[6], VADD(g, __riscv_vle32_v_u32m1(st[6], vl)), vl);
    __riscv_vse32_v_u32m1(st[7], VADD(h, __riscv_vle32_v_u32m1(st[7], vl)), vl);
  }
}
