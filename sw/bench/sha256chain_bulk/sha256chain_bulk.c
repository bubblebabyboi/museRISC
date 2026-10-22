/* sha256chain_bulk: bulk hashing of a 64 KiB buffer (issue #10, the
 * throughput half of sw/bench/sha256chain; harness:
 * docs/PERFORMANCE.md). The implementations are those of the
 * sha256chain benchmark (../sha256chain/README.md).
 *
 * Regions (bench.json "regions"; every region hashes all
 * SHA256CHAIN_KIB KiB of the buffer once, 64 KiB by default):
 *   0  plain C          SHA-256 of the buffer, scalar C
 *   1  Zknh             SHA-256 of the buffer, scalar C + Zknh
 *   2  RVV x16          SHA-256 of each of 16 equal segments (4 KiB at
 *                       64 KiB), one per lane: multi-buffer, as for a
 *                       Merkle leaf layer. The accelerator's SHA-256
 *                       engine hashes one block from the IV (no
 *                       chaining), so it cannot hash a 64 KiB message.
 *   3  accel SHA-512    SHA-512 of the buffer, SDK streaming driver
 *   4  accel SHA3-256   SHA3-256 of the buffer, SDK streaming driver
 * The buffer is bench_message() (the LCG of sw/examples/hash_stream),
 * filled before the regions. Before the regions every implementation
 * passes the FIPS 180-4 / FIPS 202 known answers (sha256_kat.c); after
 * each region its digests are checked against Python hashlib
 * (gen_kat.py, generated at build time for this size). Any mismatch
 * fails the test. */
#include "sigil.h"
#include "sha256_bench.h"
#include SHA256CHAIN_KAT_H

#define KIB ((size_t)SHA256CHAIN_KIB)
#define LEN (KIB * 1024)
#define SEG (LEN / SHA256_LANES) /* a multiple of 64 bytes */
#if SHA256CHAIN_KIB != KAT_BULK_KIB
#error "known-answer header built for a different buffer size"
#endif

static uint8_t buf[LEN] __attribute__((aligned(64)));
static sha256x16_t st16;

static void result(const char *what, sigil_perf_t t) {
  bench_print_rate(what, t.cycles, t.instret, KIB, "KiB", LEN);
}

int main(void) {
  uint8_t d[64];
  sigil_perf_t t;

  bench_fips_kats();
  bench_message(buf, LEN);

  /* 0: plain C. */
  sigil_perf_begin_id(0);
  sha256_c(buf, LEN, d);
  t = sigil_perf_end_id(0);
  bench_require(memcmp(d, kat_bulk_sha256, 32) == 0, "bulk: plain C != hashlib");
  result("sha256 plain C", t);

  /* 1: Zknh. */
  sigil_perf_begin_id(1);
  sha256_zknh(buf, LEN, d);
  t = sigil_perf_end_id(1);
  bench_require(memcmp(d, kat_bulk_sha256, 32) == 0, "bulk: Zknh != hashlib");
  result("sha256 Zknh", t);

  /* 2: RVV, 16 segments: SEG/64 data blocks per lane, then one padding
   * block that every lane shares (same length; lane stride 0). */
  {
    static uint8_t pad[64] __attribute__((aligned(64)));
    uint64_t bits = (uint64_t)SEG * 8;
    memset(pad, 0, sizeof pad);
    pad[0] = 0x80;
    for (int i = 0; i < 8; i++) pad[63 - i] = (uint8_t)(bits >> (8 * i));
    sha256x16_init(st16);
    sigil_perf_begin_id(2);
    sha256x16_blocks(st16, buf, SEG, SEG / 64, SHA256_LANES);
    sha256x16_blocks(st16, pad, 0, 1, SHA256_LANES);
    t = sigil_perf_end_id(2);
    for (unsigned j = 0; j < SHA256_LANES; j++) {
      uint32_t h[8];
      sha256x16_lane(st16, j, h);
      sha256_words_to_bytes(h, d);
      bench_require(memcmp(d, kat_bulk_lanes[j], 32) == 0, "bulk: RVV lane != hashlib");
    }
    result("sha256 RVV x16", t);
  }

  /* 3: accelerator SHA-512. */
  {
    int rc;
    sigil_perf_begin_id(3);
    rc = sigil_hash(SIGIL_HASH_SHA512, buf, LEN, d, 64);
    t = sigil_perf_end_id(3);
    bench_require(rc == 0 && memcmp(d, kat_bulk_sha512, 64) == 0,
                  "bulk: accelerator SHA-512 != hashlib");
    result("sha512 accel sigil_hash", t);
  }

  /* 4: accelerator SHA3-256. */
  {
    int rc;
    sigil_perf_begin_id(4);
    rc = sigil_hash(SIGIL_HASH_SHA3_256, buf, LEN, d, 32);
    t = sigil_perf_end_id(4);
    bench_require(rc == 0 && memcmp(d, kat_bulk_sha3_256, 32) == 0,
                  "bulk: accelerator SHA3-256 != hashlib");
    result("sha3-256 accel sigil_hash", t);
  }

  sigil_printf("sha256 of the %lu KiB buffer = ", (unsigned long)KIB);
  sigil_print_hex(kat_bulk_sha256, 32);
  sigil_printf("\nSHA256CHAIN_BULK CHECK OK kib=%lu\n", (unsigned long)KIB);
  sigil_pass();
}
