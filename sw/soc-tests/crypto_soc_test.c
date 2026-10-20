/* On-core SoC + crypto proof (issue #4): runs on the
 * in-house core inside sigil_soc_top, drives the
 * sigil_crypto accelerator over MMIO at 0x2000_0000, and
 * reports over the RTL 16550 UART at 0x1000_0000.
 *
 * Checks, in order (stage number in FAIL lines):
 *   1  SHA-256("abc") via accelerator vs known digest
 *   2  field mul mixed vector mod secp256k1 p (crypto TB)
 *   3  2*G (Jacobian, field ops on accelerator) vs known
 *   4  secp256k1 ECDSA verify of the sw/ec_ops.py frozen
 *      vector (privkey 1, msg "museRISC"); z is hashed
 *      by the accelerator
 *   5  the same verify with tampered z (bit 0 flipped)
 *      must reject
 * Reference (non-constant-time) code; vectors mirror
 * sw/ec_ops.py and tb/cpp/crypto_top_tb.cpp. Ed25519
 * verify is the sibling test ed25519_soc_test.c; both
 * share the driver in soc_crypto_drv.h. */
#include "soc_crypto_drv.h"

/* ---- SHA-256 single block via accelerator (len < 56) ---- */
static void sha256(const uint8_t *msg, uint32_t len, fe_t *digest) {
  uint32_t block[16] = {0};
  for (uint32_t i = 0; i < len; i++) {
    block[i >> 2] |= (uint32_t)msg[i] << (24 - 8 * (i & 3));
  }
  block[len >> 2] |= 0x80u << (24 - 8 * (len & 3));
  block[15] = len * 8u;
  for (int i = 0; i < 16; i++) {
    CRYPTO[(0x08u + 4u * (uint32_t)i) / 4u] = block[i];
  }
  CRYPTO[0] = 1u | (SIGIL_ENG_SHA256 << 4);
  crypto_wait_done();
  crypto_read_fe(digest);
}

/* ---- secp256k1 constants (limbs, little-endian) ---- */
static const fe_t kPminus2 = {{0xfffffffefffffc2dULL, 0xffffffffffffffffULL,
                               0xffffffffffffffffULL, 0xffffffffffffffffULL}};
static const fe_t kN = {{0xbfd25e8cd0364141ULL, 0xbaaedce6af48a03bULL,
                         0xfffffffffffffffeULL, 0xffffffffffffffffULL}};
static const fe_t kNminus2 = {{0xbfd25e8cd036413fULL, 0xbaaedce6af48a03bULL,
                               0xfffffffffffffffeULL, 0xffffffffffffffffULL}};
static const fe_t kGx = {{0x59f2815b16f81798ULL, 0x029bfcdb2dce28d9ULL,
                          0x55a06295ce870b07ULL, 0x79be667ef9dcbbacULL}};
static const fe_t kGy = {{0x9c47d08ffb10d4b8ULL, 0xfd17b448a6855419ULL,
                          0x5da4fbfc0e1108a8ULL, 0x483ada7726a3c465ULL}};
static const fe_t k2Gx = {{0xabac09b95c709ee5ULL, 0x5c778e4b8cef3ca7ULL,
                           0x3045406e95c07cd8ULL, 0xc6047f9441ed7d6dULL}};
static const fe_t k2Gy = {{0x236431a950cfe52aULL, 0xf7f632653266d0e1ULL,
                           0xa3c58419466ceaeeULL, 0x1ae168fea63dc339ULL}};
static const fe_t kSigR = {{0xc59a4cb65a1f72a7ULL, 0x9f95ef15de91651cULL,
                            0xd027a67dbc54c56eULL, 0x9d9f248547cf1efdULL}};
static const fe_t kSigS = {{0xb6debfc1634fa509ULL, 0x6b82031cc6a97e85ULL,
                            0xfd8821eb4fb1d92eULL, 0x33c5aedbec0309c3ULL}};
static const fe_t kZ = {{0x899ac63792237e53ULL, 0x534ea513339c1153ULL,
                         0xc0577d485522a783ULL, 0x0b33bc7ac81a519fULL}};
static const fe_t kShaAbc = {{0xb410ff61f20015adULL, 0xb00361a396177a9cULL,
                              0x414140de5dae2223ULL, 0xba7816bf8f01cfeaULL}};

/* Jacobian point (X, Y, Z); affine (X/Z^2, Y/Z^3), Z=0 inf. */
typedef struct {
  fe_t x, y, z;
} pt_t;

