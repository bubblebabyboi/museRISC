/* Starting point for a Sigil bare-metal program (docs/PROGRAMMING.md).
 * Runs in M-mode at 0x8000_0000 with the FPU and vector unit enabled.
 * Return 0 from main() to print "SIGIL TEST PASS <name>"; any other
 * value, a failed SIGIL_CHECK() or an unexpected trap prints
 * "SIGIL TEST FAIL <name>: ..." instead. */
#include "sigil.h"

int main(void) {
  sigil_perf_t start = sigil_perf_now();

  volatile uint64_t n = 100; /* volatile: GCC would fold the loop */
  uint64_t sum = 0;
  for (uint64_t i = 1; i <= n; i++) sum += i;

  sigil_perf_t t = sigil_perf_since(start);
  sigil_printf("sum(1..100) = %lu in %lu cycles, %lu instructions\n",
               (unsigned long)sum, (unsigned long)t.cycles,
               (unsigned long)t.instret);
  SIGIL_CHECK(sum == 5050);
  return 0;
}
