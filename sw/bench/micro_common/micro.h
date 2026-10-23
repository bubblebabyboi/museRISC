/* Shared C driver code for the micro_* benchmarks (README.md here).
 *
 * Every measured region runs one kernel (an assembly leaf function in
 * the bench's kernels.S) for exactly `ops` operations: the kernel loop
 * runs `trips` times with a fixed number of operations unrolled per
 * trip, and ops = MICRO_ITERS (bench.json "iterations"), so the
 * harness's cycles/iteration is cycles per operation. A region is
 *
 *   warm-up (outside the window) -> sigil_perf_begin_id(id) -> kernel
 *   -> sigil_perf_end_id(id) -> MICRO line -> self-check
 *
 * and the program passes only if every kernel result matches a value
 * computed independently in C. */
#ifndef MICRO_H
#define MICRO_H

#include "sigil.h"

#ifndef MICRO_ITERS
#error "MICRO_ITERS must be defined (Makefile: -DMICRO_ITERS=$(BENCH_ITERATIONS))"
#endif

#define MICRO_UNUSED __attribute__((unused))

static int micro_failures;
static unsigned micro_nregions;

/* Loop trips for MICRO_ITERS operations at `unroll` per trip. An
 * iteration count that is not a multiple of `unroll` (an ITER= smoke
 * run) is rounded up; the MICRO line prints the exact ops. */
MICRO_UNUSED static uint64_t micro_trips(uint64_t unroll) {
  uint64_t t = ((uint64_t)MICRO_ITERS + unroll - 1) / unroll;
  return t ? t : 1;
}

MICRO_UNUSED static void micro_check(const char *label, const char *what,
                                     uint64_t got, uint64_t want) {
  if (got != want) {
    sigil_printf("MICRO MISMATCH %s %s: got 0x%lx, expected 0x%lx\n", label,
                 what, got, want);
    micro_failures++;
  }
}

MICRO_UNUSED static void micro_check_min(const char *label, const char *what,
                                         uint64_t got, uint64_t min) {
  if (got < min) {
    sigil_printf("MICRO MISMATCH %s %s: got %lu, expected at least %lu\n",
                 label, what, got, min);
    micro_failures++;
  }
}

/* The hardware-counter view of one region (what an F2 run reports):
 * mcycle/minstret over the region and cycles per operation. */
MICRO_UNUSED static void micro_report(unsigned id, const char *label,
                                      uint64_t ops, sigil_perf_t t) {
  uint64_t milli = ops ? (t.cycles * 1000 + ops / 2) / ops : 0;
  sigil_printf("MICRO region=%u %s ops=%lu cycles=%lu instret=%lu "
               "cycles/op=%lu.%03lu\n",
               id, label, ops, t.cycles, t.instret, milli / 1000,
               milli % 1000);
  micro_nregions++;
}

/* One measured region. `warm` runs first, outside the window (it warms
 * the kernel's I$ lines and data); `run` is the measured kernel call. */
#define MICRO_REGION(id, label, ops, warm, run) \
  do {                                          \
    warm;                                       \
    sigil_perf_begin_id(id);                    \
    run;                                        \
    sigil_perf_t t_ = sigil_perf_end_id(id);    \
    micro_report((id), (label), (ops), t_);     \
  } while (0)

/* Ends the program: the check line (bench.json "expect") and PASS only
 * if every region ran and every check matched. */
MICRO_UNUSED __attribute__((noreturn)) static void micro_finish(unsigned regions) {
  if (micro_nregions != regions) {
    sigil_printf("MICRO MISMATCH ran %u regions, expected %u\n",
                 micro_nregions, regions);
    micro_failures++;
  }
  if (micro_failures) {
    sigil_printf("MICRO %d check(s) failed\n", micro_failures);
    sigil_fail("micro benchmark self-check");
  }
  sigil_printf("MICRO CHECK OK %s iterations=%lu regions=%u\n", SIGIL_PROG,
               (uint64_t)MICRO_ITERS, regions);
  sigil_pass();
}

/* xorshift64* (deterministic: every run builds the same data). */
static uint64_t micro_rng_state = 0x9E3779B97F4A7C15ull;
MICRO_UNUSED static uint64_t micro_rand(void) {
  uint64_t x = micro_rng_state;
  x ^= x >> 12;
  x ^= x << 25;
  x ^= x >> 27;
  micro_rng_state = x;
  return x * 0x2545F4914F6CDD1Dull;
}

#endif /* MICRO_H */
