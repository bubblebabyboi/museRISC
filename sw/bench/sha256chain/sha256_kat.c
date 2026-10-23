/* Known-answer tests and helpers for the sha256chain benchmarks.
 *
 * bench_fips_kats() checks every implementation the benchmarks measure
 * against the FIPS 180-4 / FIPS 202 example vectors before any region
 * runs (and warms the caches with the same code):
 *   SHA-256  ""  "abc"  "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
 *            (448 bits, two blocks): plain C, Zknh, RVV (all 16 lanes,
 *            one- and two-block messages, a partial vl); the
 *            accelerator for the one-block messages (sigil_sha256 and
 *            sigil_sha256_block; its engine has no chaining, so two-block
 *            messages cannot be hashed on it)
 *   SHA-512  "abc" and the 896-bit two-block message (accelerator)
 *   SHA3-256 "" and "abc" (accelerator)
 * plus the RVV chain at a partial vl against the plain-C chain. The
 * per-region results are checked by each benchmark against Python
 * hashlib values generated at build time (gen_kat.py). */
#include "sigil.h"
#include "sha256_bench.h"

#define KAT256_EMPTY "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
#define KAT256_ABC "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
#define KAT256_448 "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
#define KAT512_ABC                                                     \
  "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" \
  "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
#define KAT512_896                                                     \
  "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018" \
  "501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909"
#define KAT3_EMPTY "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
#define KAT3_ABC "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"

static const char kM448[] = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
static const char kM896[] =
    "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
    "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";

void bench_require(int ok, const char *what) {
  if (!ok) sigil_fail(what);
}

void sha256_words_to_bytes(const uint32_t h[8], uint8_t out[32]) {
  for (int i = 0; i < 32; i++) out[i] = (uint8_t)(h[i >> 2] >> (24 - 8 * (i & 3)));
}

void sha256_bytes_to_words(const uint8_t in[32], uint32_t h[8]) {
  for (int i = 0; i < 8; i++) {
    h[i] = ((uint32_t)in[4 * i] << 24) | ((uint32_t)in[4 * i + 1] << 16) |
           ((uint32_t)in[4 * i + 2] << 8) | in[4 * i + 3];
  }
}

void bench_seed(unsigned lane, uint8_t *out, size_t n) {
  for (size_t k = 0; k < n; k++) out[k] = (uint8_t)(k + 17u * lane);
}

void bench_message(uint8_t *buf, size_t n) {
  uint32_t x = 12345;
  for (size_t i = 0; i < n; i++) {
    x = x * 1103515245u + 12345u;
    buf[i] = (uint8_t)(x >> 16);
  }
}

static int hexval(char c) { return c <= '9' ? c - '0' : c - 'a' + 10; }
static int eq_hex(const uint8_t *b, const char *hex, size_t n) {
  for (size_t i = 0; i < n; i++) {
    if (b[i] != ((hexval(hex[2 * i]) << 4) | hexval(hex[2 * i + 1]))) return 0;
  }
  return 1;
}

/* FIPS 180-4 padding of a message of up to 119 bytes into nb blocks. */
static size_t pad256(const void *msg, size_t len, uint8_t *out) {
  size_t nb = len < 56 ? 64 : 128;
  memset(out, 0, nb);
  memcpy(out, msg, len);
  out[len] = 0x80;
  for (int i = 0; i < 8; i++) out[nb - 1 - i] = (uint8_t)(((uint64_t)len * 8) >> (8 * i));
  return nb / 64;
}

static void rvv_lane_digest(const sha256x16_t st, unsigned lane, uint8_t out[32]) {
  uint32_t h[8];
  sha256x16_lane(st, lane, h);
  sha256_words_to_bytes(h, out);
}

static uint8_t kat_blocks[SHA256_LANES][64] __attribute__((aligned(64)));
static uint8_t kat_two[128] __attribute__((aligned(64)));
static sha256x16_t kat_st;

