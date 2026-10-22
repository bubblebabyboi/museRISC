/* ed25519_verify: verify an Ed25519 signature with the SDK driver.
 *
 * sigil_ed25519_verify() (sw/sdk/lib/ed25519.c) runs every field
 * operation mod 2^255 - 19 on the accelerator's field unit and hashes
 * SHA-512(R || A || M) on the streaming hash engine. Use this file as a
 * template: replace the key, message and signature with your own.
 *
 * Vector: RFC 8032 section 7.1, TEST 2 (one-byte message 0x72; the
 * same frozen vector as sw/ec_ops.py and sw/soc-tests/ed25519_soc_test.c).
 * Checks:
 *   1. the genuine signature is accepted
 *   2. the message changed (0x72 -> 0x73) is rejected (MISMATCH)
 *   3. S >= L (non-canonical) is rejected before any curve math (BAD_S)
 * (sw/soc-tests/ed25519_soc_test.c also covers a corrupted S and
 * RFC 8032 TEST 1.)
 * One verify is about 7.4M cycles (thousands of field ops over MMIO):
 * ~0.12 s at the interim 62.5 MHz F2 clock, ~13 s in soc_rtl_tb. */
#include "sigil.h"

static const uint8_t pub[32] = {
    0x3d, 0x40, 0x17, 0xc3, 0xe8, 0x43, 0x89, 0x5a, 0x92, 0xb7, 0x0a,
    0xa7, 0x4d, 0x1b, 0x7e, 0xbc, 0x9c, 0x98, 0x2c, 0xcf, 0x2e, 0xc4,
    0x96, 0x8c, 0xc0, 0xcd, 0x55, 0xf1, 0x2a, 0xf4, 0x66, 0x0c};
static const uint8_t msg[1] = {0x72};
static const uint8_t sig[64] = {
    /* R */
    0x92, 0xa0, 0x09, 0xa9, 0xf0, 0xd4, 0xca, 0xb8, 0x72, 0x0e, 0x82,
    0x0b, 0x5f, 0x64, 0x25, 0x40, 0xa2, 0xb2, 0x7b, 0x54, 0x16, 0x50,
    0x3f, 0x8f, 0xb3, 0x76, 0x22, 0x23, 0xeb, 0xdb, 0x69, 0xda,
    /* S */
    0x08, 0x5a, 0xc1, 0xe4, 0x3e, 0x15, 0x99, 0x6e, 0x45, 0x8f, 0x36,
    0x13, 0xd0, 0xf1, 0x1d, 0x8c, 0x38, 0x7b, 0x2e, 0xae, 0xb4, 0x30,
    0x2a, 0xee, 0xb0, 0x0d, 0x29, 0x16, 0x12, 0xbb, 0x0c, 0x00};

int main(void) {
  /* 1. Genuine signature. */
  sigil_perf_t p = sigil_perf_now();
  int rc = sigil_ed25519_verify(pub, msg, sizeof msg, sig);
  sigil_perf_t t = sigil_perf_since(p);
  sigil_printf("verify(RFC 8032 TEST 2) = %d in %lu cycles (%lu instructions)\n",
               rc, (unsigned long)t.cycles, (unsigned long)t.instret);
  SIGIL_CHECK(rc == SIGIL_ED25519_OK);

  /* 2. Different message, same signature. */
  const uint8_t other[1] = {0x73};
  rc = sigil_ed25519_verify(pub, other, sizeof other, sig);
  sigil_printf("verify(changed message) = %d\n", rc);
  SIGIL_CHECK(rc == SIGIL_ED25519_MISMATCH);

  /* 3. S = 2^255 - 1 >= L. */
  uint8_t bad[64];
  memcpy(bad, sig, 32);
  memset(bad + 32, 0xff, 32);
  bad[63] = 0x7f;
  rc = sigil_ed25519_verify(pub, msg, sizeof msg, bad);
  sigil_printf("verify(S >= L) = %d\n", rc);
  SIGIL_CHECK(rc == SIGIL_ED25519_BAD_S);
  return 0;
}