static void pt_double(const pt_t *p, pt_t *r) {
  if (fe_is_zero(&p->z) || fe_is_zero(&p->y)) {
    fe_set_u64(&r->x, 1);
    fe_set_u64(&r->y, 1);
    fe_set_u64(&r->z, 0);
    return;
  }
  fe_t y2, s, m, x3, y3, z3, tmp;
  fe_sqr(&p->y, &y2);                       /* Y^2 */
  fe_mul(&p->x, &y2, &s);
  fe_mul_small(&s, 4, &s);                  /* S = 4XY^2 */
  fe_sqr(&p->x, &m);
  fe_mul_small(&m, 3, &m);                  /* M = 3X^2 (a=0) */
  fe_sqr(&m, &x3);
  fe_add(&s, &s, &tmp);
  fe_sub(&x3, &tmp, &x3);                   /* X' = M^2-2S */
  fe_sub(&s, &x3, &y3);
  fe_mul(&m, &y3, &y3);
  fe_sqr(&y2, &tmp);
  fe_mul_small(&tmp, 8, &tmp);
  fe_sub(&y3, &tmp, &y3);                   /* Y' = M(S-X')-8Y^4 */
  fe_mul(&p->y, &p->z, &z3);
  fe_add(&z3, &z3, &z3);                    /* Z' = 2YZ */
  r->x = x3;
  r->y = y3;
  r->z = z3;
}

static void pt_add(const pt_t *p, const pt_t *q, pt_t *r) {
  if (fe_is_zero(&p->z)) {
    *r = *q;
    return;
  }
  if (fe_is_zero(&q->z)) {
    *r = *p;
    return;
  }
  fe_t z1z1, z2z2, u1, u2, s1, s2, h, rr, h2, h3, x3, y3, z3, tmp;
  fe_sqr(&p->z, &z1z1);
  fe_sqr(&q->z, &z2z2);
  fe_mul(&p->x, &z2z2, &u1);
  fe_mul(&q->x, &z1z1, &u2);
  fe_mul(&q->z, &z2z2, &tmp);
  fe_mul(&p->y, &tmp, &s1);
  fe_mul(&p->z, &z1z1, &tmp);
  fe_mul(&q->y, &tmp, &s2);
  if (fe_eq(&u1, &u2)) {
    if (!fe_eq(&s1, &s2)) {
      fe_set_u64(&r->x, 1);
      fe_set_u64(&r->y, 1);
      fe_set_u64(&r->z, 0);
      return;
    }
    pt_double(p, r);
    return;
  }
  fe_sub(&u2, &u1, &h);
  fe_sub(&s2, &s1, &rr);
  fe_sqr(&h, &h2);
  fe_mul(&h, &h2, &h3);
  fe_sqr(&rr, &x3);
  fe_sub(&x3, &h3, &x3);
  fe_mul(&u1, &h2, &tmp);
  fe_add(&tmp, &tmp, &tmp);
  fe_sub(&x3, &tmp, &x3);                   /* X3=r^2-H^3-2U1H^2 */
  fe_mul(&u1, &h2, &y3);
  fe_sub(&y3, &x3, &y3);
  fe_mul(&rr, &y3, &y3);
  fe_mul(&s1, &h3, &tmp);
  fe_sub(&y3, &tmp, &y3);                   /* Y3=r(U1H^2-X3)-S1H^3 */
  fe_mul(&h, &p->z, &z3);
  fe_mul(&z3, &q->z, &z3);
  r->x = x3;
  r->y = y3;
  r->z = z3;
}

static void pt_mul(const fe_t *k, const pt_t *p, pt_t *r) {
  pt_t result, addend = *p;
  fe_set_u64(&result.x, 1);
  fe_set_u64(&result.y, 1);
  fe_set_u64(&result.z, 0);
  for (int i = 0; i < 256; i++) {
    if ((i & 31) == 0) putc('.');
    if (bn_bit(k, i)) pt_add(&result, &addend, &result);
    pt_double(&addend, &addend);
  }
  putc('\n');
  *r = result;
}

static void pt_to_affine(const pt_t *p, fe_t *x, fe_t *y) {
  fe_t zi, zi2, zi3;
  fe_pow(&p->z, &kPminus2, &zi);
  fe_sqr(&zi, &zi2);
  fe_mul(&zi2, &zi, &zi3);
  fe_mul(&p->x, &zi2, x);
  fe_mul(&p->y, &zi3, y);
}

/* ---- scalar arithmetic mod n in software (fe_t limbs) ---- */
static int bn_cmp(const fe_t *a, const fe_t *b) {
  for (int i = 3; i >= 0; i--) {
    if (a->v[i] != b->v[i]) return a->v[i] > b->v[i] ? 1 : -1;
  }
  return 0;
}
static inline void bn_sub(const fe_t *a, const fe_t *b, fe_t *r) {
  fe_t out;
  uint64_t bw = 0;
  for (int i = 0; i < 4; i++) {
    uint64_t t = a->v[i] - b->v[i];
    uint64_t b1 = (t > a->v[i]) ? 1 : 0;
    out.v[i] = t - bw;
    bw = b1 | ((out.v[i] > t) ? 1u : 0u);
  }
  *r = out;
}
static inline void bn_addmod(const fe_t *a, const fe_t *b, fe_t *r) {
  fe_t out;
  uint64_t carry = 0;
  for (int i = 0; i < 4; i++) {
    uint64_t t = a->v[i] + b->v[i];
    uint64_t c1 = (t < a->v[i]) ? 1 : 0;
    out.v[i] = t + carry;
    carry = c1 | ((out.v[i] < t) ? 1u : 0u);
  }
  if (carry || bn_cmp(&out, &kN) >= 0) bn_sub(&out, &kN, &out);
  *r = out;
}
static void bn_mulmod(const fe_t *a, const fe_t *b, fe_t *r) {
  fe_t result;
  fe_set_u64(&result, 0);
  for (int i = 255; i >= 0; i--) {
    bn_addmod(&result, &result, &result);
    if (bn_bit(b, i)) bn_addmod(&result, a, &result);
  }
  *r = result;
}
static void bn_powmod(const fe_t *a, const fe_t *e, fe_t *r) {
  fe_t result, base = *a;
  fe_set_u64(&result, 1);
  for (int i = 255; i >= 0; i--) {
    bn_mulmod(&result, &result, &result);
    if (bn_bit(e, i)) bn_mulmod(&result, &base, &result);
  }
  *r = result;
}

