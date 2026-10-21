/* FPGA-top smoke test (issue #52): runs on sigil_fpga_top with RAM
 * behind the mbus->AXI4 bridge. Built with the soc-tests startup
 * code and link script (image at 0x8000_0000, stack below
 * 0x8010_0000).
 *  1. Memory: 512 KiB at 0x8020_0000 (32x the 16 KiB D$) written
 *     with 64-bit words, then overwritten in places with byte,
 *     halfword and word stores, then verified -- dirty lines are
 *     written back to and refilled from the AXI memory, with
 *     partial byte enables merged in the line.
 *  2. Virtual UART RX: reads one line from the 16550 (the host
 *     pushes it into the FPGA top's RX FIFO) and compares it with
 *     the expected text; the line is longer than the 16550's
 *     16-byte RX FIFO, so a dropped byte would show up.
 * Prints "FPGA SMOKE PASS" or "FPGA SMOKE FAIL <stage>". */
#include <stdint.h>

#define UART ((volatile uint8_t *)0x10000000UL)
#define MEM_BASE 0x80200000UL
#define MEM_WORDS (512u * 1024u / 8u)

static const char kExpect[] =
    "sigil-fpga-uart-rx 0123456789abcdefghijklmnopqrstuvwxyz "
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ the quick brown fox jumps over the lazy dog "
    "0123456789 !#$%&()*+,-./:;<=>?@[]^_{|}~ end";

static void putc(char c) {
  while ((UART[5] & 0x20) == 0) {
  }
  UART[0] = (uint8_t)c;
}
static void puts(const char *s) {
  while (*s) putc(*s++);
}
static int getc(void) {
  while ((UART[5] & 0x01) == 0) {
  }
  return UART[0];
}
static void fail(int stage) {
  puts("FPGA SMOKE FAIL ");
  putc((char)('0' + stage));
  puts("\r\n");
  for (;;) __asm__ volatile("wfi");
}
static uint64_t pat(uint64_t i) { return (i * 0x9E3779B97F4A7C15ull) ^ 0x5A5A0000A5A5ull; }

int main(void) {
  volatile uint64_t *d = (volatile uint64_t *)MEM_BASE;
  volatile uint32_t *w = (volatile uint32_t *)MEM_BASE;
  volatile uint16_t *h = (volatile uint16_t *)MEM_BASE;
  volatile uint8_t *b = (volatile uint8_t *)MEM_BASE;
  puts("FPGA SMOKE: memory\r\n");
  for (uint32_t i = 0; i < MEM_WORDS; i++) d[i] = pat(i);
  for (uint32_t i = 0; i < MEM_WORDS; i += 3) b[8 * i + 1] = (uint8_t)(i * 5u);
  for (uint32_t i = 0; i < MEM_WORDS; i += 5) h[4 * i + 2] = (uint16_t)(i * 7u);
  for (uint32_t i = 0; i < MEM_WORDS; i += 7) w[2 * i + 1] = i * 13u;
  for (uint32_t i = 0; i < MEM_WORDS; i++) {
    uint64_t e = pat(i);
    if (i % 3 == 0) e = (e & ~(0xFFull << 8)) | ((uint64_t)(uint8_t)(i * 5u) << 8);
    if (i % 5 == 0) e = (e & ~(0xFFFFull << 32)) | ((uint64_t)(uint16_t)(i * 7u) << 32);
    if (i % 7 == 0) e = (e & 0xFFFFFFFFull) | ((uint64_t)(i * 13u) << 32);
    if (d[i] != e) fail(1);
  }
  puts("FPGA SMOKE: memory ok\r\nFPGA SMOKE: uart rx\r\n");
  uint32_t n = 0;
  for (;;) {
    int c = getc();
    if (c == '\n') break;
    if (n >= sizeof(kExpect) - 1 || (char)c != kExpect[n]) fail(2);
    n++;
  }
  if (n != sizeof(kExpect) - 1) fail(3);
  puts("FPGA SMOKE: uart rx ok\r\nFPGA SMOKE PASS\r\n");
  return 0;
}
