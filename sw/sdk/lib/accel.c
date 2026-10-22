/* Sigil SDK crypto accelerator driver (sigil_crypto at 0x2000_0000).
 * Register map: docs/SPEC.md section 3 and sw/sigil_crypto.h; this is
 * the same programming model as sw/soc-tests/soc_crypto_drv.h and
 * sw/hash-tests/hash_soc_test.c, packaged as a library. */
#include "sigil.h"

/* ---------------- SHA-256 (one block per start) ---------------- */
static void wait_done(void) {
  while ((SIGIL_REG32(SIGIL_STATUS) & 0x2u) == 0) {
  }
}

void sigil_sha256_block(const uint32_t block[16], uint32_t h[8]) {
  for (int i = 0; i < 16; i++) SIGIL_REG32(SIGIL_DIN(i)) = block[i];
  SIGIL_REG32(SIGIL_CTRL) = 1u | (SIGIL_ENG_SHA256 << 4);
  wait_done();
  /* DOUT0 is the low word of the digest read as a 256-bit number,
   * i.e. H7; DOUT7 is H0. */
  for (int i = 0; i < 8; i++) h[7 - i] = SIGIL_REG32(SIGIL_DOUT(i));
}

int sigil_sha256(const void *msg, size_t len, uint8_t digest[32]) {
  const uint8_t *m = (const uint8_t *)msg;
  if (len > SIGIL_SHA256_MAX_LEN) return -1;
  uint32_t block[16] = {0}, h[8];
  for (size_t i = 0; i < len; i++) block[i >> 2] |= (uint32_t)m[i] << (24 - 8 * (i & 3));
  block[len >> 2] |= 0x80u << (24 - 8 * (len & 3));
  block[15] = (uint32_t)len * 8u;
  sigil_sha256_block(block, h);
  for (int i = 0; i < 32; i++) digest[i] = (uint8_t)(h[i >> 2] >> (24 - 8 * (i & 3)));
  return 0;
}

/* ---------------- streaming hash ---------------- */
static int hash_mode;
static uint32_t pend;     /* up to 3 bytes not yet written to HDATA */
static unsigned pend_n;

void sigil_hash_init(int mode) {
  hash_mode = mode;
  pend = 0;
  pend_n = 0;
  SIGIL_REG32(SIGIL_HCTRL) = SIGIL_HCTRL_INIT(mode);
}

void sigil_hash_update(const void *data, size_t len) {
  const uint8_t *p = (const uint8_t *)data;
  /* Top up a partial word first. */
  while (len > 0 && pend_n != 0) {
    pend |= (uint32_t)*p++ << (8 * pend_n);
    len--;
    if (++pend_n == 4) {
      SIGIL_REG32(SIGIL_HDATA) = pend;
      pend = 0;
      pend_n = 0;
    }
  }
  /* Whole words: HDATA stalls the store while the block buffer is
   * full, so no status polling is needed here. */
  if ((((uintptr_t)p) & 3) == 0) {
    for (; len >= 4; len -= 4, p += 4) SIGIL_REG32(SIGIL_HDATA) = *(const uint32_t *)p;
  } else {
    for (; len >= 4; len -= 4, p += 4) {
      SIGIL_REG32(SIGIL_HDATA) = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                                 ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    }
  }
  while (len-- > 0) pend |= (uint32_t)*p++ << (8 * pend_n++);
}

static void hash_wait(void) {
  while ((SIGIL_REG32(SIGIL_HSTATUS) & SIGIL_HS_DONE) == 0) {
  }
}

int sigil_hash_final(uint8_t *out, size_t outlen) {
  size_t per; /* output bytes available per squeeze */
  switch (hash_mode) {
    case SIGIL_HASH_SHA512: per = 64; break;
    case SIGIL_HASH_SHA3_256:
    case SIGIL_HASH_KECCAK256: per = 32; break;
    default: per = 136; break; /* SHAKE256: whole rate, then squeeze */
  }
  SIGIL_REG32(SIGIL_HFIN) = SIGIL_HFIN_WORD(pend_n, pend);
  pend = 0;
  pend_n = 0;
  if (hash_mode != SIGIL_HASH_SHAKE256 && outlen > per) return -1;
  hash_wait();
  size_t got = 0;
  for (;;) {
    for (size_t k = 0; k < per && got < outlen; k += 4) {
      uint32_t w = SIGIL_REG32(SIGIL_HDOUT);
      for (int b = 0; b < 4 && got < outlen; b++) out[got++] = (uint8_t)(w >> (8 * b));
    }
    if (got >= outlen) break;
    SIGIL_REG32(SIGIL_HCTRL) = SIGIL_HCTRL_SQUEEZE;
    hash_wait();
  }
  return (SIGIL_REG32(SIGIL_HSTATUS) & SIGIL_HS_ERR) ? -1 : 0;
}

int sigil_hash(int mode, const void *msg, size_t len, uint8_t *out, size_t outlen) {
  sigil_hash_init(mode);
  sigil_hash_update(msg, len);
  return sigil_hash_final(out, outlen);
}

/* ---------------- 256-bit field unit ---------------- */
static void write_fe(uintptr_t reg, const sigil_fe_t *a) {
  for (int i = 0; i < 8; i++) {
    SIGIL_REG32(reg + 4u * (unsigned)i) = (uint32_t)(a->v[i >> 1] >> (32 * (i & 1)));
  }
}

void sigil_fe_modsel(uint32_t sel) { SIGIL_REG32(SIGIL_MODSEL) = sel; }

void sigil_fe_set_modulus(const sigil_fe_t *m) {
  write_fe(SIGIL_MOD(0), m);
  sigil_fe_modsel(SIGIL_MOD_CUSTOM);
}

static void fe_op(uint32_t op, const sigil_fe_t *a, const sigil_fe_t *b, sigil_fe_t *r) {
  write_fe(SIGIL_DIN(0), a); /* A = DIN0..7  */
  write_fe(SIGIL_DIN(8), b); /* B = DIN8..15 */
  SIGIL_REG32(SIGIL_CTRL) = 1u | (SIGIL_ENG_FIELD << 4) | (op << 6);
  wait_done();
  for (int i = 0; i < 4; i++) {
    r->v[i] = (uint64_t)SIGIL_REG32(SIGIL_DOUT(2 * i)) |
              ((uint64_t)SIGIL_REG32(SIGIL_DOUT(2 * i + 1)) << 32);
  }
}

void sigil_fe_add(const sigil_fe_t *a, const sigil_fe_t *b, sigil_fe_t *r) {
  fe_op(SIGIL_FLD_ADD, a, b, r);
}
void sigil_fe_sub(const sigil_fe_t *a, const sigil_fe_t *b, sigil_fe_t *r) {
  fe_op(SIGIL_FLD_SUB, a, b, r);
}
void sigil_fe_mul(const sigil_fe_t *a, const sigil_fe_t *b, sigil_fe_t *r) {
  fe_op(SIGIL_FLD_MUL, a, b, r);
}

void sigil_fe_pow(const sigil_fe_t *a, const sigil_fe_t *e, sigil_fe_t *r) {
  sigil_fe_t acc, base = *a;
  sigil_fe_set_u64(&acc, 1);
  for (int i = 255; i >= 0; i--) {
    sigil_fe_mul(&acc, &acc, &acc);
    if ((e->v[i >> 6] >> (i & 63)) & 1) sigil_fe_mul(&acc, &base, &acc);
  }
  *r = acc;
}
