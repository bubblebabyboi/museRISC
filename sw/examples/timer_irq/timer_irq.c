/* timer_irq: CLINT machine-timer and software interrupts.
 *
 * The CLINT's mtime counts core clock cycles; the machine timer
 * interrupt is pending while mtime >= mtimecmp. The handler below
 * re-arms mtimecmp one PERIOD later each time, so the interrupt fires
 * periodically. Checks:
 *   1. masked (mstatus.MIE = 0): mip.MTIP goes pending, no trap taken
 *   2. enabled: exactly N_TICKS interrupts, each taken after its
 *      deadline and within MAX_LATENCY cycles of it, main() sleeping in
 *      wfi between them
 *   3. after sigil_timer_off(), no further timer interrupts
 *   4. a CLINT software interrupt (msip) is taken once and cleared */
#include "sigil.h"

#define PERIOD 2000      /* cycles between timer interrupts */
#define N_TICKS 10
#define MAX_LATENCY 1000 /* deadline -> handler entry, cycles (sim: ~200;
                            margin for DDR cache misses on F2) */

static volatile uint64_t ticks, soft_irqs, first_latency, worst_latency;
static volatile uint64_t deadline; /* current mtimecmp */
static volatile int late;

static void on_irq(uint64_t irq) {
  if (irq == SIGIL_IRQ_M_TIMER) {
    uint64_t now = sigil_mtime();
    if (now < deadline) late = -1; /* fired early: must never happen */
    uint64_t lat = now - deadline;
    if (ticks == 0) {
      first_latency = lat; /* the one held back by MIE = 0 */
    } else if (lat > worst_latency) {
      worst_latency = lat;
    }
    ticks++;
    deadline += PERIOD;
    sigil_set_mtimecmp(deadline); /* clears the pending interrupt */
  } else if (irq == SIGIL_IRQ_M_SOFT) {
    soft_irqs++;
    SIGIL_REG32(SIGIL_CLINT_MSIP) = 0; /* clear the source */
  }
}

int main(void) {
  sigil_set_irq_handler(on_irq);

  /* 1. Masked: let the deadline pass with MIE = 0. */
  sigil_irq_enable(SIGIL_MIE_MTIE);
  deadline = sigil_mtime() + 500;
  sigil_set_mtimecmp(deadline);
  while (sigil_mtime() < deadline + 100) {
  }
  SIGIL_CHECK(sigil_csr_read(mip) & SIGIL_MIE_MTIE); /* MTIP pending */
  SIGIL_CHECK(ticks == 0);

  /* 2. Enable: the pending interrupt is taken at once, then N_TICKS-1
   * more arrive every PERIOD cycles while we sleep. */
  uint64_t t0 = sigil_mtime();
  sigil_irq_global_enable();
  while (ticks < N_TICKS) sigil_wfi();
  sigil_timer_off();
  uint64_t elapsed = sigil_mtime() - t0;
  sigil_printf("%lu timer interrupts in %lu cycles; latency: first %lu "
               "(held by MIE=0), worst of the rest %lu cycles\n",
               (unsigned long)ticks, (unsigned long)elapsed,
               (unsigned long)first_latency, (unsigned long)worst_latency);
  SIGIL_CHECK(late == 0);
  SIGIL_CHECK(ticks == N_TICKS);
  /* The 1st fires on enable, the other N-1 PERIOD apart. */
  SIGIL_CHECK(elapsed >= (N_TICKS - 1) * PERIOD - 200);
  SIGIL_CHECK(elapsed <= (N_TICKS - 1) * PERIOD + MAX_LATENCY + 200);
  /* Handler entry within MAX_LATENCY of each deadline, except the
   * first, which waited for MIE on purpose. */
  SIGIL_CHECK(first_latency >= 100);
  SIGIL_CHECK(worst_latency <= MAX_LATENCY);

  /* 3. Timer off: nothing more for a while. */
  sigil_delay_cycles(5 * PERIOD);
  SIGIL_CHECK(ticks == N_TICKS);

  /* 4. Software interrupt via the CLINT msip register. */
  sigil_irq_enable(SIGIL_MIE_MSIE);
  SIGIL_REG32(SIGIL_CLINT_MSIP) = 1;
  for (int i = 0; i < 100 && soft_irqs == 0; i++) {
  }
  SIGIL_CHECK(soft_irqs == 1);
  SIGIL_CHECK((sigil_csr_read(mip) & SIGIL_MIE_MSIE) == 0);
  sigil_irq_global_disable();
  return 0;
}
