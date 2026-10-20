// museRISC in-house core: B/Zicond/crypto unit testbench.
// Golden model written independently from the extension
// manuals (bit operations), FIPS-197 (AES), and FIPS-180-4
// (SHA rotate/shift sets). The AES S-box here is a literal
// transcription of the FIPS-197 table (the RTL computes it in
// the composite field GF((2^4)^2)), so the two implementations
// only agree if both are right; both S-box directions are
// swept exhaustively.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>

#include "verilated.h"
#include "verilated_cov.h"
#include "Vmuserisc_bext.h"

static Vmuserisc_bext* dut;
static long checks = 0, fails = 0;

static uint64_t run(uint8_t op, uint64_t a, uint64_t b) {
  dut->op_i = op; dut->a_i = a; dut->b_i = b;
  dut->eval();
  return dut->result_o;
}

namespace gold {

static uint64_t ror64(uint64_t v, int sh) {
  sh &= 63;
  return sh == 0 ? v : (v >> sh) | (v << (64 - sh));
}
static uint32_t ror32(uint32_t v, int sh) {
  sh &= 31;
  return sh == 0 ? v : (v >> sh) | (v << (32 - sh));
}
static __uint128_t clmul(uint64_t a, uint64_t b) {
  __uint128_t r = 0;
  for (int i = 0; i < 64; i++)
    if ((b >> i) & 1) r ^= (__uint128_t)a << i;
  return r;
}

// FIPS-197 Figure 7 (S-box) and Figure 14 (inverse S-box).
static const uint8_t SBOX[256] = {
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16};
static const uint8_t ISBOX[256] = {
  0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
  0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
  0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
  0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
  0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
  0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
  0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
  0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
  0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
  0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
  0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
  0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
  0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
  0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
  0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
  0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d};

static uint8_t xtime(uint8_t x) {
  return (x << 1) ^ ((x & 0x80) ? 0x1B : 0);
}
static uint8_t gmul(uint8_t a, uint8_t b) {
  uint8_t r = 0;
  while (b) { if (b & 1) r ^= a; a = xtime(a); b >>= 1; }
  return r;
}
static uint32_t mixcol(uint32_t w) {
  uint8_t s0 = w, s1 = w >> 8, s2 = w >> 16, s3 = w >> 24;
  uint32_t r0 = gmul(s0,2) ^ gmul(s1,3) ^ s2 ^ s3;
  uint32_t r1 = s0 ^ gmul(s1,2) ^ gmul(s2,3) ^ s3;
  uint32_t r2 = s0 ^ s1 ^ gmul(s2,2) ^ gmul(s3,3);
  uint32_t r3 = gmul(s0,3) ^ s1 ^ s2 ^ gmul(s3,2);
  return r0 | (r1 << 8) | (r2 << 16) | (r3 << 24);
}
static uint32_t imixcol(uint32_t w) {
  uint8_t s0 = w, s1 = w >> 8, s2 = w >> 16, s3 = w >> 24;
  uint32_t r0 = gmul(s0,14) ^ gmul(s1,11) ^ gmul(s2,13) ^ gmul(s3,9);
  uint32_t r1 = gmul(s0,9) ^ gmul(s1,14) ^ gmul(s2,11) ^ gmul(s3,13);
  uint32_t r2 = gmul(s0,13) ^ gmul(s1,9) ^ gmul(s2,14) ^ gmul(s3,11);
  uint32_t r3 = gmul(s0,11) ^ gmul(s1,13) ^ gmul(s2,9) ^ gmul(s3,14);
  return r0 | (r1 << 8) | (r2 << 16) | (r3 << 24);
}
// One aes64 round half per the K spec: state is the 128-bit
// pair (a=low columns 0-1, b=high columns 2-3) in AES
// column-major order; result is the new low half.
static uint64_t aes_half(uint64_t a, uint64_t b, bool inv,
                         bool mix) {
  uint8_t s[16], o[8];
  for (int i = 0; i < 8; i++) {
    s[i] = (a >> (8*i)) & 0xFF;
    s[i+8] = (b >> (8*i)) & 0xFF;
  }
  for (int c = 0; c < 2; c++)
    for (int r = 0; r < 4; r++) {
      int src = inv ? (c + 4 - r) % 4 : (c + r) % 4;
      uint8_t v = s[src*4 + r];
      o[c*4 + r] = inv ? ISBOX[v] : SBOX[v];
    }
  uint64_t half = 0;
  for (int i = 0; i < 8; i++) half |= (uint64_t)o[i] << (8*i);
  if (mix) {
    uint32_t lo = inv ? imixcol((uint32_t)half) : mixcol((uint32_t)half);
    uint32_t hi = inv ? imixcol((uint32_t)(half >> 32))
                      : mixcol((uint32_t)(half >> 32));
    half = lo | ((uint64_t)hi << 32);
  }
  return half;
}
static const uint8_t RCON[11] = {1,2,4,8,16,32,64,128,27,54,0};

static uint64_t eval(int op, uint64_t a, uint64_t b) {
  uint32_t a32 = (uint32_t)a;
  switch (op) {
    case 0: return a32 + b;
    case 1: return (a << 1) + b;
    case 2: return (a << 2) + b;
    case 3: return (a << 3) + b;
    case 4: return ((uint64_t)a32 << 1) + b;
    case 5: return ((uint64_t)a32 << 2) + b;
    case 6: return ((uint64_t)a32 << 3) + b;
    case 7: return (uint64_t)a32 << (b & 63);
    case 8: return a & ~b;
    case 9: return a | ~b;
    case 10: return ~(a ^ b);
    case 11: return a ? __builtin_clzll(a) : 64;
    case 12: return a32 ? __builtin_clz(a32) : 32;
    case 13: return a ? __builtin_ctzll(a) : 64;
    case 14: return a32 ? __builtin_ctz(a32) : 32;
    case 15: return __builtin_popcountll(a);
    case 16: return __builtin_popcount(a32);
    case 17: return (int64_t)a >= (int64_t)b ? a : b;
    case 18: return a >= b ? a : b;
    case 19: return (int64_t)a <= (int64_t)b ? a : b;
    case 20: return a <= b ? a : b;
    case 21: return (int64_t)(int8_t)a;
    case 22: return (int64_t)(int16_t)a;
    case 23: return ror64(a, -(int)(b & 63));
    case 24: return (int64_t)(int32_t)ror32(a32, -(int)(b & 31));
    case 25: return ror64(a, b & 63);
    case 26: return (int64_t)(int32_t)ror32(a32, b & 31);
    case 27: { uint64_t r = 0;
      for (int i = 0; i < 8; i++)
        if ((a >> (8*i)) & 0xFF) r |= 0xFFULL << (8*i);
      return r; }
    case 28: return __builtin_bswap64(a);
    case 29: return (uint64_t)clmul(a, b);
    case 30: return (uint64_t)(clmul(a, b) >> 64);
    case 31: return (uint64_t)(clmul(a, b) >> 63);
    case 32: return a & ~(1ULL << (b & 63));
    case 33: return (a >> (b & 63)) & 1;
    case 34: return a ^ (1ULL << (b & 63));
    case 35: return a | (1ULL << (b & 63));
    case 36: return b == 0 ? 0 : a;
    case 37: return b != 0 ? 0 : a;
    case 38: return ((b & 0xFFFFFFFFULL) << 32) | a32;
    case 39: return ((b & 0xFFULL) << 8) | (a & 0xFFULL);
    case 40: return (int64_t)(int32_t)(((b & 0xFFFF) << 16) | (a & 0xFFFF));
    case 41: { uint64_t r = 0;
      for (int i = 0; i < 64; i++) {
        int byte = i / 8, bit = i % 8;
        if ((a >> i) & 1) r |= 1ULL << (byte*8 + (7-bit));
      }
      return r; }
    case 42: { uint64_t r = 0;
      for (int i = 0; i < 16; i++) {
        int idx = (b >> (4*i)) & 0xF;
        r |= ((a >> (4*idx)) & 0xF) << (4*i);
      }
      return r; }
    case 43: { uint64_t r = 0;
      for (int i = 0; i < 8; i++) {
        int idx = (b >> (8*i)) & 0xFF;
        if (idx < 8) r |= ((a >> (8*idx)) & 0xFF) << (8*i);
      }
      return r; }
    case 44: return aes_half(a, b, false, false);
    case 45: return aes_half(a, b, false, true);
    case 46: return aes_half(a, b, true, false);
    case 47: return aes_half(a, b, true, true);
    case 48: return imixcol(a32) | ((uint64_t)imixcol(a >> 32) << 32);
    case 49: { uint32_t w = a >> 32;
      int rc = b & 0xF;
      if (rc != 0xA) w = ror32(w, 8);
      uint32_t ks = (SBOX[w >> 24] << 24) | (SBOX[(w >> 16) & 0xFF] << 16) |
                    (SBOX[(w >> 8) & 0xFF] << 8) | SBOX[w & 0xFF];
      ks ^= RCON[rc];
      return ks | ((uint64_t)ks << 32); }
    case 50: { uint32_t lo = (uint32_t)(a >> 32) ^ (uint32_t)b;
      uint32_t hi = lo ^ (uint32_t)(b >> 32);
      return lo | ((uint64_t)hi << 32); }
    case 51: return (int64_t)(int32_t)(ror32(a32,7) ^ ror32(a32,18) ^ (a32 >> 3));
    case 52: return (int64_t)(int32_t)(ror32(a32,17) ^ ror32(a32,19) ^ (a32 >> 10));
    case 53: return (int64_t)(int32_t)(ror32(a32,2) ^ ror32(a32,13) ^ ror32(a32,22));
    case 54: return (int64_t)(int32_t)(ror32(a32,6) ^ ror32(a32,11) ^ ror32(a32,25));
    case 55: return ror64(a,1) ^ ror64(a,8) ^ (a >> 7);
    case 56: return ror64(a,19) ^ ror64(a,61) ^ (a >> 6);
    case 57: return ror64(a,28) ^ ror64(a,34) ^ ror64(a,39);
    case 58: return ror64(a,14) ^ ror64(a,18) ^ ror64(a,41);
    default: return 0;
  }
}
}  // namespace gold

