/* On-core Ed25519 verify proof (issue #4): runs on the in-house
 * core inside sigil_soc_top, drives every Curve25519 field op
 * (add/sub/mul mod p = 2^255-19, MODSEL=1) through the sigil_crypto
 * accelerator over MMIO at 0x2000_0000, and reports over the RTL
 * 16550 UART at 0x1000_0000. Sibling of crypto_soc_test.c
 * (SHA-256 + secp256k1 ECDSA); both share soc_crypto_drv.h.
 *
 * Hash step: SHA-512 is NOT on the accelerator yet (its block is
 * standalone RTL, not wired into sigil_crypto_top). It is computed
 * here IN SOFTWARE ON THE CORE (FIPS 180-4, below), checked
 * against the SHA-512("abc") KAT first, and h = SHA-512(R||A||M)
 * is reduced mod L in software. No precomputed digests are used.
 *
 * Vectors: RFC 8032 sec. 7.1 TEST 1 and TEST 2, the same frozen
 * ones in sw/ec_ops.py.
 *
 * Checks, in order (stage number in FAIL lines):
 *   1  software SHA-512("abc") vs FIPS 180-4 digest
 *   2  Curve25519 field KATs on the accelerator: sqrt(-1)^2 = -1,
 *      d * 121666 = -121665
 *   3  verify RFC 8032 TEST 1 (empty message): accept
 *   4  verify RFC 8032 TEST 2 (message 0x72): accept
 *   5  TEST 2 with S bit 0 flipped: reject at the point compare
 *      (full verify math runs; S stays < L)
 *   6  TEST 2 with S + L (non-canonical S): reject
 *
 * Verify = RFC 8032 sec. 5.1.7 in the cofactorless form used by
 * sw/ec_ops.py / ref10: decode A, k = SHA-512(R||A||M) mod L,
 * check encode([S]B + [k](-A)) == R. Points are extended twisted
 * Edwards (X:Y:Z:T), a = -1 (add-2008-hwcd-3, dbl-2008-hwcd);
 * [S]B + [k](-A) is one joint (Shamir) double-and-add ladder.
 * Reference code: variable-time, NOT constant-time (fine for
 * public verify inputs; W2/W4 own constant-time). */
#include "soc_crypto_drv.h"

/* ---- Curve25519 / Ed25519 constants (limbs, little-endian) ---- */
static const fe_t kEdD = {{0x75eb4dca135978a3ULL, 0x00700a4d4141d8abULL,
                           0x8cc740797779e898ULL, 0x52036cee2b6ffe73ULL}};
static const fe_t kEd2D = {{0xebd69b9426b2f159ULL, 0x00e0149a8283b156ULL,
                            0x198e80f2eef3d130ULL, 0x2406d9dc56dffce7ULL}};
static const fe_t kSqrtM1 = {{0xc4ee1b274a0ea0b0ULL, 0x2f431806ad2fe478ULL,
                              0x2b4d00993dfbd7a7ULL, 0x2b8324804fc1df0bULL}};
static const fe_t kBx = {{0xc9562d608f25d51aULL, 0x692cc7609525a7b2ULL,
                          0xc0a4e231fdd6dc5cULL, 0x216936d3cd6e53feULL}};
static const fe_t kBy = {{0x6666666666666658ULL, 0x6666666666666666ULL,
                          0x6666666666666666ULL, 0x6666666666666666ULL}};
static const fe_t kBt = {{0x6dde8ab3a5b7dda3ULL, 0x20f09f80775152f5ULL,
                          0x66ea4e8e64abe37dULL, 0x67875f0fd78b7665ULL}};
static const fe_t kEdP = {{0xffffffffffffffedULL, 0xffffffffffffffffULL,
                           0xffffffffffffffffULL, 0x7fffffffffffffffULL}};
static const fe_t kEdPm2 = {{0xffffffffffffffebULL, 0xffffffffffffffffULL,
                             0xffffffffffffffffULL, 0x7fffffffffffffffULL}};
