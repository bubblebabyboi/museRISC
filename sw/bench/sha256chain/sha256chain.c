/* sha256chain: SHA-256 hash chain h_{i+1} = SHA-256(h_i), N hashes per
 * measured region (issue #10; harness: docs/PERFORMANCE.md).
 *
 * Regions (bench.json "regions"; every region does N hashes):
 *   0  plain C          one chain, scalar C
 *   1  Zknh             one chain, scalar C + sha256sum0/sum1/sig0/sig1
 *   2  RVV x16          16 independent chains, one per lane (multi-
 *                       buffer), N hashes in total: lane j does N/16
 *                       steps (+1 for j < N%16)
 *   3  accel block      one chain on the accelerator's SHA-256 engine,
 *                       SDK raw block driver sigil_sha256_block(): the
 *                       digest words are the next message words
 *   4  accel bytes      the same through the SDK byte API sigil_sha256()
 *   5  accel SHA-512    h_{i+1} = SHA-512(h_i), 64-byte chain, SDK
 *                       streaming driver sigil_hash()
 *   6  accel SHA3-256   h_{i+1} = SHA3-256(h_i), sigil_hash()
 * The chains start from the seed bench_seed(0) (bytes 0, 1, 2, ...);
 * RVV lane j from bench_seed(j). Before the regions every
 * implementation passes the FIPS 180-4 / FIPS 202 known answers
 * (sha256_kat.c); after each region its final chain values are checked
 * against Python hashlib (gen_kat.py, generated at build time for this
 * N). Any mismatch fails the test. */
#include "sigil.h"
#include "sha256_bench.h"
#include SHA256CHAIN_KAT_H

#define N ((size_t)SHA256CHAIN_HASHES)
#if SHA256CHAIN_HASHES != KAT_CHAIN_HASHES
#error "known-answer header built for a different hash count"
#endif

static sha256x16_t st16;

static void seed_words(unsigned lane, uint32_t h[8]) {
  uint8_t s[32];
  bench_seed(lane, s, 32);
  sha256_bytes_to_words(s, h);
}

static void check_words(const uint32_t h[8], const uint8_t want[32], const char *what) {
  uint8_t d[32];
  sha256_words_to_bytes(h, d);
  bench_require(memcmp(d, want, 32) == 0, what);
}

static void result(const char *what, sigil_perf_t t, uint64_t msg_bytes) {
  bench_print_rate(what, t.cycles, t.instret, N, "hash", N * msg_bytes);
}

/* Accelerator chains: each region is one call (the functions start on
 * an I$ line, -falign-functions=64 in the Makefile). */
__attribute__((noinline)) static void accel_chain_block(uint32_t blk[16], size_t n) {
  for (; n > 0; n--) sigil_sha256_block(blk, blk);
}
__attribute__((noinline)) static int accel_chain_bytes(uint8_t m[32], size_t n) {
  int err = 0;
  for (; n > 0; n--) err |= sigil_sha256(m, 32, m);
  return err;
}
__attribute__((noinline)) static int accel_chain_hash(int mode, uint8_t *m, size_t len,
                                                      size_t n) {
  int err = 0;
  for (; n > 0; n--) err |= sigil_hash(mode, m, len, m, len);
  return err;
}

int main(void) {
  uint32_t h[8];
  sigil_perf_t t;

  bench_fips_kats();

  /* 0: plain C. */
  seed_words(0, h);
  sigil_perf_begin_id(0);
  sha256_chain_c(h, N);
  t = sigil_perf_end_id(0);
  check_words(h, kat_chain_sha256, "chain: plain C != hashlib");
  result("sha256 plain C", t, 32);

  /* 1: Zknh. */
  seed_words(0, h);
  sigil_perf_begin_id(1);
  sha256_chain_zknh(h, N);
  t = sigil_perf_end_id(1);
  check_words(h, kat_chain_sha256, "chain: Zknh != hashlib");
  result("sha256 Zknh", t, 32);

  /* 2: RVV, 16 chains. */
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    seed_words(j, h);
    sha256x16_set_lane(st16, j, h);
  }
  sigil_perf_begin_id(2);
  sha256x16_chain(st16, N / SHA256_LANES, SHA256_LANES);
  if (N % SHA256_LANES) sha256x16_chain(st16, 1, N % SHA256_LANES);
  t = sigil_perf_end_id(2);
  for (unsigned j = 0; j < SHA256_LANES; j++) {
    sha256x16_lane(st16, j, h);
    check_words(h, kat_chain_lanes[j], "chain: RVV lane != hashlib");
  }
  result("sha256 RVV x16", t, 32);

  /* 3: accelerator, raw block driver. blk[0..7] = h, then the padding
   * of a 32-byte message; the driver writes H0..H7 back into blk[0..7]
   * after it has sent the whole block. */
  {
    uint32_t blk[16];
    seed_words(0, blk);
    blk[8] = 0x80000000u;
    for (int i = 9; i < 15; i++) blk[i] = 0;
    blk[15] = 256;
    sigil_perf_begin_id(3);
    accel_chain_block(blk, N);
    t = sigil_perf_end_id(3);
    check_words(blk, kat_chain_sha256, "chain: accelerator block != hashlib");
    result("sha256 accel sigil_sha256_block", t, 32);
  }

  /* 4: accelerator, byte API (packs the message, pads, unpacks). */
  {
    uint8_t m[32];
    int err;
    bench_seed(0, m, 32);
    sigil_perf_begin_id(4);
    err = accel_chain_bytes(m, N);
    t = sigil_perf_end_id(4);
    bench_require(err == 0 && memcmp(m, kat_chain_sha256, 32) == 0,
                  "chain: accelerator sigil_sha256 != hashlib");
    result("sha256 accel sigil_sha256", t, 32);
  }

  /* 5: accelerator SHA-512, 64-byte chain. */
  {
    uint8_t m[64] __attribute__((aligned(8)));
    int err;
    bench_seed(0, m, 64);
    sigil_perf_begin_id(5);
    err = accel_chain_hash(SIGIL_HASH_SHA512, m, 64, N);
    t = sigil_perf_end_id(5);
    bench_require(err == 0 && memcmp(m, kat_chain_sha512, 64) == 0,
                  "chain: accelerator SHA-512 != hashlib");
    result("sha512 accel sigil_hash", t, 64);
  }

  /* 6: accelerator SHA3-256. */
  {
    uint8_t m[32] __attribute__((aligned(8)));
    int err;
    bench_seed(0, m, 32);
    sigil_perf_begin_id(6);
    err = accel_chain_hash(SIGIL_HASH_SHA3_256, m, 32, N);
    t = sigil_perf_end_id(6);
    bench_require(err == 0 && memcmp(m, kat_chain_sha3_256, 32) == 0,
                  "chain: accelerator SHA3-256 != hashlib");
    result("sha3-256 accel sigil_hash", t, 32);
  }

  sigil_printf("sha256 chain h_%lu = ", (unsigned long)N);
  sigil_print_hex(kat_chain_sha256, 32);
  sigil_printf("\nSHA256CHAIN CHECK OK hashes=%lu\n", (unsigned long)N);
  sigil_pass();
}
