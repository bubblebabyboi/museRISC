/* Scalar SHA-256 (FIPS 180-4): plain C, and the same C with the Zknh
 * scalar-crypto instructions for the four sigma functions.
 *
 * Both are the textbook formulation (64-word schedule array, eight
 * working variables) built from one always-inline template, so they
 * differ only in how the sigma functions are computed:
 *   plain C  rotates and shifts (GCC emits Zbb roriw for the rotates)
 *   Zknh     sha256sum0/sum1/sig0/sig1, one instruction each
 *            (<riscv_crypto.h> intrinsics)
 * Message words are read as aligned 32-bit loads plus a byte swap
 * (__builtin_bswap32: Zbb rev8) when the input is 4-byte aligned, and
 * byte by byte otherwise. The functions are scalar: auto-vectorization
 * and loop-to-memcpy distribution are off for this file's code (the SDK
 * -march includes V, and GCC would otherwise turn the word-copy loops
 * into vle8/vse8 loops on the element-serial vector unit). */
#pragma GCC optimize("no-tree-vectorize", "no-tree-loop-distribute-patterns")

#include <riscv_crypto.h>

#include "sigil.h"
#include "sha256_bench.h"

#define SCALAR __attribute__((noinline))

const uint32_t sha256_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

const uint32_t sha256_IV[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372,
                               0xa54ff53a, 0x510e527f, 0x9b05688c,
                               0x1f83d9ab, 0x5be0cd19};

static inline uint32_t ror32(uint32_t x, unsigned n) {
  return (x >> n) | (x << (32 - n));
}

/* zk is a compile-time constant at every call site. */
#define BSIG0(x) (zk ? __riscv_sha256sum0(x) : ror32(x, 2) ^ ror32(x, 13) ^ ror32(x, 22))
#define BSIG1(x) (zk ? __riscv_sha256sum1(x) : ror32(x, 6) ^ ror32(x, 11) ^ ror32(x, 25))
#define SSIG0(x) (zk ? __riscv_sha256sig0(x) : ror32(x, 7) ^ ror32(x, 18) ^ ((x) >> 3))
#define SSIG1(x) (zk ? __riscv_sha256sig1(x) : ror32(x, 17) ^ ror32(x, 19) ^ ((x) >> 10))

/* One compression: s = s + F(s, m), m = the 16 message words. */
static inline __attribute__((always_inline)) void compress(uint32_t s[8],
                                                           const uint32_t m[16],
                                                           int zk) {
  uint32_t w[64];
  for (int i = 0; i < 16; i++) w[i] = m[i];
  for (int i = 16; i < 64; i++) {
    w[i] = SSIG1(w[i - 2]) + w[i - 7] + SSIG0(w[i - 15]) + w[i - 16];
  }
  uint32_t a = s[0], b = s[1], c = s[2], d = s[3];
  uint32_t e = s[4], f = s[5], g = s[6], h = s[7];
  for (int i = 0; i < 64; i++) {
    uint32_t t1 = h + BSIG1(e) + ((e & f) ^ (~e & g)) + sha256_K[i] + w[i];
    uint32_t t2 = BSIG0(a) + ((a & b) ^ (a & c) ^ (b & c));
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }
  s[0] += a;
  s[1] += b;
  s[2] += c;
  s[3] += d;
  s[4] += e;
  s[5] += f;
  s[6] += g;
  s[7] += h;
}

typedef uint32_t __attribute__((may_alias)) u32_alias;

static inline void load_block(uint32_t m[16], const uint8_t *p) {
  if ((((uintptr_t)p) & 3) == 0) {
    for (int i = 0; i < 16; i++) m[i] = __builtin_bswap32(((const u32_alias *)p)[i]);
  } else {
    for (int i = 0; i < 16; i++) {
      m[i] = ((uint32_t)p[4 * i] << 24) | ((uint32_t)p[4 * i + 1] << 16) |
             ((uint32_t)p[4 * i + 2] << 8) | p[4 * i + 3];
    }
  }
}

static inline __attribute__((always_inline)) void sha256_impl(const uint8_t *msg,
                                                              size_t len,
                                                              uint8_t out[32],
                                                              int zk) {
  uint32_t s[8], m[16];
  for (int i = 0; i < 8; i++) s[i] = sha256_IV[i];
  size_t done = 0;
  for (; done + 64 <= len; done += 64) {
    load_block(m, msg + done);
    compress(s, m, zk);
  }
  /* Final block(s): the tail, 0x80, zeros, the 64-bit bit length. */
  uint8_t tail[128] __attribute__((aligned(8)));
  size_t r = len - done, nb = r < 56 ? 64 : 128;
  for (size_t i = 0; i < r; i++) tail[i] = msg[done + i];
  tail[r] = 0x80;
  for (size_t i = r + 1; i < nb - 8; i++) tail[i] = 0;
  uint64_t bits = (uint64_t)len * 8;
  for (int i = 0; i < 8; i++) tail[nb - 1 - i] = (uint8_t)(bits >> (8 * i));
  for (size_t off = 0; off < nb; off += 64) {
    load_block(m, tail + off);
    compress(s, m, zk);
  }
  sha256_words_to_bytes(s, out);
}

/* Chain step: the message is the previous digest (words H0..H7), one
 * padded block: 0x80 terminator, zeros, bit length 256. */
static inline __attribute__((always_inline)) void chain_impl(uint32_t h[8],
                                                             size_t n, int zk) {
  uint32_t m[16];
  m[8] = 0x80000000u;
  for (int i = 9; i < 15; i++) m[i] = 0;
  m[15] = 256;
  for (; n > 0; n--) {
    uint32_t s[8];
    for (int i = 0; i < 8; i++) {
      m[i] = h[i];
      s[i] = sha256_IV[i];
    }
    compress(s, m, zk);
    for (int i = 0; i < 8; i++) h[i] = s[i];
  }
}

SCALAR void sha256_c(const void *msg, size_t len, uint8_t out[32]) {
  sha256_impl((const uint8_t *)msg, len, out, 0);
}
SCALAR void sha256_zknh(const void *msg, size_t len, uint8_t out[32]) {
  sha256_impl((const uint8_t *)msg, len, out, 1);
}
SCALAR void sha256_chain_c(uint32_t h[8], size_t n) { chain_impl(h, n, 0); }
SCALAR void sha256_chain_zknh(uint32_t h[8], size_t n) { chain_impl(h, n, 1); }
