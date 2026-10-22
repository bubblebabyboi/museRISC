/* F2 memory test from the core (issues #65, #66): sparse address test
 * over all of DDR4 (PA 0x8000_0000 + 64 GiB) and HBM (PA 0x10_8000_0000
 * + 16 GiB), then load latency and sequential read rate of each.
 * The full-range pass at AXI speed is the host's job (sigil_host
 * --memtest, the CL memory engine); this one checks the whole path
 * from the core: L1 refills / write-backs, the bridge's 80 GiB window,
 * the SmartConnect, the SLR crossings and both memories.
 *
 * Sparse test: one 64-byte line per STRIDE (default 64 KiB) at a
 * rotating line offset inside each block, eight address-unique 64-bit
 * words; all lines written first (the D$ write-back evicts them long
 * before the verify pass), then all verified.
 * Latency: NLAT cold line refills per memory, each timed with rdcycle
 * around a load (the D$ blocks on a miss); lines 1 MiB + 64 B apart
 * so every load misses, read-only so no victim write-back.
 * Read rate: 4 MiB read sequentially (one 64-bit load per line).
 *
 * Mailbox (64-bit word at MAILBOX, loaded by the host; zero = defaults):
 *   bits 7:0   log2(STRIDE), default 16 (64 KiB)
 *   bits 15:8  log2(NLAT), default 12 (4096 samples)
 *   bit 16     skip HBM
 * Ends with "F2 MEMTEST PASS" / "F2 MEMTEST FAIL" and the test finisher
 * (0x5555, or (1 << 16) | 0x3333 on failure). */
#include <stdint.h>

#define UART ((volatile uint8_t *)0x10000000UL)
#define FINISHER ((volatile uint32_t *)0x00100000UL)
#define MAILBOX ((volatile uint64_t *)0x80080000UL)

#define DDR_BASE 0x80000000ull
#define DDR_SIZE 0x1000000000ull   /* 64 GiB */
#define HBM_BASE 0x1080000000ull
#define HBM_SIZE 0x400000000ull    /* 16 GiB */
/* Keep clear of the image, stack and mailbox (first 16 MiB of DDR4). */
#define DDR_SKIP 0x1000000ull

static void putc_(char c) {
  while ((UART[5] & 0x20) == 0) {
  }
  UART[0] = (uint8_t)c;
}
static void puts_(const char *s) {
  while (*s) putc_(*s++);
}
static void putu(uint64_t v) {
  char b[24];
  int n = 0;
  do {
    b[n++] = (char)('0' + v % 10);
    v /= 10;
  } while (v);
  while (n) putc_(b[--n]);
}
static void puthex(uint64_t v) {
  puts_("0x");
  for (int i = 60; i >= 0; i -= 4) putc_("0123456789abcdef"[(v >> i) & 15]);
}
static uint64_t rdcycle(void) {
  uint64_t c;
  __asm__ volatile("rdcycle %0" : "=r"(c));
  return c;
}
static uint64_t pat(uint64_t a) { return a ^ 0x5A5AC3C3F00FF00Full ^ (a << 23); }

static uint64_t line_at(uint64_t base, uint64_t i, unsigned sh) {
  const uint64_t lines = (1ull << sh) / 64;
  return base + (i << sh) + ((i * 37u) % lines) * 64;
}

static int sparse(const char *name, uint64_t base, uint64_t size, uint64_t skip, unsigned sh) {
  const uint64_t n = size >> sh;
  uint64_t bad = 0, first = 0, t0 = rdcycle();
  for (uint64_t i = 0; i < n; i++) {
    const uint64_t a = line_at(base, i, sh);
    if (a - base < skip) continue;
    volatile uint64_t *p = (volatile uint64_t *)a;
    for (int k = 0; k < 8; k++) p[k] = pat(a + 8u * (uint64_t)k);
  }
  const uint64_t t1 = rdcycle();
  for (uint64_t i = 0; i < n; i++) {
    const uint64_t a = line_at(base, i, sh);
    if (a - base < skip) continue;
    volatile uint64_t *p = (volatile uint64_t *)a;
    for (int k = 0; k < 8; k++) {
      const uint64_t w = a + 8u * (uint64_t)k;
      if (p[k] != pat(w)) {
        if (bad++ == 0) first = w;
      }
    }
  }
  const uint64_t t2 = rdcycle();
  puts_("MEMTEST ");
  puts_(name);
  puts_(" points ");
  putu(n);
  puts_(" stride ");
  putu(1ull << sh);
  puts_(" errors ");
  putu(bad);
  if (bad) {
    puts_(" first ");
    puthex(first);
  }
  puts_(" write_cycles ");
  putu(t1 - t0);
  puts_(" verify_cycles ");
  putu(t2 - t1);
  puts_("\r\n");
  return bad != 0;
}

