/* micro_pipe: one pipeline mechanism per region, in cycles per
 * operation (../micro_common/README.md). Kernels: kernels.S. Region
 * labels match bench.json. */
#include "micro.h"

#define U 256 /* operations per loop trip, kernels.S */

uint64_t k_empty(void);
uint64_t k_loop(uint64_t trips);
uint64_t k_alu32_dep(uint64_t trips, uint64_t x);
uint64_t k_alu32_indep(uint64_t trips, uint64_t x);
uint64_t k_alu16_dep(uint64_t trips, uint64_t x);
uint64_t k_alu32_straddle(uint64_t trips, uint64_t x);
uint64_t k_br_nt(uint64_t trips, uint64_t x);
uint64_t k_br_taken(uint64_t trips, uint64_t x);
uint64_t k_jal(uint64_t trips);
uint64_t k_call_ret(uint64_t trips);
uint64_t k_jalr_call_ret(uint64_t trips);
uint64_t k_brpat(uint64_t trips, const uint8_t *pattern);
uint64_t k_ld_dep(uint64_t trips, const uint64_t *p);
uint64_t k_ld_indep(uint64_t trips, const uint64_t *line);
uint64_t k_ld_use1(uint64_t trips, const uint64_t *w);
uint64_t k_ld_use2(uint64_t trips, const uint64_t *w);
uint64_t k_st(uint64_t trips, uint64_t *line, uint64_t v);
uint64_t k_rdcycle(uint64_t trips);
uint64_t k_rdtime(uint64_t trips);
uint64_t k_csrr(uint64_t trips);
uint64_t k_csrw(uint64_t trips, uint64_t v);
uint64_t k_csrrw(uint64_t trips, uint64_t v);
uint64_t k_fence(uint64_t trips);

static uint64_t line[8] __attribute__((aligned(64)));
static uint64_t self_ptr __attribute__((aligned(64)));

enum { PAT_NEVER, PAT_ALWAYS, PAT_ALT, PAT_RAND };

/* Pattern bytes for k_brpat: 1 = not taken, 0 = taken. PAT_RAND has
 * exactly half taken, in a shuffled order. Returns the not-taken count. */
static uint64_t make_pattern(uint8_t *p, uint64_t n, int kind) {
  uint64_t nt = 0;
  for (uint64_t i = 0; i < n; i++)
    p[i] = kind == PAT_NEVER ? 1 : kind == PAT_ALWAYS ? 0 : (uint8_t)(i & 1);
  if (kind == PAT_RAND) {
    for (uint64_t i = n - 1; i > 0; i--) { /* Fisher-Yates */
      uint64_t j = micro_rand() % (i + 1);
      uint8_t t = p[i];
      p[i] = p[j];
      p[j] = t;
    }
  }
  for (uint64_t i = 0; i < n; i++) nt += p[i];
  return nt;
}