static const fe_t kEdPm5d8 = {{0xfffffffffffffffdULL, 0xffffffffffffffffULL,
                               0xffffffffffffffffULL, 0x0fffffffffffffffULL}};
static const fe_t kEdL = {{0x5812631a5cf5d3edULL, 0x14def9dea2f79cd6ULL,
                           0x0000000000000000ULL, 0x1000000000000000ULL}};

/* RFC 8032 sec. 7.1 TEST 1 / TEST 2 (as in sw/ec_ops.py). */
static const uint8_t kPub1[32] = {
    0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe,
    0xd3, 0xc9, 0x64, 0x07, 0x3a, 0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6,
    0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a};
static const uint8_t kSig1[64] = {
    0xe5, 0x56, 0x43, 0x00, 0xc3, 0x60, 0xac, 0x72, 0x90, 0x86, 0xe2,
    0xcc, 0x80, 0x6e, 0x82, 0x8a, 0x84, 0x87, 0x7f, 0x1e, 0xb8, 0xe5,
    0xd9, 0x74, 0xd8, 0x73, 0xe0, 0x65, 0x22, 0x49, 0x01, 0x55, 0x5f,
    0xb8, 0x82, 0x15, 0x90, 0xa3, 0x3b, 0xac, 0xc6, 0x1e, 0x39, 0x70,
    0x1c, 0xf9, 0xb4, 0x6b, 0xd2, 0x5b, 0xf5, 0xf0, 0x59, 0x5b, 0xbe,
    0x24, 0x65, 0x51, 0x41, 0x43, 0x8e, 0x7a, 0x10, 0x0b};
static const uint8_t kPub2[32] = {
    0x3d, 0x40, 0x17, 0xc3, 0xe8, 0x43, 0x89, 0x5a, 0x92, 0xb7, 0x0a,
    0xa7, 0x4d, 0x1b, 0x7e, 0xbc, 0x9c, 0x98, 0x2c, 0xcf, 0x2e, 0xc4,
    0x96, 0x8c, 0xc0, 0xcd, 0x55, 0xf1, 0x2a, 0xf4, 0x66, 0x0c};
static const uint8_t kMsg2[1] = {0x72};
static const uint8_t kSig2[64] = {
    0x92, 0xa0, 0x09, 0xa9, 0xf0, 0xd4, 0xca, 0xb8, 0x72, 0x0e, 0x82,
    0x0b, 0x5f, 0x64, 0x25, 0x40, 0xa2, 0xb2, 0x7b, 0x54, 0x16, 0x50,
    0x3f, 0x8f, 0xb3, 0x76, 0x22, 0x23, 0xeb, 0xdb, 0x69, 0xda, 0x08,
    0x5a, 0xc1, 0xe4, 0x3e, 0x15, 0x99, 0x6e, 0x45, 0x8f, 0x36, 0x13,
    0xd0, 0xf1, 0x1d, 0x8c, 0x38, 0x7b, 0x2e, 0xae, 0xb4, 0x30, 0x2a,
    0xee, 0xb0, 0x0d, 0x29, 0x16, 0x12, 0xbb, 0x0c, 0x00};

