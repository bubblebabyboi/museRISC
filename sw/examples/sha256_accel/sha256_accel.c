/* sha256_accel: SHA-256 on the accelerator vs SHA-256 in software.
 *
 * The accelerator's SHA-256 engine compresses one 512-bit block from
 * the IV per start (no chaining), so sigil_sha256() handles messages
 * of up to 55 bytes (one padded block). Longer messages are hashed in
 * software here. Two software versions are compared:
 *   sw C     plain C (GCC uses Zbb rotates)
 *   sw Zknh  the same with the scalar-crypto sha256sig0/sig1/sum0/sum1
 *            instructions the core implements (Zknh)
 * Checks:
 *   1. FIPS 180-4 known answers ("", "abc", the 56-byte two-block
 *      message) in software (both versions)
 *   2. accelerator == known answer for "" and "abc"
 *   3. accelerator == software for every length 0..55 of a test pattern
 *      (and a 55-byte known answer from Python hashlib)
 *   4. a 200-byte (4-block) message in software vs hashlib
 *   5. the driver rejects a 56-byte message (-1)
 * and prints cycle counts for one block: accelerator vs both software
 * versions. */
#include "sigil.h"

/* ---------------- software SHA-256 (FIPS 180-4) ---------------- */
static const uint32_t K[64] = {
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

static inline uint32_t ror(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

/* Zknh: one instruction per sigma function (RV64: low 32 bits). */
#define ZKNH(op)                                              \
  static inline uint32_t zk_##op(uint32_t x) {                \
    uint64_t r;                                               \
    __asm__(#op " %0, %1" : "=r"(r) : "r"((uint64_t)x));      \
    return (uint32_t)r;                                       \
  }
ZKNH(sha256sig0)
ZKNH(sha256sig1)
ZKNH(sha256sum0)
ZKNH(sha256sum1)

/* One compression; `zk` is a compile-time constant at each call site,
 * so this inlines into two specialised versions. */
static inline __attribute__((always_inline)) void compress(uint32_t h[8],
                                                           const uint8_t *blk,
                                                           int zk) {
  uint32_t w[64];
  for (int i = 0; i < 16; i++) {
    w[i] = ((uint32_t)blk[4 * i] << 24) | ((uint32_t)blk[4 * i + 1] << 16) |
           ((uint32_t)blk[4 * i + 2] << 8) | blk[4 * i + 3];
  }
  for (int i = 16; i < 64; i++) {
    uint32_t s0 = zk ? zk_sha256sig0(w[i - 15])
                     : ror(w[i - 15], 7) ^ ror(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = zk ? zk_sha256sig1(w[i - 2])
                     : ror(w[i - 2], 17) ^ ror(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
  uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];
  for (int i = 0; i < 64; i++) {
    uint32_t S1 = zk ? zk_sha256sum1(e) : ror(e, 6) ^ ror(e, 11) ^ ror(e, 25);
    uint32_t S0 = zk ? zk_sha256sum0(a) : ror(a, 2) ^ ror(a, 13) ^ ror(a, 22);
    uint32_t t1 = hh + S1 + ((e & f) ^ (~e & g)) + K[i] + w[i];
    uint32_t t2 = S0 + ((a & b) ^ (a & c) ^ (b & c));
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

static inline __attribute__((always_inline)) void sha256_sw_impl(
    const uint8_t *m, size_t len, uint8_t out[32], int zk) {
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  uint8_t blk[64];
  size_t i = 0;
  for (; i + 64 <= len; i += 64) compress(h, m + i, zk);
  size_t r = len - i;
  memcpy(blk, m + i, r);
  blk[r++] = 0x80;
  if (r > 56) {
    memset(blk + r, 0, 64 - r);
    compress(h, blk, zk);
    r = 0;
  }
  memset(blk + r, 0, 56 - r);
  uint64_t bits = (uint64_t)len * 8;
  for (int j = 0; j < 8; j++) blk[56 + j] = (uint8_t)(bits >> (56 - 8 * j));
  compress(h, blk, zk);
  for (int j = 0; j < 32; j++) out[j] = (uint8_t)(h[j >> 2] >> (24 - 8 * (j & 3)));
}
static void sha256_c(const void *m, size_t len, uint8_t out[32]) {
  sha256_sw_impl((const uint8_t *)m, len, out, 0);
}
static void sha256_zknh(const void *m, size_t len, uint8_t out[32]) {
  sha256_sw_impl((const uint8_t *)m, len, out, 1);
}

/* ---------------- helpers ---------------- */
static int hexval(char c) { return c <= '9' ? c - '0' : c - 'a' + 10; }
static int eq_hex(const uint8_t *b, const char *hex) {
  for (int i = 0; i < 32; i++) {
    if (b[i] != ((hexval(hex[2 * i]) << 4) | hexval(hex[2 * i + 1]))) return 0;
  }
  return 1;
}
#define KAT_EMPTY "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
#define KAT_ABC "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
#define KAT_448 "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
/* Python: hashlib.sha256(bytes((i*7+3) & 0xff for i in range(n))) */
#define KAT_PAT55 "e7313d333c272e639f790978283f9eb392e843d0f29b7016828bb1daa4aac70b"
#define KAT_PAT200 "2c7e18c942ef065b526a2d4e5546283749cd3ddfb51d8fc71f42717363685f46"

static uint8_t pat[200];

int main(void) {
  uint8_t d1[32], d2[32], d3[32];
  const char *m448 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
  for (int i = 0; i < 200; i++) pat[i] = (uint8_t)(i * 7 + 3);

  /* 1. Software known answers. */
  sha256_c("", 0, d1);
  sha256_zknh("", 0, d2);
  SIGIL_CHECK(eq_hex(d1, KAT_EMPTY) && eq_hex(d2, KAT_EMPTY));
  sha256_c("abc", 3, d1);
  sha256_zknh("abc", 3, d2);
  SIGIL_CHECK(eq_hex(d1, KAT_ABC) && eq_hex(d2, KAT_ABC));
  sha256_c(m448, 56, d1);
  sha256_zknh(m448, 56, d2);
  SIGIL_CHECK(eq_hex(d1, KAT_448) && eq_hex(d2, KAT_448));
  sigil_printf("software SHA-256 (C and Zknh) known answers ok\n");

  /* 2. Accelerator known answers. */
  SIGIL_CHECK(sigil_sha256("", 0, d3) == 0 && eq_hex(d3, KAT_EMPTY));
  SIGIL_CHECK(sigil_sha256("abc", 3, d3) == 0 && eq_hex(d3, KAT_ABC));
  sigil_printf("accelerator SHA-256(\"abc\") = ");
  sigil_print_hex(d3, 32);
  sigil_putc('\n');

  /* 3. Accelerator vs software, every single-block length. */
  for (size_t n = 0; n <= SIGIL_SHA256_MAX_LEN; n++) {
    SIGIL_CHECK(sigil_sha256(pat, n, d3) == 0);
    sha256_c(pat, n, d1);
    SIGIL_CHECK(memcmp(d1, d3, 32) == 0);
  }
  SIGIL_CHECK(eq_hex(d3, KAT_PAT55));
  sigil_printf("accelerator == software for lengths 0..55\n");

  /* 4. Multi-block message: software only. */
  sha256_c(pat, 200, d1);
  sha256_zknh(pat, 200, d2);
  SIGIL_CHECK(eq_hex(d1, KAT_PAT200) && eq_hex(d2, KAT_PAT200));

  /* 5. Too long for the one-block engine. */
  SIGIL_CHECK(sigil_sha256(pat, 56, d3) == -1);

  /* Cycle counts for a 55-byte (one-block) message. */
  sigil_perf_t p = sigil_perf_now();
  sigil_sha256(pat, 55, d3);
  sigil_perf_t accel = sigil_perf_since(p);
  p = sigil_perf_now();
  sha256_c(pat, 55, d1);
  sigil_perf_t swc = sigil_perf_since(p);
  p = sigil_perf_now();
  sha256_zknh(pat, 55, d2);
  sigil_perf_t swk = sigil_perf_since(p);
  SIGIL_CHECK(memcmp(d1, d3, 32) == 0 && memcmp(d2, d3, 32) == 0);
  sigil_printf("SHA-256 of 55 bytes: accelerator %lu cycles (%lu instr), "
               "sw C %lu cycles (%lu instr), sw Zknh %lu cycles (%lu instr)\n",
               (unsigned long)accel.cycles, (unsigned long)accel.instret,
               (unsigned long)swc.cycles, (unsigned long)swc.instret,
               (unsigned long)swk.cycles, (unsigned long)swk.instret);
  return 0;
}
