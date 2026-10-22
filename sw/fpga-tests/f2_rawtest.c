/* F2 read-after-write ordering test (issue #73 oops hunt, AXI lens).
 * Runs on sigil_fpga_top (fpga_top_tb / fpga_top_tb_f2, or the F2
 * itself) with the L1 caches on. Every check is a read of DDR data
 * that the core wrote shortly before through a D$ write-back, the
 * case where an AXI path without read/write channel ordering (a
 * refill AR overtaking the write-back AW/W of the same line, or an
 * early B response) would return the old data:
 *
 *  1. Evict, then refill the same line: write line A, load or store
 *     four other lines of A's D$ set (64 sets x 4 ways x 64 B: same
 *     set every 4 KiB), so the dirty A is written back, then read A
 *     at once (refill) and check all 8 words. Sets, lines and the
 *     load/store mix change every iteration.
 *  2. FENCE.I: write a tiny function (li a0, imm; ret) into a code
 *     buffer through the D$, FENCE.I (write back every dirty D$ line,
 *     invalidate the I$), call it: the I$ refill must see the new
 *     immediate, as for a Linux exec of a page-cache page.
 *  3. AMOs on lines just evicted: amoadd.d / amoswap.d / lr.d+sc.d on
 *     a word whose line was written back a moment before.
 *
 * Prints "F2 RAW PASS" or "F2 RAW FAIL <phase> <addr> <got> <exp>"
 * and powers off through the test finisher (0x5555 pass,
 * (1 << 16) | 0x3333 fail). */
#include <stdint.h>

#define UART ((volatile uint8_t *)0x10000000UL)
#define FINISHER ((volatile uint32_t *)0x00100000UL)
#define AREA 0x80400000UL /* 4 MiB test area */
#define AREA_LINES (4u * 1024u * 1024u / 64u)
#define CODE 0x80300000UL /* code buffers, 16 x 64 B */

#ifndef ITERS
#define ITERS 3000
#endif
#ifndef CODE_ITERS
#define CODE_ITERS 400
#endif
#ifndef AMO_ITERS
#define AMO_ITERS 600
#endif

static void putc_(char c) {
  while ((UART[5] & 0x20) == 0) {
  }
  UART[0] = (uint8_t)c;
}
static void puts_(const char *s) {
  while (*s) putc_(*s++);
}
static void puthex(uint64_t v) {
  puts_("0x");
  for (int i = 60; i >= 0; i -= 4) putc_("0123456789abcdef"[(v >> i) & 15]);
}
static int fails;
static void fail(int phase, uint64_t a, uint64_t got, uint64_t exp) {
  if (fails++ < 8) {
    puts_("F2 RAW FAIL ");
    putc_((char)('0' + phase));
    putc_(' ');
    puthex(a);
    putc_(' ');
    puthex(got);
    putc_(' ');
    puthex(exp);
    puts_("\r\n");
  }
}
static uint64_t rng = 0x243F6A8885A308D3ull;
static uint64_t rnd(void) {
  rng ^= rng << 13;
  rng ^= rng >> 7;
  rng ^= rng << 17;
  return rng;
}
static uint64_t pat(uint64_t a, uint64_t it) {
  return (a * 0x9E3779B97F4A7C15ull) ^ (it << 40) ^ 0xC0FFEE0000000000ull;
}
/* Line address of way-alias k (0..7) of set s in the area. */
static volatile uint64_t *line(unsigned s, unsigned k) {
  return (volatile uint64_t *)(AREA + 4096ul * k + 64ul * s);
}