/* ---- 256-bit helpers (software, scalars mod L) ---- */
static void fe_from_le(fe_t *r, const uint8_t *b) {
  for (int i = 0; i < 4; i++) {
    uint64_t w = 0;
    for (int j = 7; j >= 0; j--) w = (w << 8) | b[8 * i + j];
    r->v[i] = w;
  }
}
static void fe_to_le(uint8_t *b, const fe_t *a) {
  for (int i = 0; i < 32; i++) b[i] = (uint8_t)(a->v[i >> 3] >> (8 * (i & 7)));
}
static int bn_cmp(const fe_t *a, const fe_t *b) {
  for (int i = 3; i >= 0; i--) {
    if (a->v[i] != b->v[i]) return a->v[i] > b->v[i] ? 1 : -1;
  }
  return 0;
}
/* r = a + b (256-bit, returns carry out). */
static uint64_t bn_add(const fe_t *a, const fe_t *b, fe_t *r) {
  uint64_t carry = 0;
  for (int i = 0; i < 4; i++) {
    uint64_t t = a->v[i] + b->v[i];
    uint64_t c1 = t < a->v[i];
    r->v[i] = t + carry;
    carry = c1 | (r->v[i] < t);
  }
  return carry;
}
static void bn_sub(const fe_t *a, const fe_t *b, fe_t *r) {
  uint64_t bw = 0;
  for (int i = 0; i < 4; i++) {
    uint64_t t = a->v[i] - b->v[i];
    uint64_t b1 = t > a->v[i];
    uint64_t o = t - bw;
    bw = b1 | (o > t);
    r->v[i] = o;
  }
}
/* r = (512-bit little-endian byte string) mod L, bit-serial. */
static void sc_reduce512(fe_t *r, const uint8_t *b64) {
  fe_t acc;
  fe_set_u64(&acc, 0);
  for (int i = 511; i >= 0; i--) {
    /* acc < L < 2^253, so 2*acc + 1 fits in 256 bits. */
    for (int j = 3; j > 0; j--) acc.v[j] = (acc.v[j] << 1) | (acc.v[j - 1] >> 63);
    acc.v[0] = (acc.v[0] << 1) | ((b64[i >> 3] >> (i & 7)) & 1);
    if (bn_cmp(&acc, &kEdL) >= 0) bn_sub(&acc, &kEdL, &acc);
  }
  *r = acc;
}

/* ---- SHA-512 in software on the core (FIPS 180-4) ---- */
static const uint64_t kSha512K[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL,
    0xe9b5dba58189dbbcULL, 0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL,
    0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL, 0xd807aa98a3030242ULL,
    0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL,
    0xc19bf174cf692694ULL, 0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL,
    0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL, 0x2de92c6f592b0275ULL,
    0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL,
    0xbf597fc7beef0ee4ULL, 0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
    0x06ca6351e003826fULL, 0x142929670a0e6e70ULL, 0x27b70a8546d22ffcULL,
    0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL,
    0x92722c851482353bULL, 0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL,
    0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL, 0xd192e819d6ef5218ULL,
    0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL,
    0x34b0bcb5e19b48a8ULL, 0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL,
    0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL, 0x748f82ee5defb2fcULL,
    0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL,
    0xc67178f2e372532bULL, 0xca273eceea26619cULL, 0xd186b8c721c0c207ULL,
    0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL, 0x06f067aa72176fbaULL,
    0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL,
    0x431d67c49c100d4cULL, 0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL,
    0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL};

static uint64_t ror64(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }

