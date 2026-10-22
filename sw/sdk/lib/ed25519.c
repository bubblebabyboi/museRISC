/* Ed25519 verify for the Sigil SDK (RFC 8032 section 5.1.7, the
 * cofactorless check used by sw/ec_ops.py and ref10). Field ops mod
 * p = 2^255 - 19 run on the accelerator's field unit (MODSEL = 1);
 * k = SHA-512(R || A || M) runs on the streaming hash engine. Points are
 * extended twisted Edwards (X:Y:Z:T), a = -1 (add-2008-hwcd-3,
 * dbl-2008-hwcd); [S]B + [k](-A) is one joint double-and-add ladder.
 * Same math as sw/soc-tests/ed25519_soc_test.c (which hashes in
 * software). Variable-time reference code: public inputs only. */
#include "sigil.h"

typedef sigil_fe_t fe;
#define fe_add sigil_fe_add
#define fe_sub sigil_fe_sub
#define fe_mul sigil_fe_mul

static const fe kD = {{0x75eb4dca135978a3ULL, 0x00700a4d4141d8abULL,
                       0x8cc740797779e898ULL, 0x52036cee2b6ffe73ULL}};
static const fe k2D = {{0xebd69b9426b2f159ULL, 0x00e0149a8283b156ULL,
                        0x198e80f2eef3d130ULL, 0x2406d9dc56dffce7ULL}};
static const fe kSqrtM1 = {{0xc4ee1b274a0ea0b0ULL, 0x2f431806ad2fe478ULL,
                            0x2b4d00993dfbd7a7ULL, 0x2b8324804fc1df0bULL}};
static const fe kBx = {{0xc9562d608f25d51aULL, 0x692cc7609525a7b2ULL,
                        0xc0a4e231fdd6dc5cULL, 0x216936d3cd6e53feULL}};
static const fe kBy = {{0x6666666666666658ULL, 0x6666666666666666ULL,
                        0x6666666666666666ULL, 0x6666666666666666ULL}};
static const fe kBt = {{0x6dde8ab3a5b7dda3ULL, 0x20f09f80775152f5ULL,
                        0x66ea4e8e64abe37dULL, 0x67875f0fd78b7665ULL}};
static const fe kP = {{0xffffffffffffffedULL, 0xffffffffffffffffULL,
                       0xffffffffffffffffULL, 0x7fffffffffffffffULL}};
static const fe kPm2 = {{0xffffffffffffffebULL, 0xffffffffffffffffULL,
                         0xffffffffffffffffULL, 0x7fffffffffffffffULL}};
static const fe kPm5d8 = {{0xfffffffffffffffdULL, 0xffffffffffffffffULL,
                           0xffffffffffffffffULL, 0x0fffffffffffffffULL}};
static const fe kL = {{0x5812631a5cf5d3edULL, 0x14def9dea2f79cd6ULL,
                       0x0000000000000000ULL, 0x1000000000000000ULL}};

static int bit(const fe *a, int i) { return (int)((a->v[i >> 6] >> (i & 63)) & 1); }
static int is_zero(const fe *a) { return (a->v[0] | a->v[1] | a->v[2] | a->v[3]) == 0; }

static void from_le(fe *r, const uint8_t *b) {
  for (int i = 0; i < 4; i++) {
    uint64_t w = 0;
    for (int j = 7; j >= 0; j--) w = (w << 8) | b[8 * i + j];
    r->v[i] = w;
  }
}
static void to_le(uint8_t *b, const fe *a) {
  for (int i = 0; i < 32; i++) b[i] = (uint8_t)(a->v[i >> 3] >> (8 * (i & 7)));
}
static int cmp(const fe *a, const fe *b) {
  for (int i = 3; i >= 0; i--) {
    if (a->v[i] != b->v[i]) return a->v[i] > b->v[i] ? 1 : -1;
  }
  return 0;
}
static void bn_sub(const fe *a, const fe *b, fe *r) {
  uint64_t bw = 0;
  for (int i = 0; i < 4; i++) {
    uint64_t t = a->v[i] - b->v[i];
    uint64_t b1 = t > a->v[i];
    uint64_t o = t - bw;
    bw = b1 | (o > t);
    r->v[i] = o;
  }
}
/* r = (512-bit little-endian string) mod L, bit-serial. */
static void reduce512(fe *r, const uint8_t b[64]) {
  fe acc = {{0, 0, 0, 0}};
  for (int i = 511; i >= 0; i--) {
    for (int j = 3; j > 0; j--) acc.v[j] = (acc.v[j] << 1) | (acc.v[j - 1] >> 63);
    acc.v[0] = (acc.v[0] << 1) | ((b[i >> 3] >> (i & 7)) & 1);
    if (cmp(&acc, &kL) >= 0) bn_sub(&acc, &kL, &acc);
  }
  *r = acc;
}

typedef struct {
  fe x, y, z, t;
} pt;

