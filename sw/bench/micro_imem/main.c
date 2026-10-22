/* micro_imem: instruction fetch over a sweep of code footprints, in
 * cycles per instruction (../micro_common/README.md). Kernels:
 * kernels.S. Region labels match bench.json.
 *
 * Each region runs straight-line 32-bit addi code of S bytes (the last
 * S bytes of a 32 KiB block, then ret) over and over: MICRO_ITERS
 * instructions in MICRO_ITERS / (S / 4) passes, after one warm-up pass.
 * Per pass the driver adds a jalr, the ret and two loop instructions. */
#include "micro.h"

uint64_t k_empty(void);
uint64_t k_ifoot(uint64_t trips, uint64_t count, const void *entry);
extern const uint8_t k_block[], k_block_end[];

int main(void) {
  static const struct {
    const char *label;
    uint32_t kib;
  } sizes[] = {
      {"ifoot_1k", 1},   {"ifoot_2k", 2},   {"ifoot_3k", 3},   {"ifoot_4k", 4},
      {"ifoot_6k", 6},   {"ifoot_8k", 8},   {"ifoot_12k", 12}, {"ifoot_16k", 16},
      {"ifoot_24k", 24}, {"ifoot_32k", 32},
  };
  const unsigned n = sizeof sizes / sizeof sizes[0];
  uint64_t r;

  SIGIL_CHECK(k_block_end - k_block == 32 * 1024);
  MICRO_REGION(1, "empty", MICRO_ITERS, k_empty(), r = k_empty());
  micro_check("empty", "result", r, 0);

  for (unsigned k = 0; k < n; k++) {
    const uint64_t per_pass = sizes[k].kib * 1024 / 4;
    const uint64_t trips = micro_trips(per_pass), ops = trips * per_pass;
    const uint8_t *entry = k_block_end - sizes[k].kib * 1024;
    MICRO_REGION(2 + k, sizes[k].label, ops, k_ifoot(1, 0, entry),
                 r = k_ifoot(trips, 0, entry));
    micro_check(sizes[k].label, "addi count", r, ops);
  }

  micro_finish(1 + n);
}