int main(void) {
  puts_("F2 RAW: start\r\n");

  /* 1. Evict, then refill the same line. */
  for (uint64_t it = 1; it <= ITERS; it++) {
    const unsigned s = (unsigned)(rnd() & 63);
    const unsigned base = (unsigned)(rnd() & 7) * 16; /* 0..112 KiB */
    const unsigned k0 = (unsigned)(rnd() & 7);
    volatile uint64_t *a = (volatile uint64_t *)(AREA + 4096ul * (base + k0) + 64ul * s);
    for (int w = 0; w < 8; w++) a[w] = pat((uint64_t)&a[w], it);
    /* Four other lines of the same set: A (dirty) is written back. */
    const uint64_t mix = rnd();
    for (unsigned j = 1; j <= 4; j++) {
      volatile uint64_t *b =
          (volatile uint64_t *)(AREA + 4096ul * (base + ((k0 + j) & 7)) + 64ul * s);
      if ((mix >> j) & 1) {
        b[j & 7] = pat((uint64_t)&b[j & 7], it); /* dirty victim later */
      } else {
        (void)b[j & 7];
      }
    }
    /* Refill A right away; check every word. */
    for (int w = 0; w < 8; w++) {
      const uint64_t v = a[w];
      if (v != pat((uint64_t)&a[w], it)) fail(1, (uint64_t)&a[w], v, pat((uint64_t)&a[w], it));
    }
    /* Words of the other lines written in this iteration. */
    for (unsigned j = 1; j <= 4; j++) {
      volatile uint64_t *b =
          (volatile uint64_t *)(AREA + 4096ul * (base + ((k0 + j) & 7)) + 64ul * s);
      if ((mix >> j) & 1) {
        const uint64_t v = b[j & 7];
        if (v != pat((uint64_t)&b[j & 7], it)) fail(1, (uint64_t)&b[j & 7], v, pat((uint64_t)&b[j & 7], it));
      }
    }
  }
  puts_("F2 RAW: evict/refill done\r\n");

  /* 2. Code written through the D$, FENCE.I, executed from the I$. */
  for (uint32_t it = 1; it <= CODE_ITERS; it++) {
    const unsigned slot = (unsigned)(rnd() & 15);
    volatile uint32_t *c = (volatile uint32_t *)(CODE + 64ul * slot);
    const uint32_t imm = (it * 37u + slot) & 0x7FF; /* addi a0, zero, imm */
    c[0] = (imm << 20) | (10u << 7) | 0x13u;
    c[1] = 0x00008067u; /* ret */
    /* Dirty some unrelated lines too, so FENCE.I writes back several. */
    for (unsigned j = 0; j < 8; j++) *line((unsigned)(rnd() & 63), (unsigned)(rnd() & 7)) = it;
    __asm__ volatile("fence.i" ::: "memory");
    uint64_t r;
    __asm__ volatile("jalr ra, 0(%1)\n\tmv %0, a0" : "=r"(r) : "r"(c) : "ra", "a0", "memory");
    if (r != imm) fail(2, (uint64_t)c, r, imm);
  }
  puts_("F2 RAW: fence.i done\r\n");

  /* 3. AMOs on just-evicted lines. */
  for (uint64_t it = 1; it <= AMO_ITERS; it++) {
    const unsigned s = (unsigned)(rnd() & 63);
    const unsigned k0 = (unsigned)(rnd() & 7);
    volatile uint64_t *a = line(s, k0);
    a[3] = it * 1000u;
    for (unsigned j = 1; j <= 4; j++) (void)line(s, (k0 + j) & 7)[0];
    uint64_t old;
    const uint64_t add = it;
    __asm__ volatile("amoadd.d %0, %2, (%1)" : "=r"(old) : "r"(&a[3]), "r"(add) : "memory");
    if (old != it * 1000u) fail(3, (uint64_t)&a[3], old, it * 1000u);
    for (unsigned j = 1; j <= 4; j++) (void)line(s, (k0 + j) & 7)[1];
    uint64_t v, sc;
    __asm__ volatile(
        "1: lr.d %0, (%2)\n\t"
        "addi %0, %0, 1\n\t"
        "sc.d %1, %0, (%2)\n\t"
        "bnez %1, 1b"
        : "=&r"(v), "=&r"(sc)
        : "r"(&a[3])
        : "memory");
    if (v != it * 1000u + it + 1) fail(3, (uint64_t)&a[3], v, it * 1000u + it + 1);
    for (unsigned j = 1; j <= 4; j++) (void)line(s, (k0 + j) & 7)[2];
    if (a[3] != it * 1000u + it + 1) fail(3, (uint64_t)&a[3], a[3], it * 1000u + it + 1);
  }
  puts_("F2 RAW: amo done\r\n");

  if (fails) {
    puts_("F2 RAW FAIL total ");
    puthex((uint64_t)fails);
    puts_("\r\n");
    *FINISHER = (1u << 16) | 0x3333u;
  } else {
    puts_("F2 RAW PASS\r\n");
    *FINISHER = 0x5555u;
  }
  for (;;) __asm__ volatile("wfi");
  return 0;
}
