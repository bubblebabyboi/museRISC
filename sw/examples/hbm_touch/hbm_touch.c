/* hbm_touch: the F2's 16 GiB of HBM, and DDR4 beyond 128 MiB, from
 * bare-metal C.
 *
 * On the F2 build (public AFI agfi-0c8aa56fde1a48495,
 * docs/LINUX_PLATFORM.md) the SoC's RAM is
 *   DDR4 64 GiB at 0x0_8000_0000 .. 0x10_7FFF_FFFF  (ECC; sigil_host
 *        zeroes all of it once per AFI load)
 *   HBM  16 GiB at 0x10_8000_0000 .. 0x14_7FFF_FFFF  (no ECC; not
 *        zeroed: it holds whatever was there until you write it)
 * Both are ordinary cacheable memory: a pointer is all it takes. The
 * SDK (link script, sigil_alloc) uses only the first 128 MiB of DDR4,
 * the window every simulator has, so the rest is yours to manage --
 * here with a tiny bump allocator over HBM.
 *
 * For a 256 KiB buffer (16 x the 16 KiB L1 D$, so the read pass comes
 * from memory, not from the cache) at the start of HBM, at the end of
 * HBM and in DDR4 at +32 GiB: write a pattern, read it back, print the
 * cycles per 64-byte line of each pass. Then check the first buffer
 * again (no aliasing between the three).
 *
 * Runs on the F2 and on fpga_top_tb_f2 (make -C sim fpgatop-f2-examples);
 * not on soc_rtl_tb or fpga_top_tb, whose RAM window is 128 MiB. */
#include "sigil.h"

#define F2_DDR4_BASE 0x0080000000UL
#define F2_DDR4_SIZE 0x1000000000UL /* 64 GiB */
#define F2_HBM_BASE  0x1080000000UL
#define F2_HBM_SIZE  0x0400000000UL /* 16 GiB */

#define BUF_BYTES (256UL * 1024)
#define WORDS     (BUF_BYTES / 8)
#define LINES     (BUF_BYTES / 64)

/* Bump allocator over HBM (no free), like sigil_alloc() over DDR4. */
static uintptr_t hbm_next = F2_HBM_BASE;
static void *hbm_alloc(size_t n, size_t align) {
  uintptr_t p = (hbm_next + align - 1) & ~(uintptr_t)(align - 1);
  if (p + n > F2_HBM_BASE + F2_HBM_SIZE) return NULL;
  hbm_next = p + n;
  return (void *)p;
}

/* A different 64-bit value for every address. */
static uint64_t pattern(uintptr_t a) { return (a * 0x9E3779B97F4A7C15UL) ^ 0x5167UL; }

static void fill(volatile uint64_t *p) {
  for (uint64_t i = 0; i < WORDS; i++) p[i] = pattern((uintptr_t)&p[i]);
}

static uint64_t count_bad(volatile uint64_t *p) {
  uint64_t bad = 0;
  for (uint64_t i = 0; i < WORDS; i++) bad += p[i] != pattern((uintptr_t)&p[i]);
  return bad;
}

static uint64_t touch(const char *what, volatile uint64_t *p) {
  uint64_t t0 = sigil_rdcycle();
  fill(p);
  uint64_t t1 = sigil_rdcycle();
  uint64_t bad = count_bad(p);
  uint64_t t2 = sigil_rdcycle();
  sigil_printf("%-9s 0x%010lx: write %lu, read %lu cycles per line, %lu bad words\n", what,
               (unsigned long)(uintptr_t)p, (unsigned long)((t1 - t0) / LINES),
               (unsigned long)((t2 - t1) / LINES), (unsigned long)bad);
  return bad;
}

int main(void) {
  volatile uint64_t *hbm = hbm_alloc(BUF_BYTES, 64);
  volatile uint64_t *hbm_end = (volatile uint64_t *)(F2_HBM_BASE + F2_HBM_SIZE - BUF_BYTES);
  volatile uint64_t *ddr4 = (volatile uint64_t *)(F2_DDR4_BASE + (32UL << 30));
  SIGIL_CHECK(hbm == (volatile uint64_t *)F2_HBM_BASE);
  SIGIL_CHECK(hbm_alloc(F2_HBM_SIZE, 64) == NULL); /* more than is left */

  sigil_printf("%lu KiB per buffer, %lu lines\n", (unsigned long)(BUF_BYTES >> 10),
               (unsigned long)LINES);
  SIGIL_CHECK(touch("HBM", hbm) == 0);
  SIGIL_CHECK(touch("HBM end", hbm_end) == 0);
  SIGIL_CHECK(touch("DDR4 32G", ddr4) == 0);
  SIGIL_CHECK(count_bad(hbm) == 0); /* still intact after the other two */
  return 0;
}
