/* micro_dmem: data-side memory hierarchy in cycles per load/store
 * (../micro_common/README.md). Kernels: kernels.S. Region labels match
 * bench.json.
 *
 * Pointer chase: one node per 64-byte line over a working set of W
 * bytes, linked in a random cyclic order (Sattolo) or in address order.
 * Before each chase region the D$ is cleaned (FENCE.I writes back every
 * dirty line, so no victim in the region is dirty) and the chain is
 * walked first (8 passes for W <= 32 KiB, 1 pass above) so the region
 * sees the steady state. Streams: 64 KiB buffers (4x the default D$),
 * one warm-up pass, then the region continues at the buffer start. The
 * expected results are computed in C before the warm-up, so nothing
 * but the kernels touches the D$ between the warm-up and the region. */
#include "micro.h"

uint64_t k_empty(void);
uint64_t k_chase(uint64_t trips, uint64_t *p);
uint64_t k_stream_ld(uint64_t trips, uint64_t *pos, uint64_t *base, uint64_t *end);
uint64_t k_stream_st(uint64_t trips, uint64_t *pos, uint64_t *base, uint64_t *end,
                     uint64_t v);

#define LINE 64
#define CHASE_MAX (256 * 1024)
#define STREAM_BYTES (64 * 1024)
#define STREAM_WORDS (STREAM_BYTES / 8)
#define STREAM_TRIP_WORDS 64 /* 8 lines per kernel trip */

static uint8_t *chase_buf;
static uint32_t *nxt;

static uint64_t *node(uint32_t i) { return (uint64_t *)(chase_buf + (uint64_t)i * LINE); }

/* Links n nodes in one cycle: random order (Sattolo) or address order. */
static void chase_build(uint32_t n, int random) {
  for (uint32_t i = 0; i < n; i++) nxt[i] = random ? i : (i + 1) % n;
  if (random) {
    for (uint32_t i = n - 1; i > 0; i--) {
      uint32_t j = (uint32_t)(micro_rand() % i), t = nxt[i];
      nxt[i] = nxt[j];
      nxt[j] = t;
    }
  }
  for (uint32_t i = 0; i < n; i++) *node(i) = (uint64_t)(uintptr_t)node(nxt[i]);
}

static uint32_t walk(uint32_t i, uint64_t steps) {
  while (steps--) i = nxt[i];
  return i;
}

static void chase_region(unsigned id, const char *label, uint32_t kib, int random) {
  const uint32_t n = kib * 1024 / LINE;
  const uint64_t trips = micro_trips(64), ops = trips * 64;
  const uint64_t warm = ((kib <= 32 ? 8 : 1) * (uint64_t)n + 63) / 64; /* trips */
  chase_build(n, random);
  uint32_t len = 0, i = 0; /* the chain is one cycle through all n nodes */
  do {
    i = nxt[i];
    len++;
  } while (i != 0 && len <= n);
  micro_check(label, "cycle length", len, n);
  const uint32_t want_warm = walk(0, warm * 64), want = walk(want_warm, ops);
  sigil_fence_i(); /* clean the D$: no dirty victim in the region */
  uint64_t p = 0, q = 0;
  MICRO_REGION(id, label, ops, p = k_chase(warm, node(0)),
               q = k_chase(trips, (uint64_t *)(uintptr_t)p));
  micro_check(label, "node after warm-up", p, (uint64_t)(uintptr_t)node(want_warm));
  micro_check(label, "node after region", q, (uint64_t)(uintptr_t)node(want));
}

static uint64_t pattern(uint64_t word) { return (word + 1) * 0x9E3779B97F4A7C15ull; }

int main(void) {
  static const struct {
    const char *label;
    uint32_t kib;
    int random;
  } chases[] = {
      {"chase_rand_1k", 1, 1},     {"chase_rand_2k", 2, 1},     {"chase_rand_4k", 4, 1},
      {"chase_rand_8k", 8, 1},     {"chase_rand_12k", 12, 1},   {"chase_rand_16k", 16, 1},
      {"chase_rand_20k", 20, 1},   {"chase_rand_24k", 24, 1},   {"chase_rand_32k", 32, 1},
      {"chase_rand_64k", 64, 1},   {"chase_rand_128k", 128, 1}, {"chase_rand_256k", 256, 1},
      {"chase_seq_4k", 4, 0},      {"chase_seq_8k", 8, 0},      {"chase_seq_16k", 16, 0},
      {"chase_seq_32k", 32, 0},
  };
  const unsigned nchase = sizeof chases / sizeof chases[0];
  const uint64_t trips = micro_trips(STREAM_TRIP_WORDS), ops = trips * STREAM_TRIP_WORDS;
  const uint64_t pass = STREAM_WORDS / STREAM_TRIP_WORDS; /* trips per buffer pass */
  uint64_t r;

  chase_buf = sigil_alloc(CHASE_MAX, 4096);
  nxt = sigil_alloc(CHASE_MAX / LINE * sizeof(uint32_t), 64);
  uint64_t *sld = sigil_alloc(STREAM_BYTES, 4096);
  uint64_t *sst = sigil_alloc(STREAM_BYTES, 4096);
  SIGIL_CHECK(chase_buf && nxt && sld && sst);

  MICRO_REGION(1, "empty", ops, k_empty(), r = k_empty());
  micro_check("empty", "result", r, 0);

  for (unsigned k = 0; k < nchase; k++)
    chase_region(2 + k, chases[k].label, chases[k].kib, chases[k].random);

  /* Load stream: the region reads `ops` words from the buffer start;
   * expected: the xor of the last line it reads. */
  {
    const unsigned id = 2 + nchase;
    for (uint64_t w = 0; w < STREAM_WORDS; w++) sld[w] = pattern(w);
    const uint64_t last = (ops / 8 - 1) % (STREAM_WORDS / 8);
    uint64_t want = 0;
    for (int w = 0; w < 8; w++) want ^= pattern(last * 8 + (uint64_t)w);
    sigil_fence_i();
    MICRO_REGION(id, "stream_ld", ops, k_stream_ld(pass, sld, sld, sld + STREAM_WORDS),
                 r = k_stream_ld(trips, sld, sld, sld + STREAM_WORDS));
    micro_check("stream_ld", "xor of the last line", r, want);
  }

  /* Store stream: the warm-up pass writes tag1 everywhere (all lines
   * dirty), the region writes tag2 to its `ops` words from the start. */
  {
    const unsigned id = 3 + nchase;
    const uint64_t tag1 = 0x1111111111111111ull, tag2 = 0x2222222222222222ull;
    MICRO_REGION(id, "stream_st", ops,
                 k_stream_st(pass, sst, sst, sst + STREAM_WORDS, tag1),
                 r = k_stream_st(trips, sst, sst, sst + STREAM_WORDS, tag2));
    uint64_t bad = 0;
    for (uint64_t w = 0; w < STREAM_WORDS; w++)
      bad += sst[w] != ((w < ops || ops >= STREAM_WORDS) ? tag2 : tag1);
    micro_check("stream_st", "words with the wrong tag", bad, 0);
    micro_check("stream_st", "end position", r,
                (uint64_t)(uintptr_t)(sst + ops % STREAM_WORDS));
  }

  micro_finish(3 + nchase);
}
