/* F2 platform test (issues #62, #63, #65, #66, #67): runs on
 * sigil_fpga_top with the F2 RAM window (DDR4 64 GiB at PA 0x8000_0000,
 * HBM 16 GiB at PA 0x10_8000_0000; docs/LINUX_PLATFORM.md) -- in the
 * Verilator harness (fpga_top_tb_f2), XSIM (test_sigil_platform) and on
 * the F2 itself. Built with the soc-tests startup code and link script.
 *
 *  1. RTC (goldfish, 0x0010_1000): time is set by the platform (>= 2024)
 *     and advances; a guest write moves it; an alarm fires, raises PLIC
 *     source 11 and clears.
 *  2. Memory: one line at each window edge and at the 4 GiB / 32 GiB
 *     marks, DDR4 and HBM (64 GiB - 64 / 64 GiB = DDR4 end / HBM start),
 *     written with address-unique patterns, evicted from the D$ (64 KiB
 *     of other lines), read back.
 *  3. UART bursts the way Linux's 8250 driver writes ("ns16550a"): wait
 *     for THRE, then 16 bytes without looking at LSR. 64 lines
 *     "Bnn:<56 chars>" whose content the harness checks (#63).
 *  4. Mode word at MAILBOX (the host may load 8 bytes there; zero
 *     otherwise): bit 0 = read PA 0x14_8000_0000 (just above HBM; the
 *     bridge must answer zero and flag an out-of-window error);
 *     bits 15:8 = how to end: 0 power off (finisher 0x5555), 1 fail
 *     code 42 ((42 << 16) | 0x3333), 2 reboot once (0x7777; a counter
 *     at REBOOT_CNT, outside the image and flushed with FENCE.I,
 *     survives the SoC reset), then power off.
 * Prints "F2 PLATFORM PASS" (or "F2 PLATFORM FAIL <n>") before the
 * finisher write. */
#include <stdint.h>

#define UART ((volatile uint8_t *)0x10000000UL)
#define FINISHER ((volatile uint32_t *)0x00100000UL)
#define RTC ((volatile uint32_t *)0x00101000UL)
#define RTC64 ((volatile uint64_t *)0x00101000UL)
#define PLIC_PENDING ((volatile uint32_t *)0x0C001000UL)
#define MAILBOX ((volatile uint64_t *)0x80080000UL)
#define REBOOT_CNT ((volatile uint64_t *)0x80090000UL)
#define EVICT_BASE 0x80200000UL

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
static void fail(int n, const char *what, uint64_t a, uint64_t b) {
  fails++;
  puts_("F2 PLATFORM CHECK ");
  putc_((char)('0' + n));
  puts_(" ");
  puts_(what);
  puts_(" ");
  puthex(a);
  puts_(" ");
  puthex(b);
  puts_("\r\n");
}
static uint64_t pat(uint64_t a, int k) { return (a + 8u * (uint64_t)k) ^ 0xA5C3F00D12345678ull ^ ((uint64_t)k << 56); }
static uint64_t rdcycle(void) {
  uint64_t c;
  __asm__ volatile("rdcycle %0" : "=r"(c));
  return c;
}

static const uint64_t kLines[] = {
    /* DDR4 window: start, 256 MiB, 4 GiB edge, 32 GiB, end */
    0x80000000ull + 0x00800000ull, 0x80000000ull + 0x10000000ull,
    0x80000000ull + 0xFFFFFFC0ull, 0x80000000ull + 0x100000000ull,
    0x80000000ull + 0x800000000ull, 0x107FFFFFC0ull,
    /* HBM window: start, +64, 8 GiB, end */
    0x1080000000ull, 0x1080000040ull, 0x1280000000ull, 0x147FFFFFC0ull,
};
#define NLINES (sizeof kLines / sizeof kLines[0])

static void evict(void) {
  /* 64 KiB of other lines: 4x the 16 KiB D$, so every dirty line above
   * has been written back and is refilled from memory afterwards. */
  volatile uint64_t *e = (volatile uint64_t *)EVICT_BASE;
  for (uint32_t i = 0; i < 65536 / 8; i += 8) e[i] = i;
}

