/* On-core SoC proof of the streaming hash engine (issue #6): runs on
 * the in-house core inside sigil_soc_top, streams messages into
 * sigil_crypto over MMIO (HDATA stores issued back to back, so the
 * AXI write backpressure through sigil_crypto_bridge is
 * exercised), and reports over the RTL 16550 UART. Expected values
 * come from Python hashlib / sw/hash_kat.py (Keccak-256), and the
 * message generator mirrors hash_kat.message().
 *
 * Checks (stage number in FAIL lines):
 *   1  SHA-512("abc")                       (FIPS 180-4 vector)
 *   2  SHA-512 of a 1000-byte message        (8 blocks, 0-byte tail)
 *   3  SHA3-256 of a 137-byte message        (rate + 1)
 *   4  Keccak-256("abc")                     (published vector)
 *   5  SHAKE256, 3-byte msg, 200-byte output (one squeeze)
 *   6  HSTATUS.err clear after all of the above
 * Builds with sw/soc-tests/crt.S + link.ld (shared, unmodified). */
#include <stdint.h>

#include "../sigil_crypto.h"

#define UART ((volatile uint8_t *)0x10000000UL)
#define REG(a) (*(volatile uint32_t *)(a))

static void putc(char c) {
  while ((UART[5] & 0x20) == 0) {
  }
  UART[0] = (uint8_t)c;
}
static void puts(const char *s) {
  while (*s) putc(*s++);
}
static void puthex(uint64_t v) {
  for (int i = 60; i >= 0; i -= 4) putc("0123456789abcdef"[(v >> i) & 0xf]);
}
static void fail(int stage) {
  puts("SOC HASH FAIL stage ");
  putc((char)('0' + stage));
  puts("\r\n");
  for (;;) __asm__ volatile("wfi");
}
static uint64_t rdcycle(void) {
  uint64_t c;
  __asm__ volatile("csrr %0, mcycle" : "=r"(c));
  return c;
}

/* soc-tests/link.ld sets _bss_start right after .data without
 * alignment and crt.S clears .bss with `sd`: keep .data 8-byte
 * sized/aligned so .bss starts aligned whatever .rodata's size is. */
volatile uint64_t hash_test_data_align __attribute__((section(".data"), aligned(8))) = 1;

static uint8_t msg[1000];
static uint8_t out[200];

static void gen(uint32_t len, uint32_t seed) {
  uint32_t x = seed * 0x9E3779B1u + 0x1234567u;
  for (uint32_t i = 0; i < len; i++) {
    x = x * 1103515245u + 12345u;
    msg[i] = (uint8_t)(x >> 16);
  }
}

static int hexval(char c) {
  return (c <= '9') ? c - '0' : c - 'a' + 10;
}
static int eq_hex(const uint8_t *b, const char *hex, uint32_t n) {
  uint32_t d = 0;
  for (uint32_t i = 0; i < n; i++) {
    d |= b[i] ^ (uint32_t)((hexval(hex[2 * i]) << 4) | hexval(hex[2 * i + 1]));
  }
  return d == 0;
}

static void wait_done(void) {
  while ((REG(SIGIL_HSTATUS) & SIGIL_HS_DONE) == 0) {
  }
}

/* Hash `len` bytes of `m` in `mode`, read `outlen` bytes. */
static void hash(int mode, const uint8_t *m, uint32_t len, uint8_t *o,
                 uint32_t outlen) {
  REG(SIGIL_HCTRL) = SIGIL_HCTRL_INIT(mode);
  uint32_t i = 0;
  for (; i + 4 <= len; i += 4) {
    REG(SIGIL_HDATA) = (uint32_t)m[i] | ((uint32_t)m[i + 1] << 8) |
                      ((uint32_t)m[i + 2] << 16) |
                      ((uint32_t)m[i + 3] << 24);
  }
  uint32_t tail = 0;
  for (uint32_t b = 0; i + b < len; b++) tail |= (uint32_t)m[i + b] << (8 * b);
  REG(SIGIL_HFIN) = SIGIL_HFIN_WORD(len - i, tail);
  wait_done();
  uint32_t per = (mode == SIGIL_HASH_SHA512) ? 64 : 136, got = 0;
  for (;;) {
    for (uint32_t k = 0; k < per && got < outlen; k += 4) {
      uint32_t w = REG(SIGIL_HDOUT);
      for (uint32_t b = 0; b < 4 && got < outlen; b++) o[got++] = (uint8_t)(w >> (8 * b));
    }
    if (got >= outlen) return;
    REG(SIGIL_HCTRL) = SIGIL_HCTRL_SQUEEZE;
    wait_done();
  }
}

int main(void) {
  static const uint8_t abc[3] = {'a', 'b', 'c'};

  hash(SIGIL_HASH_SHA512, abc, 3, out, 64);
  if (!eq_hex(out,
              "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
              "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
              64))
    fail(1);

  gen(1000, 1000);
  uint64_t t0 = rdcycle();
  hash(SIGIL_HASH_SHA512, msg, 1000, out, 64);
  uint64_t t1 = rdcycle();
  if (!eq_hex(out,
              "6966f9f5bb6f7c9ee61d34a700158c050349d383e04a8ff28f991c244ee42dd7"
              "4c5367ec3e2ef38af1c8c35d38ed56d9861ff59e602bc93abac0fdcd932e8402",
              64))
    fail(2);

  gen(137, 1);
  hash(SIGIL_HASH_SHA3_256, msg, 137, out, 32);
  if (!eq_hex(out,
              "448f2376ab4e39a960bb9e1b97ebf5353c3540df0a25f2ce9790d6cf752c9019",
              32))
    fail(3);

  hash(SIGIL_HASH_KECCAK256, abc, 3, out, 32);
  if (!eq_hex(out,
              "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
              32))
    fail(4);

  gen(3, 2);
  hash(SIGIL_HASH_SHAKE256, msg, 3, out, 200);
  if (!eq_hex(out,
              "bc558afb79747dbb68d5eafa8f117dcd6d4d99e16c8fa8a321000d1a7bd7c4bd"
              "f74d60d326408476ba55641a7b176523588c6b620cec22eb11f1710425195add"
              "f0a5970fd4e2fdfa368473cc60bdd55b230228b7274ecb36513d9d4f45eb4061"
              "63fc1bd62b293b6cc8532812d6b8ddff4b00da5fd130baa430e331320e061078"
              "86f52fc13ab2bbb19b5fd06db0e4e95718b884debc35b4f3d91ef2984599ca36"
              "4fba0766ed958d49235d5984269bea0d828168b7a350e9c7f0787fb248a0632b"
              "98800d33a1c5ff70",
              200))
    fail(5);

  if (REG(SIGIL_HSTATUS) & SIGIL_HS_ERR) fail(6);

  puts("SHA-512 1000 B: 0x");
  puthex(t1 - t0);
  puts(" cycles\r\n");
  puts("SOC HASH PASS\r\n");
  for (;;) __asm__ volatile("wfi");
}
