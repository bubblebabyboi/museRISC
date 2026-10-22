/* hash_stream: SHA-512 and SHA3-256 of arbitrary-length messages on
 * the streaming hash engine (docs/SPEC.md section 3.1).
 *
 * The engine takes the message 4 bytes per MMIO store (HDATA), pads in
 * hardware on HFIN, and exposes the digest on HDOUT. sigil_hash()
 * does the whole sequence; sigil_hash_init/update/final stream a
 * message in pieces of any size. Checks:
 *   1. SHA-512 at lengths around the 128-byte block boundary
 *      (0, 3, 111, 112, 127, 128, 129, 255, 1000) vs Python hashlib
 *   2. SHA3-256 around the 136-byte rate (0, 3, 135, 136, 137, 271,
 *      1000) vs hashlib
 *   3. FIPS "abc" vectors for SHA-512 and SHA3-256
 *   4. the 1000-byte message streamed in uneven pieces (1, 2, 3, ...
 *      bytes) gives the same digests as one call
 *   5. SHAKE256 with 300 bytes of output (two squeezes) vs hashlib
 * and prints cycles per byte for 1000-byte messages.
 *
 * Messages: an LCG byte stream, x = x * 1103515245 + 12345 (32-bit,
 * seed 12345), byte = (x >> 16) & 0xff; the expected values below are
 * Python hashlib over the same bytes. */
#include "sigil.h"

#define N 1000
static uint8_t msg[N];

typedef struct {
  uint32_t len;
  const char *hex;
} kat_t;

/* hashlib.sha512(msg[:len]) */
static const kat_t kSha512[] = {
    {0, "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"},
    {3, "7dd01f41a359ba5cb3350aa21af4af68dff3be71460bfced48b49ae2f9b8e69331266705324e859c0e2c0a798ad10be35ec8353f3eaf58aac572eb4a53c470dc"},
    {111, "d37e54a93ae7aaf3c4a9dfde3215b768891dc99c1a7db2dd33e32e78951d7780959354a6d95372c2786f01a1dd173d3e6f6dab9540d4c3b5c7b9729bbbf9fe4b"},
    {112, "cc2519d27259ebd28a3063c54e3032f80d82f01c895e423dbca13c6e4879aac2a88371bdfc2691ba63d02e6634346088094098f4b5ee6a1a59d096d00c38cbd4"},
    {127, "dc2c7cecaf12062ca236cc0d8ff3cf0f65ea5c5dd5f1a8f4b336990f8158ed5e857209ad8bc622df1d493e60e1bdf0f52b4ba3824bdff3734b4ada8d00e9f3ee"},
    {128, "80ebd4867b7b30d94553ceebe7ad5a3c7d9a772498737771a45729a86dc4920c5a2ac524c39f3f7e07a2bb844a770f53afb461b986bd503fa25389f57fa48f19"},
    {129, "31e2b2e27dfa815b9e608a4eec09855d030f4553c7d68b230d67b5545919f9281ceeb72c591a90dfacfa81aff471ac1c18b9200c0bbd6da9cf213ea1d98c0529"},
    {255, "ca5f0c4cb4a4b914e719d1a09acfb32f5d331a64ce10a8085ff440812d58e2326ecfc7a4539f96c6d31efea385db67b500d4e9c7c2175d70839baf9ee34931a5"},
    {1000, "b3a40afd2399fd795c243f72d8914c2a622ded4bebc966657f1d54996d5a92c73bbc8384ceb25622c9c6b40573eb7079100948a271203418627af42e8264805f"},
};
/* hashlib.sha3_256(msg[:len]) */
static const kat_t kSha3[] = {
    {0, "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"},
    {3, "c05f2a1662484d2cfc87b2e32232aaa947abc335fcc87ec8adcf4f4180dae8ea"},
    {135, "67326637607728487a50631c71fb3586ae4a57cc1bb3342417fbc54c31ccb3cc"},
    {136, "79caabf9db4e178102560c1a46b6a46fa780926b6c3ce2f3884132d5cfa02cce"},
    {137, "06365d616f287b6acdef27d57c2048b2f53f95144e6d7be616cb24d27f596f35"},
    {271, "706ef5713e9c3f2e779e76d435c71de593b6ab34c02c5d9985646e563d0d4b42"},
    {1000, "25eb954394fd45c5b3d1d8b0d1bee44b194c4dd20ba57321e20886e8a936f939"},
};
/* hashlib.shake_256(msg).hexdigest(300) */
static const char kShake300[] =
    "cb902b23a16d1368a2f51365a3c2dab3117ed7c66481912a14fb3989f7f71618"
    "b1d77d04c6b85c4521a15c63d12053dedc99396ea4bcca27b6024ea8f145b2d8"
    "f968bc27898e0cbf578c6031cc03155cea45f6c5154e529a455cb53c2d548e11"
    "5df233fe94fdf62a6ec2d3effbb8f02ff7aa9d5a540846e49172b3bf64aea624"
    "7cd77e6e35fb3daaadcca330c8f47bf60f7e36e3f03a6ce09da294047eebe68b"
    "6b5dcf1e42b94553d0ebc47403cc4153adcd508e437168789c38cca98171b191"
    "3bd1d0f502304f53725bb1f929b9fe07b27f04989f7f15aca39d46d51669df04"
    "b0c67c57f1e93bd073d2408ff7cecb8aa7fe306750d360fa5e5a407f5c66f169"
    "c54a7e4929fc619440b1e089669a6977f035186302bc21eab46f2b3b3fc67008"
    "734e2e2a197e30530902b0d9";