void bench_fips_kats(void) {
  uint8_t d[64];

  /* Scalar: plain C and Zknh. */
  sha256_c("", 0, d);
  bench_require(eq_hex(d, KAT256_EMPTY, 32), "KAT: C SHA-256(\"\")");
  sha256_c("abc", 3, d);
  bench_require(eq_hex(d, KAT256_ABC, 32), "KAT: C SHA-256(\"abc\")");
  sha256_c(kM448, 56, d);
  bench_require(eq_hex(d, KAT256_448, 32), "KAT: C SHA-256(448-bit)");
  sha256_zknh("", 0, d);
  bench_require(eq_hex(d, KAT256_EMPTY, 32), "KAT: Zknh SHA-256(\"\")");
  sha256_zknh("abc", 3, d);
  bench_require(eq_hex(d, KAT256_ABC, 32), "KAT: Zknh SHA-256(\"abc\")");
  sha256_zknh(kM448, 56, d);
  bench_require(eq_hex(d, KAT256_448, 32), "KAT: Zknh SHA-256(448-bit)");

  /* RVV: lane j hashes "abc" (even j) or "" (odd j), one block each. */
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    pad256((j & 1) ? "" : "abc", (j & 1) ? 0 : 3, kat_blocks[j]);
  }
  sha256x16_init(kat_st);
  sha256x16_blocks(kat_st, kat_blocks[0], 64, 1, SHA256_LANES);
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    rvv_lane_digest(kat_st, j, d);
    bench_require(eq_hex(d, (j & 1) ? KAT256_EMPTY : KAT256_ABC, 32),
                  "KAT: RVV SHA-256 one-block lanes");
  }
  /* Two blocks, every lane reading the same message (stride 0). */
  bench_require(pad256(kM448, 56, kat_two) == 2, "KAT: pad");
  sha256x16_init(kat_st);
  sha256x16_blocks(kat_st, kat_two, 0, 2, SHA256_LANES);
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    rvv_lane_digest(kat_st, j, d);
    bench_require(eq_hex(d, KAT256_448, 32), "KAT: RVV SHA-256(448-bit)");
  }
  /* Partial vl = 5: lanes 0..4 hashed, lanes 5..15 untouched. */
  sha256x16_init(kat_st);
  sha256x16_blocks(kat_st, kat_blocks[0], 64, 1, 5);
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    uint32_t h[8];
    sha256x16_lane(kat_st, j, h);
    sha256_words_to_bytes(h, d);
    if (j < 5) {
      bench_require(eq_hex(d, (j & 1) ? KAT256_EMPTY : KAT256_ABC, 32),
                    "KAT: RVV SHA-256 at vl=5");
    } else {
      bench_require(memcmp(h, sha256_IV, 32) == 0, "KAT: RVV vl=5 wrote a tail lane");
    }
  }
  /* RVV chain at vl = 3 against the plain-C chain (2 steps). */
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    uint8_t s[32];
    uint32_t h[8];
    bench_seed(j, s, 32);
    sha256_bytes_to_words(s, h);
    sha256x16_set_lane(kat_st, j, h);
  }
  sha256x16_chain(kat_st, 2, 3);
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    uint8_t s[32];
    uint32_t h[8], r[8];
    bench_seed(j, s, 32);
    sha256_bytes_to_words(s, h);
    if (j < 3) sha256_chain_c(h, 2);
    sha256x16_lane(kat_st, j, r);
    bench_require(memcmp(h, r, 32) == 0, "KAT: RVV chain at vl=3");
  }
  sigil_printf("KAT FIPS 180-4 SHA-256 OK: C, Zknh, RVV x16 (\"\", \"abc\", 448-bit)\n");

  /* Accelerator SHA-256 engine: one block, no chaining. */
  bench_require(sigil_sha256("", 0, d) == 0 && eq_hex(d, KAT256_EMPTY, 32),
                "KAT: accelerator SHA-256(\"\")");
  bench_require(sigil_sha256("abc", 3, d) == 0 && eq_hex(d, KAT256_ABC, 32),
                "KAT: accelerator SHA-256(\"abc\")");
  {
    uint32_t blk[16], h[8];
    pad256("abc", 3, kat_blocks[0]);
    for (int i = 0; i < 16; i++) {
      blk[i] = ((uint32_t)kat_blocks[0][4 * i] << 24) |
               ((uint32_t)kat_blocks[0][4 * i + 1] << 16) |
               ((uint32_t)kat_blocks[0][4 * i + 2] << 8) | kat_blocks[0][4 * i + 3];
    }
    sigil_sha256_block(blk, h);
    sha256_words_to_bytes(h, d);
    bench_require(eq_hex(d, KAT256_ABC, 32), "KAT: accelerator sigil_sha256_block(\"abc\")");
  }
  sigil_printf("KAT FIPS 180-4 SHA-256 OK: accelerator (\"\", \"abc\")\n");

  /* Streaming engine: SHA-512 (FIPS 180-4), SHA3-256 (FIPS 202). */
  bench_require(sigil_hash(SIGIL_HASH_SHA512, "abc", 3, d, 64) == 0 &&
                    eq_hex(d, KAT512_ABC, 64),
                "KAT: accelerator SHA-512(\"abc\")");
  bench_require(sigil_hash(SIGIL_HASH_SHA512, kM896, 112, d, 64) == 0 &&
                    eq_hex(d, KAT512_896, 64),
                "KAT: accelerator SHA-512(896-bit)");
  bench_require(sigil_hash(SIGIL_HASH_SHA3_256, "", 0, d, 32) == 0 &&
                    eq_hex(d, KAT3_EMPTY, 32),
                "KAT: accelerator SHA3-256(\"\")");
  bench_require(sigil_hash(SIGIL_HASH_SHA3_256, "abc", 3, d, 32) == 0 &&
                    eq_hex(d, KAT3_ABC, 32),
                "KAT: accelerator SHA3-256(\"abc\")");
  sigil_printf("KAT FIPS 180-4 SHA-512 / FIPS 202 SHA3-256 OK: accelerator\n");
}

/* q = a / b with two decimals, printed as "<int>.<2 digits>". */
static void print_ratio(uint64_t a, uint64_t b) {
  uint64_t x = (a * 100 + b / 2) / b;
  sigil_printf("%llu.%02llu", (unsigned long long)(x / 100), (unsigned long long)(x % 100));
}

void bench_print_rate(const char *what, uint64_t cycles, uint64_t instret,
                      uint64_t units, const char *unit, uint64_t bytes) {
  sigil_printf("RESULT %s: %llu %s, %llu cycles, %llu instret, cycles/%s ", what,
               (unsigned long long)units, unit, (unsigned long long)cycles,
               (unsigned long long)instret, unit);
  print_ratio(cycles, units);
  sigil_printf(", bytes/cycle ");
  /* bytes/cycle with 4 decimals */
  uint64_t bpc = (bytes * 10000 + cycles / 2) / cycles;
  sigil_printf("%llu.%04llu", (unsigned long long)(bpc / 10000),
               (unsigned long long)(bpc % 10000));
  sigil_printf(", %s/s at 62.5 MHz %llu, at 100 MHz %llu\n", unit,
               (unsigned long long)((units * 62500000ull + cycles / 2) / cycles),
               (unsigned long long)((units * 100000000ull + cycles / 2) / cycles));
}