static void cmp(int op, uint64_t a, uint64_t b) {
  checks++;
  uint64_t got = run(op, a, b);
  uint64_t want = gold::eval(op, a, b);
  if (got != want) {
    if (fails < 15)
      std::printf("FAIL op=%d a=%016llx b=%016llx got=%016llx want=%016llx\n",
                  op, (unsigned long long)a, (unsigned long long)b,
                  (unsigned long long)got, (unsigned long long)want);
    fails++;
  }
}

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const char* cov_path = std::getenv("COV_FILE");
  dut = new Vmuserisc_bext{&context};

  std::mt19937_64 rng(0xB17B00B5ULL);
  const uint64_t edges[] = {0, 1, ~0ULL, 0x8000000000000000ULL,
    0x00FF00FF00FF00FFULL, 0x0123456789ABCDEFULL,
    0x00000000FFFFFFFFULL, 0xFFFFFFFF00000000ULL, 3, 63, 64};
  // ops 59-63 are unassigned encodings (the decoder never emits
  // them); the unit must return 0 for them (case default).
  for (int op = 0; op <= 63; op++) {
    // aes64ks1i's second operand is a 4-bit rcon index (the
    // decoder rejects > 10); constrain it to legal values.
    auto bb = [&](uint64_t v) { return op == 49 ? (v % 11) : v; };
    for (uint64_t x : edges)
      for (uint64_t y : edges) cmp(op, x, bb(y));
    for (int i = 0; i < 800; i++) cmp(op, rng(), bb(rng()));
    // shift-amount sweeps for rotate/bit ops
    if (op == 23 || op == 24 || op == 25 || op == 26 ||
        (op >= 32 && op <= 35) || op == 7)
      for (int sh = 0; sh < 70; sh++) cmp(op, rng(), sh);
    if (op == 49)  // every rcon index incl. the 0xA no-rot case
      for (int rc = 0; rc <= 10; rc++) cmp(op, rng(), rc);
  }

  // Exhaustive S-box sweep, both directions, every lane: the
  // RTL computes SubBytes/InvSubBytes in a composite field
  // GF((2^4)^2), so check all 256 inputs against the FIPS-197
  // tables (and the tables against the GF(2^8) definition).
  long sbox_fail = 0;
  for (int x = 0; x < 256; x++) {
    // reference self-check: SBOX = affine(x^-1), ISBOX = SBOX^-1
    uint8_t inv = 0;
    for (int y = 1; y < 256 && x; y++)
      if (gold::gmul(x, y) == 1) { inv = y; break; }
    uint8_t aff = inv;
    for (int k = 1; k <= 4; k++)
      aff ^= (uint8_t)((inv << k) | (inv >> (8 - k)));
    aff ^= 0x63;
    if (gold::SBOX[x] != aff || gold::ISBOX[gold::SBOX[x]] != x) {
      std::printf("FAIL reference S-box mismatch at %02x\n", x);
      sbox_fail++;
    }
    const uint64_t rep = 0x0101010101010101ULL * (uint64_t)x;
    const uint64_t want_f = 0x0101010101010101ULL * gold::SBOX[x];
    const uint64_t want_i = 0x0101010101010101ULL * gold::ISBOX[x];
    // aes64es/ds with every state byte = x: all 8 lanes see x.
    uint64_t got_f = run(44, rep, rep), got_i = run(46, rep, rep);
    // aes64ks1i with rcon 0xA (no RotWord, Rcon 0): lanes 0-3.
    uint64_t got_k = run(49, rep, 0xA);
    checks += 3;
    if (got_f != want_f || got_i != want_i || got_k != want_f) {
      if (sbox_fail < 15)
        std::printf("FAIL sbox x=%02x fwd=%016llx inv=%016llx ks=%016llx\n",
                    x, (unsigned long long)got_f,
                    (unsigned long long)got_i, (unsigned long long)got_k);
      sbox_fail++;
    }
    // byte-distinct states through the full golden as well
    cmp(44, rep ^ 0x0011223344556677ULL, rep ^ 0x8899AABBCCDDEEFFULL);
    cmp(46, rep ^ 0x0011223344556677ULL, rep ^ 0x8899AABBCCDDEEFFULL);
  }
  fails += sbox_fail;
  cmp(0, 1, 2);  // back to a low op (op_i[5] 1->0 toggle)
  std::printf("S-box sweep: 256/256 inputs x {fwd, inv, ks1i}, %ld fail\n",
              sbox_fail);

  dut->final();
  // Write coverage while the model (which owns the counters) is
  // still alive; writing after `delete dut` read freed memory and
  // produced garbage line counts.
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  delete dut;
  if (fails) { std::printf("BEXT TB FAIL (%ld/%ld)\n", fails, checks);
    return 1; }
  std::printf("BEXT TB PASS (%ld checks)\n", checks);
  return 0;
}