#define COUNT(a) (sizeof(a) / sizeof((a)[0]))

static int hexval(char c) { return c <= '9' ? c - '0' : c - 'a' + 10; }
static int eq_hex(const uint8_t *b, const char *hex, size_t n) {
  for (size_t i = 0; i < n; i++) {
    if (b[i] != ((hexval(hex[2 * i]) << 4) | hexval(hex[2 * i + 1]))) return 0;
  }
  return 1;
}

/* Feed msg[0..len) in pieces of 1, 2, 3, ... bytes. */
static void hash_pieces(int mode, uint32_t len, uint8_t *out, size_t outlen) {
  sigil_hash_init(mode);
  uint32_t off = 0, piece = 1;
  while (off < len) {
    uint32_t n = len - off < piece ? len - off : piece;
    sigil_hash_update(msg + off, n);
    off += n;
    piece++;
  }
  SIGIL_CHECK(sigil_hash_final(out, outlen) == 0);
}

int main(void) {
  static uint8_t out[300];
  uint32_t x = 12345;
  for (int i = 0; i < N; i++) {
    x = x * 1103515245u + 12345u;
    msg[i] = (uint8_t)(x >> 16);
  }

  /* 1, 2: known answers at every length in the tables. */
  for (unsigned i = 0; i < COUNT(kSha512); i++) {
    SIGIL_CHECK(sigil_hash(SIGIL_HASH_SHA512, msg, kSha512[i].len, out, 64) == 0);
    SIGIL_CHECK(eq_hex(out, kSha512[i].hex, 64));
  }
  sigil_printf("SHA-512: %u lengths ok\n", (unsigned)COUNT(kSha512));
  for (unsigned i = 0; i < COUNT(kSha3); i++) {
    SIGIL_CHECK(sigil_hash(SIGIL_HASH_SHA3_256, msg, kSha3[i].len, out, 32) == 0);
    SIGIL_CHECK(eq_hex(out, kSha3[i].hex, 32));
  }
  sigil_printf("SHA3-256: %u lengths ok\n", (unsigned)COUNT(kSha3));

  /* 3. FIPS 180-4 / FIPS 202 "abc". */
  SIGIL_CHECK(sigil_hash(SIGIL_HASH_SHA512, "abc", 3, out, 64) == 0);
  SIGIL_CHECK(eq_hex(out,
                     "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                     "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
                     64));
  SIGIL_CHECK(sigil_hash(SIGIL_HASH_SHA3_256, "abc", 3, out, 32) == 0);
  SIGIL_CHECK(eq_hex(out, "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                     32));
  sigil_printf("SHA3-256(\"abc\") = ");
  sigil_print_hex(out, 32);
  sigil_putc('\n');

  /* 4. Streaming in uneven pieces == one shot. */
  hash_pieces(SIGIL_HASH_SHA512, N, out, 64);
  SIGIL_CHECK(eq_hex(out, kSha512[COUNT(kSha512) - 1].hex, 64));
  hash_pieces(SIGIL_HASH_SHA3_256, N, out, 32);
  SIGIL_CHECK(eq_hex(out, kSha3[COUNT(kSha3) - 1].hex, 32));
  sigil_printf("piecewise streaming ok\n");

  /* 5. SHAKE256, 300 output bytes = 136 + 136 + 28 (two squeezes). */
  SIGIL_CHECK(sigil_hash(SIGIL_HASH_SHAKE256, msg, N, out, 300) == 0);
  SIGIL_CHECK(eq_hex(out, kShake300, 300));
  sigil_printf("SHAKE256 300-byte output ok\n");

  /* Throughput for 1000-byte messages (cycles per byte x100). */
  sigil_perf_t p = sigil_perf_now();
  sigil_hash(SIGIL_HASH_SHA512, msg, N, out, 64);
  uint64_t c512 = sigil_perf_since(p).cycles;
  p = sigil_perf_now();
  sigil_hash(SIGIL_HASH_SHA3_256, msg, N, out, 32);
  uint64_t c3 = sigil_perf_since(p).cycles;
  sigil_printf("1000 bytes: SHA-512 %lu cycles (%lu.%02lu cycles/byte), "
               "SHA3-256 %lu cycles (%lu.%02lu cycles/byte)\n",
               (unsigned long)c512, (unsigned long)(c512 / N),
               (unsigned long)(c512 % N / 10), (unsigned long)c3,
               (unsigned long)(c3 / N), (unsigned long)(c3 % N / 10));
  return 0;
}