int main(void) {
  puts("SOC CRYPTO START\r\n");
  fe_t got, want;
  /* Stage 1: SHA-256("abc"). */
  sha256((const uint8_t *)"abc", 3, &got);
  if (!fe_eq(&got, &kShaAbc)) fail(1);
  puts("stage1 sha256 ok\r\n");

  /* Stage 2: field mul mixed vector (secp, MODSEL=0). */
  CRYPTO[0x68 / 4] = 0;
  {
    fe_t a = {{0x1234567890abcdefULL, 0x1234567890abcdefULL,
               0x1234567890abcdefULL, 0x1234567890abcdefULL}};
    fe_t b = {{0xfedcba0987654321ULL, 0xfedcba0987654321ULL,
               0xfedcba0987654321ULL, 0xfedcba0987654321ULL}};
    want = (fe_t){{0x354652a4e4897181ULL, 0xc6a865e9cd771060ULL,
                   0x6a2a19b97d502825ULL, 0x0dabcd892d293febULL}};
    fe_mul(&a, &b, &got);
    if (!fe_eq(&got, &want)) fail(2);
  }
  puts("stage2 field mul ok\r\n");

  /* Stage 3: 2*G in Jacobian, affine compare. */
  pt_t g, g2, acc;
  g.x = kGx;
  g.y = kGy;
  fe_set_u64(&g.z, 1);
  pt_double(&g, &g2);
  fe_t ax, ay;
  pt_to_affine(&g2, &ax, &ay);
  if (!fe_eq(&ax, &k2Gx) || !fe_eq(&ay, &k2Gy)) fail(3);
  puts("stage3 2G ok\r\n");

  /* Stage 4: ECDSA verify (z hashed by accelerator). */
  fe_t z;
  sha256((const uint8_t *)"museRISC", 8, &z);
  if (!fe_eq(&z, &kZ)) fail(4);
  fe_t w, u1, u2;
  /* Scalar inversion on the accelerator too: MODSEL=2
   * with MOD = group order n, then restore secp p. */
  crypto_write_fe(0x6c, &kN);
  CRYPTO[0x68 / 4] = 2;
  fe_pow(&kSigS, &kNminus2, &w);
  fe_mul(&z, &w, &u1);
  fe_mul(&kSigR, &w, &u2);
  CRYPTO[0x68 / 4] = 0;
  puts("stage4a scalar inv ok\r\n");
  pt_t p1, p2;
  pt_mul(&u1, &g, &p1);
  puts("stage4b u1*G ok\r\n");
  pt_mul(&u2, &g, &p2); /* Q = G for privkey 1 */
  puts("stage4c u2*Q ok\r\n");
  pt_add(&p1, &p2, &acc);
  if (fe_is_zero(&acc.z)) fail(4);
  pt_to_affine(&acc, &ax, &ay);
  if (bn_cmp(&ax, &kN) >= 0) bn_sub(&ax, &kN, &ax);
  if (!fe_eq(&ax, &kSigR)) fail(4);
  puts("stage4 ECDSA verify ok\r\n");

  /* Stage 5: tampered z (low bit flipped) must reject.
   * Only u1 depends on z, so u2*Q from stage 4 is reused;
   * MOD regs still hold n. */
  fe_t zt = z;
  zt.v[0] ^= 1;
  CRYPTO[0x68 / 4] = 2;
  fe_mul(&zt, &w, &u1);
  CRYPTO[0x68 / 4] = 0;
  pt_mul(&u1, &g, &p1);
  pt_add(&p1, &p2, &acc);
  if (!fe_is_zero(&acc.z)) {
    pt_to_affine(&acc, &ax, &ay);
    if (bn_cmp(&ax, &kN) >= 0) bn_sub(&ax, &kN, &ax);
    if (fe_eq(&ax, &kSigR)) fail(5);
  }
  puts("stage5 ECDSA tamper rejected\r\n");
  puts("SOC CRYPTO PASS\r\n");
  for (;;) __asm__ volatile("wfi");
  return 0;
}