static void sha512_block(uint64_t h[8], const uint8_t *blk) {
  uint64_t w[80];
  for (int i = 0; i < 16; i++) {
    uint64_t x = 0;
    for (int j = 0; j < 8; j++) x = (x << 8) | blk[8 * i + j];
    w[i] = x;
  }
  for (int i = 16; i < 80; i++) {
    uint64_t s0 = ror64(w[i - 15], 1) ^ ror64(w[i - 15], 8) ^ (w[i - 15] >> 7);
    uint64_t s1 = ror64(w[i - 2], 19) ^ ror64(w[i - 2], 61) ^ (w[i - 2] >> 6);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint64_t a = h[0], b = h[1], c = h[2], d = h[3];
  uint64_t e = h[4], f = h[5], g = h[6], hh = h[7];
  for (int i = 0; i < 80; i++) {
    uint64_t t1 = hh + (ror64(e, 14) ^ ror64(e, 18) ^ ror64(e, 41)) +
                  ((e & f) ^ (~e & g)) + kSha512K[i] + w[i];
    uint64_t t2 = (ror64(a, 28) ^ ror64(a, 34) ^ ror64(a, 39)) +
                  ((a & b) ^ (a & c) ^ (b & c));
    hh = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }
  h[0] += a;
  h[1] += b;
  h[2] += c;
  h[3] += d;
  h[4] += e;
  h[5] += f;
  h[6] += g;
  h[7] += hh;
}

/* SHA-512 of the concatenation of up to 3 byte strings. */
typedef struct {
  const uint8_t *p;
  uint32_t n;
} span_t;
static void sha512(const span_t *parts, int nparts, uint8_t out[64]) {
  uint64_t h[8] = {0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL,
                   0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
                   0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
                   0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL};
  uint8_t blk[128];
  uint32_t fill = 0;
  uint64_t total = 0;
  for (int k = 0; k < nparts; k++) {
    for (uint32_t i = 0; i < parts[k].n; i++) {
      blk[fill++] = parts[k].p[i];
      total++;
      if (fill == 128) {
        sha512_block(h, blk);
        fill = 0;
      }
    }
  }
  blk[fill++] = 0x80;
  if (fill > 112) {
    while (fill < 128) blk[fill++] = 0;
    sha512_block(h, blk);
    fill = 0;
  }
  while (fill < 120) blk[fill++] = 0; /* high 64 bits of length = 0 */
  for (int j = 7; j >= 0; j--) blk[fill++] = (uint8_t)((total * 8) >> (8 * j));
  sha512_block(h, blk);
  for (int i = 0; i < 64; i++) out[i] = (uint8_t)(h[i >> 3] >> (56 - 8 * (i & 7)));
}

/* ---- Edwards points, extended coordinates, field ops on accel ---- */
typedef struct {
  fe_t x, y, z, t;
} ept_t;

static void ept_identity(ept_t *r) {
  fe_set_u64(&r->x, 0);
  fe_set_u64(&r->y, 1);
  fe_set_u64(&r->z, 1);
  fe_set_u64(&r->t, 0);
}

/* add-2008-hwcd-3 (a = -1, k = 2d); complete for Ed25519. */
static void ept_add(const ept_t *p, const ept_t *q, ept_t *r) {
  fe_t a, b, c, d, e, f, g, h, t;
  fe_sub(&p->y, &p->x, &a);
  fe_sub(&q->y, &q->x, &t);
  fe_mul(&a, &t, &a);
  fe_add(&p->y, &p->x, &b);
  fe_add(&q->y, &q->x, &t);
  fe_mul(&b, &t, &b);
  fe_mul(&p->t, &q->t, &c);
  fe_mul(&c, &kEd2D, &c);
  fe_mul(&p->z, &q->z, &d);
  fe_add(&d, &d, &d);
  fe_sub(&b, &a, &e);
  fe_sub(&d, &c, &f);
  fe_add(&d, &c, &g);
  fe_add(&b, &a, &h);
  fe_mul(&e, &f, &r->x);
  fe_mul(&g, &h, &r->y);
  fe_mul(&e, &h, &r->t);
  fe_mul(&f, &g, &r->z);
}

/* dbl-2008-hwcd with a = -1. */
static void ept_dbl(const ept_t *p, ept_t *r) {
  fe_t a, b, c, e, f, g, h, zero;
  fe_set_u64(&zero, 0);
  fe_sqr(&p->x, &a);
  fe_sqr(&p->y, &b);
  fe_sqr(&p->z, &c);
  fe_add(&c, &c, &c);
  fe_sub(&b, &a, &g);    /* G = aA + B = B - A */
  fe_sub(&g, &c, &f);    /* F = G - C */
  fe_add(&a, &b, &h);
  fe_sub(&zero, &h, &h); /* H = aA - B = -(A + B) */
  fe_add(&p->x, &p->y, &e);
  fe_sqr(&e, &e);
  fe_add(&e, &h, &e);    /* E = (X+Y)^2 - A - B */
  fe_mul(&e, &f, &r->x);
  fe_mul(&g, &h, &r->y);
  fe_mul(&e, &h, &r->t);
  fe_mul(&f, &g, &r->z);
}

/* RFC 8032 sec. 5.1.3 point decoding; returns 0 on success. */
static int ept_decode(ept_t *r, const uint8_t enc[32]) {
  fe_t y, y2, u, v, v3, v7, t, x, vx2, one, zero, negu;
  fe_from_le(&y, enc);
  int sign = (int)(y.v[3] >> 63);
  y.v[3] &= 0x7fffffffffffffffULL;
  if (bn_cmp(&y, &kEdP) >= 0) return 1;
  fe_set_u64(&one, 1);
  fe_set_u64(&zero, 0);
  fe_sqr(&y, &y2);
  fe_sub(&y2, &one, &u);              /* u = y^2 - 1 */
  fe_mul(&y2, &kEdD, &v);
  fe_add(&v, &one, &v);               /* v = d y^2 + 1 */
  fe_sqr(&v, &v3);
  fe_mul(&v3, &v, &v3);               /* v^3 */
  fe_sqr(&v3, &v7);
  fe_mul(&v7, &v, &v7);               /* v^7 */
  fe_mul(&u, &v7, &t);
  fe_pow(&t, &kEdPm5d8, &t);          /* (u v^7)^((p-5)/8) */
  fe_mul(&u, &v3, &x);
  fe_mul(&x, &t, &x);                 /* x = u v^3 (u v^7)^((p-5)/8) */
  fe_sqr(&x, &vx2);
  fe_mul(&vx2, &v, &vx2);
  fe_sub(&zero, &u, &negu);
  if (fe_eq(&vx2, &u)) {
  } else if (fe_eq(&vx2, &negu)) {
    fe_mul(&x, &kSqrtM1, &x);
  } else {
    return 1;                         /* not on the curve */
  }
  if (fe_is_zero(&x) && sign) return 1;
  if ((int)(x.v[0] & 1) != sign) fe_sub(&zero, &x, &x);
  r->x = x;
  r->y = y;
  fe_set_u64(&r->z, 1);
  fe_mul(&x, &y, &r->t);
  return 0;
}

static void ept_encode(const ept_t *p, uint8_t out[32]) {
  fe_t zi, x, y;
  fe_pow(&p->z, &kEdPm2, &zi);
  fe_mul(&p->x, &zi, &x);
  fe_mul(&p->y, &zi, &y);
  y.v[3] |= (x.v[0] & 1) << 63;
  fe_to_le(out, &y);
}

/* RFC 8032 sec. 5.1.7 verify (cofactorless, as sw/ec_ops.py).
 * Returns 0 accept, 1 bad A encoding, 2 S >= L, 3 mismatch. */
static int ed25519_verify(const uint8_t pub[32], const uint8_t *msg,
                          uint32_t mlen, const uint8_t sig[64]) {
  ept_t a, b, bma, acc;
  fe_t s, k;
  uint8_t digest[64], enc[32];
  fe_from_le(&s, sig + 32);
  if (bn_cmp(&s, &kEdL) >= 0) return 2;
  if (ept_decode(&a, pub)) return 1;
  span_t parts[3] = {{sig, 32}, {pub, 32}, {msg, mlen}};
  sha512(parts, 3, digest);
  sc_reduce512(&k, digest);
  /* -A, B, B - A for the joint ladder. */
  fe_t zero;
  fe_set_u64(&zero, 0);
  fe_sub(&zero, &a.x, &a.x);
  fe_sub(&zero, &a.t, &a.t);
  b.x = kBx;
  b.y = kBy;
  fe_set_u64(&b.z, 1);
  b.t = kBt;
  ept_add(&b, &a, &bma);
  ept_identity(&acc);
  for (int i = 255; i >= 0; i--) {
    if ((i & 31) == 31) putc('.');
    ept_dbl(&acc, &acc);
    int sb = bn_bit(&s, i), kb = bn_bit(&k, i);
    if (sb && kb) {
      ept_add(&acc, &bma, &acc);
    } else if (sb) {
      ept_add(&acc, &b, &acc);
    } else if (kb) {
      ept_add(&acc, &a, &acc);
    }
  }
  putc('\n');
  ept_encode(&acc, enc);
  uint8_t d = 0;
  for (int i = 0; i < 32; i++) d |= enc[i] ^ sig[i];
  return d ? 3 : 0;
}

int main(void) {
  puts("SOC CRYPTO START (ed25519)\r\n");

  /* Stage 1: software SHA-512("abc") KAT. */
  {
    static const uint8_t kAbc512[64] = {
        0xdd, 0xaf, 0x35, 0xa1, 0x93, 0x61, 0x7a, 0xba, 0xcc, 0x41, 0x73,
        0x49, 0xae, 0x20, 0x41, 0x31, 0x12, 0xe6, 0xfa, 0x4e, 0x89, 0xa9,
        0x7e, 0xa2, 0x0a, 0x9e, 0xee, 0xe6, 0x4b, 0x55, 0xd3, 0x9a, 0x21,
        0x92, 0x99, 0x2a, 0x27, 0x4f, 0xc1, 0xa8, 0x36, 0xba, 0x3c, 0x23,
        0xa3, 0xfe, 0xeb, 0xbd, 0x45, 0x4d, 0x44, 0x23, 0x64, 0x3c, 0xe8,
        0x0e, 0x2a, 0x9a, 0xc9, 0x4f, 0xa5, 0x4c, 0xa4, 0x9f};
    uint8_t out[64];
    span_t parts[1] = {{(const uint8_t *)"abc", 3}};
    sha512(parts, 1, out);
    uint8_t d = 0;
    for (int i = 0; i < 64; i++) d |= out[i] ^ kAbc512[i];
    if (d) fail(1);
  }
  puts("stage1 sha512 (sw) ok\r\n");

  /* Stage 2: Curve25519 field KATs on the accelerator. */
  crypto_set_modsel(1);
  {
    fe_t r, want, k;
    fe_sqr(&kSqrtM1, &r);
    bn_sub(&kEdP, &(fe_t){{1, 0, 0, 0}}, &want); /* p - 1 = -1 */
    if (!fe_eq(&r, &want)) fail(2);
    fe_mul_small(&kEdD, 121666, &r);
    fe_set_u64(&k, 121665);
    bn_sub(&kEdP, &k, &want);
    if (!fe_eq(&r, &want)) fail(2);
  }
  puts("stage2 curve25519 field ok\r\n");

  /* Stage 3/4: RFC 8032 TEST 1 and TEST 2 must accept. */
  if (ed25519_verify(kPub1, (const uint8_t *)"", 0, kSig1) != 0) fail(3);
  puts("stage3 ed25519 RFC8032 TEST1 verify ok\r\n");
  if (ed25519_verify(kPub2, kMsg2, 1, kSig2) != 0) fail(4);
  puts("stage4 ed25519 RFC8032 TEST2 verify ok\r\n");

  /* Stage 5: tampered signature (S bit 0) must reject at the
   * point compare, i.e. after the full verify computation. */
  uint8_t bad[64];
  for (int i = 0; i < 64; i++) bad[i] = kSig2[i];
  bad[32] ^= 1;
  if (ed25519_verify(kPub2, kMsg2, 1, bad) != 3) fail(5);
  puts("stage5 ed25519 tampered S rejected\r\n");

  /* Stage 6: S + L (same S mod L, non-canonical) must reject. */
  {
    fe_t s;
    fe_from_le(&s, kSig2 + 32);
    if (bn_add(&s, &kEdL, &s) != 0) fail(6);
    for (int i = 0; i < 32; i++) bad[i] = kSig2[i];
    fe_to_le(bad + 32, &s);
    if (ed25519_verify(kPub2, kMsg2, 1, bad) != 2) fail(6);
  }
  puts("stage6 ed25519 non-canonical S rejected\r\n");

  crypto_set_modsel(0);
  puts("ED25519 VERIFY OK\r\n");
  puts("SOC CRYPTO PASS\r\n");
  for (;;) __asm__ volatile("wfi");
  return 0;
}