static void latency(const char *name, uint64_t base, unsigned nlat_sh) {
  const uint64_t n = 1ull << nlat_sh;
  uint64_t mn = ~0ull, mx = 0, sum = 0, acc = 0;
  /* Read 64 KiB elsewhere first: the D$ then holds only clean lines, so
   * no timed refill includes a victim write-back. */
  for (uint64_t off = 0; off < 0x10000; off += 64)
    acc += *(volatile uint64_t *)(base + 0x7000000ull + off);
  for (uint64_t i = 0; i < n; i++) {
    const uint64_t a = base + i * (0x100000ull + 64);
    uint64_t t0, t1, v;
    __asm__ volatile(
        "rdcycle %0\n\t"
        "ld %1, 0(%3)\n\t"
        "add %1, %1, zero\n\t"
        "rdcycle %2\n\t"
        : "=&r"(t0), "=&r"(v), "=&r"(t1)
        : "r"(a)
        : "memory");
    acc += v;
    const uint64_t d = t1 - t0;
    sum += d;
    if (d < mn) mn = d;
    if (d > mx) mx = d;
  }
  /* Hit latency of the same sequence (now cached lines, last 64). */
  uint64_t hit = 0;
  {
    const uint64_t a = base + (n - 1) * (0x100000ull + 64);
    uint64_t t0, t1, v;
    __asm__ volatile(
        "ld %1, 0(%3)\n\t"
        "rdcycle %0\n\t"
        "ld %1, 0(%3)\n\t"
        "add %1, %1, zero\n\t"
        "rdcycle %2\n\t"
        : "=&r"(t0), "=&r"(v), "=&r"(t1)
        : "r"(a)
        : "memory");
    hit = t1 - t0;
    acc += v;
  }
  /* Sequential read rate: 4 MiB, one load per 64-byte line. */
  const uint64_t sb = base + 0x40000000ull;
  const uint64_t r0 = rdcycle();
  for (uint64_t off = 0; off < (4u << 20); off += 64) acc += *(volatile uint64_t *)(sb + off);
  const uint64_t r1 = rdcycle();
  puts_("LATENCY ");
  puts_(name);
  puts_(" refill_cycles min ");
  putu(mn);
  puts_(" avg_x100 ");
  putu(sum * 100 / n);
  puts_(" max ");
  putu(mx);
  puts_(" n ");
  putu(n);
  puts_(" hit_cycles ");
  putu(hit);
  puts_(" seq_read_4MiB_cycles ");
  putu(r1 - r0);
  puts_(" (");
  putu(acc & 1);
  puts_(")\r\n");
}

int main(void) {
  const uint64_t mb = *MAILBOX;
  unsigned sh = (unsigned)(mb & 0xFF);
  unsigned nlat = (unsigned)((mb >> 8) & 0xFF);
  const int skip_hbm = (int)((mb >> 16) & 1);
  if (sh == 0) sh = 16;
  if (nlat == 0) nlat = 12;
  if (sh < 6) sh = 6;
  puts_("F2 MEMTEST: start\r\n");
  int fail = 0;
  fail |= sparse("ddr", DDR_BASE, DDR_SIZE, DDR_SKIP, sh);
  if (!skip_hbm) fail |= sparse("hbm", HBM_BASE, HBM_SIZE, 0, sh);
  latency("ddr", DDR_BASE + 0x100000000ull, nlat);
  if (!skip_hbm) latency("hbm", HBM_BASE + 0x40000000ull, nlat);
  puts_(fail ? "F2 MEMTEST FAIL\r\n" : "F2 MEMTEST PASS\r\n");
  while ((UART[5] & 0x40) == 0) {
  }
  *FINISHER = fail ? ((1u << 16) | 0x3333) : 0x5555;
  for (;;) __asm__ volatile("wfi");
}