int main(void) {
  const uint64_t trips = micro_trips(U), ops = trips * U;
  const uint64_t x0 = 0x0123456789abcdefull;
  uint64_t r;

  MICRO_REGION(1, "empty", ops, k_empty(), r = k_empty());
  micro_check("empty", "result", r, 0);

  /* The bare loop: one trip per operation. */
  MICRO_REGION(2, "loop", ops, k_loop(1), r = k_loop(ops));
  micro_check("loop", "result", r, 0);

  MICRO_REGION(3, "alu32_dep", ops, k_alu32_dep(1, 0), r = k_alu32_dep(trips, x0));
  micro_check("alu32_dep", "sum", r, x0 + 3 * ops);

  MICRO_REGION(4, "alu32_indep", ops, k_alu32_indep(1, 0), r = k_alu32_indep(trips, x0));
  micro_check("alu32_indep", "sum", r, 4 * (x0 + 3));

  MICRO_REGION(5, "alu16_dep", ops, k_alu16_dep(1, 0), r = k_alu16_dep(trips, x0));
  micro_check("alu16_dep", "sum", r, x0 + 3 * ops);

  MICRO_REGION(6, "alu32_straddle", ops, k_alu32_straddle(1, 0),
               r = k_alu32_straddle(trips, x0));
  micro_check("alu32_straddle", "sum", r, x0 + 3 * ops);

  MICRO_REGION(7, "br_nt", ops, k_br_nt(1, 0), r = k_br_nt(trips, x0));
  micro_check("br_nt", "taken count", r, 0);

  MICRO_REGION(8, "br_taken", ops, k_br_taken(1, 0), r = k_br_taken(trips, x0));
  micro_check("br_taken", "wrong-path addi count", r, 0);

  MICRO_REGION(9, "jal", ops, k_jal(1), r = k_jal(trips));
  micro_check("jal", "wrong-path addi count", r, 0);

  MICRO_REGION(10, "call_ret", ops, k_call_ret(1), r = k_call_ret(trips));
  micro_check("call_ret", "calls", r, ops);

  MICRO_REGION(11, "jalr_call_ret", ops, k_jalr_call_ret(1), r = k_jalr_call_ret(trips));
  micro_check("jalr_call_ret", "calls", r, ops);

  /* Branch patterns, 64 branches per trip. */
  {
    static const char *const names[] = {"brpat_never", "brpat_always", "brpat_alt",
                                        "brpat_rand"};
    const uint64_t ptrips = micro_trips(64), pops = ptrips * 64;
    uint8_t *pat = sigil_alloc(pops, 64);
    SIGIL_CHECK(pat != NULL);
    for (int k = PAT_NEVER; k <= PAT_RAND; k++) {
      uint64_t nt = make_pattern(pat, pops, k);
      MICRO_REGION(12 + k, names[k], pops, k_brpat(1, pat), r = k_brpat(ptrips, pat));
      micro_check(names[k], "not-taken count", r, nt);
    }
  }

  self_ptr = (uint64_t)(uintptr_t)&self_ptr;
  MICRO_REGION(16, "ld_dep", ops, k_ld_dep(1, &self_ptr), r = k_ld_dep(trips, &self_ptr));
  micro_check("ld_dep", "pointer", r, (uint64_t)(uintptr_t)&self_ptr);

  {
    uint64_t want = 0;
    for (int i = 0; i < 8; i++) {
      line[i] = micro_rand();
      want ^= line[i];
    }
    MICRO_REGION(17, "ld_indep", ops, k_ld_indep(1, line), r = k_ld_indep(trips, line));
    micro_check("ld_indep", "xor", r, want);

    want = ops / 2 * (line[0] + line[1]);
    MICRO_REGION(18, "ld_use1", ops, k_ld_use1(1, line), r = k_ld_use1(trips, line));
    micro_check("ld_use1", "sum", r, want);
    MICRO_REGION(19, "ld_use2", ops, k_ld_use2(1, line), r = k_ld_use2(trips, line));
    micro_check("ld_use2", "sum", r, want);

    const uint64_t v = 0x5a5a1234deadbeefull;
    MICRO_REGION(20, "st", ops, k_st(1, line, 0), r = k_st(trips, line, v));
    for (int i = 0; i < 8; i++) micro_check("st", "stored word", line[i], v);
  }

  MICRO_REGION(21, "rdcycle", ops, k_rdcycle(1), r = k_rdcycle(trips));
  micro_check_min("rdcycle", "last - first read", r, ops - 1);

  MICRO_REGION(22, "rdtime", ops, k_rdtime(1), r = k_rdtime(trips));
  micro_check_min("rdtime", "last - first read", r, ops - 1);

  {
    const uint64_t m = 0x0badc0ffee0ddf00ull, v = 0x1122334455667788ull;
    sigil_csr_write(mscratch, m);
    MICRO_REGION(23, "csrr", ops, k_csrr(1), r = k_csrr(trips));
    micro_check("csrr", "mscratch", r, m);

    MICRO_REGION(24, "csrw", ops, k_csrw(1, 0), r = k_csrw(trips, v));
    micro_check("csrw", "mscratch", sigil_csr_read(mscratch), v);

    sigil_csr_write(mscratch, m);
    MICRO_REGION(25, "csrrw", ops, k_csrrw(1, v), r = k_csrrw(trips, v));
    micro_check("csrrw", "register", r, v);
    micro_check("csrrw", "mscratch", sigil_csr_read(mscratch), m);
  }

  MICRO_REGION(26, "fence", ops, k_fence(1), r = k_fence(trips));
  micro_check("fence", "result", r, 0);

  micro_finish(26);
}
