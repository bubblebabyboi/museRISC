/* Shared bare-metal driver for the SoC crypto tests (issue #4):
 * RTL 16550 UART at 0x1000_0000 for output, and the sigil_crypto
 * accelerator at SIGIL_CRYPTO_BASE (register map: docs/SPEC.md,
 * constants: sw/sigil_crypto.h). Include from exactly one .c file
 * per firmware image (it also defines memset/memcpy for the
 * freestanding build). Reference code, NOT constant-time. */
#ifndef SOC_CRYPTO_DRV_H
#define SOC_CRYPTO_DRV_H
#include <stdint.h>

#include "../sigil_crypto.h"

#define UART ((volatile uint8_t *)0x10000000UL)
#define CRYPTO ((volatile uint32_t *)SIGIL_CRYPTO_BASE)

static void putc(char c) {
  while ((UART[5] & 0x20) == 0) {
  }
  UART[0] = (uint8_t)c;
}
static void puts(const char *s) {
  while (*s) putc(*s++);
}
static void fail(int stage) {
  puts("SOC CRYPTO FAIL stage ");
  putc((char)('0' + stage));
  puts("\r\n");
  for (;;) __asm__ volatile("wfi");
}

/* ---- 256-bit values, 4x64 little-endian limbs ---- */
typedef struct {
  uint64_t v[4];
} fe_t;

static int fe_eq(const fe_t *a, const fe_t *b) {
  uint64_t d = 0;
  for (int i = 0; i < 4; i++) d |= a->v[i] ^ b->v[i];
  return d == 0;
}
static int fe_is_zero(const fe_t *a) {
  return (a->v[0] | a->v[1] | a->v[2] | a->v[3]) == 0;
}
static void fe_set_u64(fe_t *r, uint64_t x) {
  r->v[0] = x;
  r->v[1] = r->v[2] = r->v[3] = 0;
}
static int bn_bit(const fe_t *a, int i) {
  return (int)((a->v[i >> 6] >> (i & 63)) & 1);
}

/* ---- accelerator field op (MODSEL set once per curve) ---- */
static void crypto_wait_done(void) {
  while ((CRYPTO[0x04 / 4] & 0x2u) == 0) {
  }
}
static void crypto_write_fe(uint32_t word_off, const fe_t *a) {
  for (int i = 0; i < 8; i++) {
    CRYPTO[(word_off + 4u * (uint32_t)i) / 4u] =
        (uint32_t)(a->v[i >> 1] >> (32 * (i & 1)));
  }
}
static void crypto_read_fe(fe_t *r) {
  for (int i = 0; i < 8; i++) {
    uint32_t w = CRYPTO[(0x48u + 4u * (uint32_t)i) / 4u];
    if ((i & 1) == 0) {
      r->v[i >> 1] = w;
    } else {
      r->v[i >> 1] |= (uint64_t)w << 32;
    }
  }
}
/* MODSEL: 0 secp256k1 p, 1 Curve25519 p, 2 custom MOD regs. */
static void crypto_set_modsel(uint32_t sel) { CRYPTO[0x68 / 4] = sel; }
static void fe_op(uint32_t op, const fe_t *a, const fe_t *b, fe_t *r) {
  crypto_write_fe(0x08, a);
  crypto_write_fe(0x28, b);
  CRYPTO[0] = 1u | (SIGIL_ENG_FIELD << 4) | (op << 6);
  crypto_wait_done();
  crypto_read_fe(r);
}
static void fe_add(const fe_t *a, const fe_t *b, fe_t *r) {
  fe_op(SIGIL_FLD_ADD, a, b, r);
}
static void fe_sub(const fe_t *a, const fe_t *b, fe_t *r) {
  fe_op(SIGIL_FLD_SUB, a, b, r);
}
static void fe_mul(const fe_t *a, const fe_t *b, fe_t *r) {
  fe_op(SIGIL_FLD_MUL, a, b, r);
}
static void fe_sqr(const fe_t *a, fe_t *r) { fe_mul(a, a, r); }
static void fe_mul_small(const fe_t *a, uint64_t k, fe_t *r) {
  fe_t kk;
  fe_set_u64(&kk, k);
  fe_mul(a, &kk, r);
}
static void fe_pow(const fe_t *a, const fe_t *e, fe_t *r) {
  fe_t result, base = *a;
  fe_set_u64(&result, 1);
  for (int i = 255; i >= 0; i--) {
    fe_sqr(&result, &result);
    if (bn_bit(e, i)) fe_mul(&result, &base, &result);
  }
  *r = result;
}

/* Compiler runtime stubs (no libc). */
void *memset(void *dst, int c, unsigned long n) {
  uint8_t *d = (uint8_t *)dst;
  for (unsigned long i = 0; i < n; i++) d[i] = (uint8_t)c;
  return dst;
}
void *memcpy(void *dst, const void *src, unsigned long n) {
  uint8_t *d = (uint8_t *)dst;
  const uint8_t *s = (const uint8_t *)src;
  for (unsigned long i = 0; i < n; i++) d[i] = s[i];
  return dst;
}
#endif
