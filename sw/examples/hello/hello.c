/* hello: the smallest useful Sigil program.
 *
 * Prints over the UART, reads misa and the performance counters, and
 * checks things that must hold on this core:
 *   - misa reports RV64 with I, M, A, F, D, C and V
 *   - a counted loop of N iterations retires exactly 2N + 2
 *     instructions (see count_loop below)
 *   - cycles >= instructions (single-issue, in-order pipeline)
 *   - mtime (CLINT) ticks once per core clock, like mcycle
 * Returning 0 from main prints "SIGIL TEST PASS hello". */
#include "sigil.h"

/* Runs `n` iterations of a two-instruction loop between two
 * rdinstret reads. Retired between the reads: the first rdinstret
 * itself, the mv, and 2 per iteration -> 2n + 2. */
static uint64_t count_loop(uint64_t n, uint64_t *cycles) {
  uint64_t i0, i1, c0, c1;
  __asm__ volatile(
      "rdcycle   %2\n"
      "rdinstret %0\n"
      "mv        t0, %4\n"
      "1: addi   t0, t0, -1\n"
      "bnez      t0, 1b\n"
      "rdinstret %1\n"
      "rdcycle   %3\n"
      : "=&r"(i0), "=&r"(i1), "=&r"(c0), "=&r"(c1)
      : "r"(n)
      : "t0");
  *cycles = c1 - c0;
  return i1 - i0;
}

int main(void) {
  sigil_printf("Hello from Sigil!\n");

  /* misa: bit 63:62 = MXL (2 = RV64), bit i = extension 'A' + i. */
  uint64_t misa = sigil_csr_read(misa);
  sigil_printf("misa = 0x%016lx: RV64", (unsigned long)misa);
  for (int i = 0; i < 26; i++) {
    if (misa & (1UL << i)) sigil_putc((char)('A' + i));
  }
  sigil_putc('\n');
  SIGIL_CHECK((misa >> 62) == 2);
  const char *need = "IMAFDCV";
  for (const char *p = need; *p; p++) SIGIL_CHECK(misa & (1UL << (*p - 'A')));

  /* Exact instruction count of a known loop. */
  const uint64_t n = 1000;
  uint64_t cyc;
  uint64_t ins = count_loop(n, &cyc);
  sigil_printf("loop of %lu iterations: %lu instructions, %lu cycles\n",
               (unsigned long)n, (unsigned long)ins, (unsigned long)cyc);
  SIGIL_CHECK(ins == 2 * n + 2);
  SIGIL_CHECK(cyc >= ins);

  /* mtime and mcycle both count core clocks: over the same interval
   * they differ only by the few cycles between the reads. */
  uint64_t t0 = sigil_mtime(), c0 = sigil_rdcycle();
  sigil_delay_cycles(5000);
  uint64_t t1 = sigil_mtime(), c1 = sigil_rdcycle();
  uint64_t dt = t1 - t0, dc = c1 - c0;
  sigil_printf("5000-cycle delay: mtime +%lu, mcycle +%lu, time CSR %lu\n",
               (unsigned long)dt, (unsigned long)dc,
               (unsigned long)sigil_rdtime());
  SIGIL_CHECK(dc >= 5000 && dc < 6000);
  SIGIL_CHECK(dt + 64 > dc && dc + 64 > dt);

  /* Totals since reset (includes the startup code and the prints). */
  sigil_printf("total: %lu cycles, %lu instructions retired\n",
               (unsigned long)sigil_rdcycle(), (unsigned long)sigil_rdinstret());
  return 0;
}
