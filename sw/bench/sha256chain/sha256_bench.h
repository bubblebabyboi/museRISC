/* SHA-256 implementations and checks shared by the sha256chain and
 * sha256chain_bulk benchmarks (README.md here).
 *
 *   sha256_sw.c    scalar: plain C, and C with the Zknh instructions
 *                  (sha256sig0/sig1/sum0/sum1)
 *   sha256_rvv.c   RVV multi-buffer: 16 independent messages, one per
 *                  32-bit lane (e32, LMUL 1, VLEN 512)
 *   sha256_kat.c   FIPS 180-4 / FIPS 202 known answers for every
 *                  implementation (scalar, RVV, accelerator), the
 *                  benchmark seeds and message, helpers
 *
 * The accelerator side is the SDK driver as is (sigil.h:
 * sigil_sha256, sigil_sha256_block, sigil_hash). */
#ifndef SHA256_BENCH_H
#define SHA256_BENCH_H

#include <stddef.h>
#include <stdint.h>

/* RVV lanes: vsetvlmax(e32, m1) at VLEN 512. */
#define SHA256_LANES 16

extern const uint32_t sha256_K[64];
extern const uint32_t sha256_IV[8];

/* ---- scalar (sha256_sw.c) ---- */
/* One-shot SHA-256 of len bytes (FIPS 180-4 padding). */
void sha256_c(const void *msg, size_t len, uint8_t out[32]);
void sha256_zknh(const void *msg, size_t len, uint8_t out[32]);
/* Hash chain in place: n times h = SHA-256(h), h as the 8 big-endian
 * digest words (a 32-byte message is exactly words H0..H7). */
void sha256_chain_c(uint32_t h[8], size_t n);
void sha256_chain_zknh(uint32_t h[8], size_t n);

/* ---- RVV multi-buffer (sha256_rvv.c) ----
 * st[k][j] is state word k of lane j (transposed, so one vle32 loads
 * word k of every lane). Only lanes [0, vl) are read or written. */
typedef uint32_t sha256x16_t[8][SHA256_LANES];
void sha256x16_init(sha256x16_t st);
/* Compresses nblocks consecutive 64-byte blocks of every lane: lane j's
 * blocks start at base + j * lane_stride (lane_stride 0: all lanes read
 * the same blocks). The blocks are already padded. */
void sha256x16_blocks(sha256x16_t st, const uint8_t *base, size_t lane_stride,
                      size_t nblocks, size_t vl);
/* Hash chain in place on every lane: steps times h = SHA-256(h). */
void sha256x16_chain(sha256x16_t st, size_t steps, size_t vl);
void sha256x16_lane(const sha256x16_t st, unsigned lane, uint32_t h[8]);
void sha256x16_set_lane(sha256x16_t st, unsigned lane, const uint32_t h[8]);

/* ---- helpers and checks (sha256_kat.c) ---- */
void sha256_words_to_bytes(const uint32_t h[8], uint8_t out[32]);
void sha256_bytes_to_words(const uint8_t in[32], uint32_t h[8]);
/* Benchmark seeds: byte k of lane j's seed is (k + 17 j) mod 256. The
 * single-chain benchmarks start from lane 0's seed (bytes 0, 1, 2, ...). */
void bench_seed(unsigned lane, uint8_t *out, size_t n);
/* Benchmark message: x = x * 1103515245 + 12345 (32-bit, x0 = 12345),
 * byte = (x >> 16) & 0xff, as in sw/examples/hash_stream. */
void bench_message(uint8_t *buf, size_t n);
/* Known-answer tests of every implementation; fails the test on a
 * mismatch, prints one line per family otherwise. */
void bench_fips_kats(void);
/* Fails the test with "<what>" unless ok. */
void bench_require(int ok, const char *what);
/* Prints one result line for a measured region: cycles per unit (two
 * decimals), and units/s at 62.5 MHz (F2 today) and 100 MHz (target). */
void bench_print_rate(const char *what, uint64_t cycles, uint64_t instret,
                      uint64_t units, const char *unit, uint64_t bytes);

#endif /* SHA256_BENCH_H */