int main(void) {
  const uint64_t mode = *MAILBOX;
  puts_("F2 PLATFORM: start\r\n");

  /* 1. RTC. */
  {
    const uint64_t t0 = *RTC64;
    const uint32_t lo = RTC[0];
    const uint32_t hi = RTC[1];
    const uint64_t t1 = ((uint64_t)hi << 32) | lo;
    puts_("F2 PLATFORM: rtc ");
    puthex(t0);
    puts_("\r\n");
    if (t0 < 1704067200000000000ull) fail(1, "rtc before 2024", t0, 0);
    if (t1 <= t0) fail(1, "rtc not advancing", t0, t1);
    /* Guest write: +1 s, then read back. */
    const uint64_t set = t1 + 1000000000ull;
    RTC[1] = (uint32_t)(set >> 32);
    RTC[0] = (uint32_t)set;
    const uint64_t t2 = *RTC64;
    if (t2 < set || t2 > set + 100000000ull) fail(1, "rtc write", set, t2);
    /* Alarm 20 us ahead, interrupt enabled. */
    const uint64_t al = t2 + 20000;
    RTC[3] = (uint32_t)(al >> 32);
    RTC[2] = (uint32_t)al;
    RTC[4] = 1;
    if (RTC[6] != 1) fail(1, "alarm not armed", RTC[6], 0);
    const uint64_t c0 = rdcycle();
    while (RTC[6] != 0 && rdcycle() - c0 < 50000000ull) {
    }
    if (RTC[6] != 0) fail(1, "alarm never fired", *RTC64, al);
    if (!(PLIC_PENDING[0] & (1u << 11))) fail(1, "rtc irq not pending", PLIC_PENDING[0], 0);
    RTC[7] = 1;   /* CLEAR_INTERRUPT */
    RTC[4] = 0;
    if (PLIC_PENDING[0] & (1u << 11)) fail(1, "rtc irq not cleared", PLIC_PENDING[0], 0);
  }

  /* 2. Memory at the window edges, DDR4 and HBM. */
  puts_("F2 PLATFORM: memory\r\n");
  for (unsigned i = 0; i < NLINES; i++) {
    volatile uint64_t *p = (volatile uint64_t *)kLines[i];
    for (int k = 0; k < 8; k++) p[k] = pat(kLines[i], k);
  }
  evict();
  for (unsigned i = 0; i < NLINES; i++) {
    volatile uint64_t *p = (volatile uint64_t *)kLines[i];
    for (int k = 0; k < 8; k++) {
      const uint64_t v = p[k];
      if (v != pat(kLines[i], k)) fail(2, "mem", kLines[i] + 8u * k, v);
    }
  }

  /* 3. UART bursts (16 bytes per THRE, like Linux's 8250 driver). */
  puts_("F2 PLATFORM: uart\r\n");
  {
    char line[64];
    for (int n = 0; n < 64; n++) {
      line[0] = 'B';
      line[1] = (char)('0' + n / 10);
      line[2] = (char)('0' + n % 10);
      line[3] = ':';
      for (int j = 0; j < 56; j++) line[4 + j] = (char)('a' + (n * 7 + j) % 26);
      line[60] = '\r';
      line[61] = '\n';
      int i = 0;
      while (i < 62) {
        while ((UART[5] & 0x20) == 0) {
        }
        for (int b = 0; b < 16 && i < 62; b++) UART[0] = (uint8_t)line[i++];
      }
    }
  }

  /* 4. Optional out-of-window read, then end per the mode word. */
  if (mode & 1) {
    const uint64_t v = *(volatile uint64_t *)0x1480000000ull;
    if (v != 0) fail(4, "oob read", v, 0);
    puts_("F2 PLATFORM: oob read done\r\n");
  }
  const unsigned end = (unsigned)(mode >> 8) & 0xFF;
  if (fails == 0) {
    puts_("F2 PLATFORM PASS\r\n");
  } else {
    puts_("F2 PLATFORM FAIL\r\n");
  }
  while ((UART[5] & 0x40) == 0) {  /* TEMT: everything sent */
  }
  if (fails) {
    *FINISHER = (1u << 16) | 0x3333;
  } else if (end == 1) {
    *FINISHER = (42u << 16) | 0x3333;
  } else if (end == 2 && *REBOOT_CNT != 0x5EB007ull) {
    *REBOOT_CNT = 0x5EB007ull;
    __asm__ volatile("fence.i" ::: "memory");   /* write the D$ back */
    puts_("F2 PLATFORM: reboot\r\n");
    while ((UART[5] & 0x40) == 0) {
    }
    *FINISHER = 0x7777;
  } else {
    if (end == 2) {
      *REBOOT_CNT = 0;
      __asm__ volatile("fence.i" ::: "memory");
      puts_("F2 PLATFORM: rebooted once\r\n");
      while ((UART[5] & 0x40) == 0) {
      }
    }
    *FINISHER = 0x5555;
  }
  for (;;) __asm__ volatile("wfi");
}