static void pt_add(const pt *p, const pt *q, pt *r) {
  fe a, b, c, d, e, f, g, h, t;
  fe_sub(&p->y, &p->x, &a);
  fe_sub(&q->y, &q->x, &t);
  fe_mul(&a, &t, &a);
  fe_add(&p->y, &p->x, &b);
  fe_add(&q->y, &q->x, &t);
  fe_mul(&b, &t, &b);
  fe_mul(&p->t, &q->t, &c);
  fe_mul(&c, &k2D, &c);
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

static void pt_dbl(const pt *p, pt *r) {
  fe a, b, c, e, f, g, h, zero = {{0, 0, 0, 0}};
  fe_mul(&p->x, &p->x, &a);
  fe_mul(&p->y, &p->y, &b);
  fe_mul(&p->z, &p->z, &c);
  fe_add(&c, &c, &c);
  fe_sub(&b, &a, &g);
  fe_sub(&g, &c, &f);
  fe_add(&a, &b, &h);
  fe_sub(&zero, &h, &h);
  fe_add(&p->x, &p->y, &e);
  fe_mul(&e, &e, &e);
  fe_add(&e, &h, &e);
  fe_mul(&e, &f, &r->x);
  fe_mul(&g, &h, &r->y);
  fe_mul(&e, &h, &r->t);
  fe_mul(&f, &g, &r->z);
}

/* RFC 8032 section 5.1.3 point decoding; returns 0 on success. */
static int pt_decode(pt *r, const uint8_t enc[32]) {
  fe y, y2, u, v, v3, v7, t, x, vx2, negu, one = {{1, 0, 0, 0}}, zero = {{0, 0, 0, 0}};
  from_le(&y, enc);
  int sign = (int)(y.v[3] >> 63);
  y.v[3] &= 0x7fffffffffffffffULL;
  if (cmp(&y, &kP) >= 0) return 1;
  fe_mul(&y, &y, &y2);
  fe_sub(&y2, &one, &u);       /* u = y^2 - 1     */
  fe_mul(&y2, &kD, &v);
  fe_add(&v, &one, &v);        /* v = d y^2 + 1   */
  fe_mul(&v, &v, &v3);
  fe_mul(&v3, &v, &v3);        /* v^3             */
  fe_mul(&v3, &v3, &v7);
  fe_mul(&v7, &v, &v7);        /* v^7             */
  fe_mul(&u, &v7, &t);
  sigil_fe_pow(&t, &kPm5d8, &t);
  fe_mul(&u, &v3, &x);
  fe_mul(&x, &t, &x);          /* candidate root  */
  fe_mul(&x, &x, &vx2);
  fe_mul(&vx2, &v, &vx2);
  fe_sub(&zero, &u, &negu);
  if (sigil_fe_eq(&vx2, &negu)) {
    fe_mul(&x, &kSqrtM1, &x);
  } else if (!sigil_fe_eq(&vx2, &u)) {
    return 1;                  /* not on the curve */
  }
  if (is_zero(&x) && sign) return 1;
  if ((int)(x.v[0] & 1) != sign) fe_sub(&zero, &x, &x);
  r->x = x;
  r->y = y;
  sigil_fe_set_u64(&r->z, 1);
  fe_mul(&x, &y, &r->t);
  return 0;
}

static void pt_encode(const pt *p, uint8_t out[32]) {
  fe zi, x, y;
  sigil_fe_pow(&p->z, &kPm2, &zi);
  fe_mul(&p->x, &zi, &x);
  fe_mul(&p->y, &zi, &y);
  y.v[3] |= (x.v[0] & 1) << 63;
  to_le(out, &y);
}

int sigil_ed25519_verify(const uint8_t pub[32], const void *msg, size_t len,
                         const uint8_t sig[64]) {
  pt a, b, bma, acc;
  fe s, k, zero = {{0, 0, 0, 0}};
  uint8_t digest[64], enc[32];

  from_le(&s, sig + 32);
  if (cmp(&s, &kL) >= 0) return SIGIL_ED25519_BAD_S;
  sigil_fe_modsel(SIGIL_MOD_CURVE25519);
  if (pt_decode(&a, pub)) return SIGIL_ED25519_BAD_KEY;

  /* k = SHA-512(R || A || M) mod L, hashed by the streaming engine. */
  sigil_hash_init(SIGIL_HASH_SHA512);
  sigil_hash_update(sig, 32);
  sigil_hash_update(pub, 32);
  sigil_hash_update(msg, len);
  sigil_hash_final(digest, 64);
  reduce512(&k, digest);

  /* Joint ladder over (S, k) with B, -A and B - A. */
  fe_sub(&zero, &a.x, &a.x);
  fe_sub(&zero, &a.t, &a.t);
  b.x = kBx;
  b.y = kBy;
  sigil_fe_set_u64(&b.z, 1);
  b.t = kBt;
  pt_add(&b, &a, &bma);
  acc.x = zero;
  sigil_fe_set_u64(&acc.y, 1);
  sigil_fe_set_u64(&acc.z, 1);
  acc.t = zero;
  for (int i = 255; i >= 0; i--) {
    pt_dbl(&acc, &acc);
    int sb = bit(&s, i), kb = bit(&k, i);
    if (sb && kb) {
      pt_add(&acc, &bma, &acc);
    } else if (sb) {
      pt_add(&acc, &b, &acc);
    } else if (kb) {
      pt_add(&acc, &a, &acc);
    }
  }
  pt_encode(&acc, enc);
  uint8_t d = 0;
  for (int i = 0; i < 32; i++) d |= enc[i] ^ sig[i];
  return d ? SIGIL_ED25519_MISMATCH : SIGIL_ED25519_OK;
}
