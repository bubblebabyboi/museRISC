// RV64M golden model shared by the muldiv unit testbenches
// (muldiv_tb.cpp, muldiv_mc_tb.cpp): __int128 arithmetic formulated
// directly from the spec rules (truncation toward zero, dividend-
// signed remainder, divide-by-zero and signed-overflow results).
#pragma once
#include <climits>
#include <cstdint>

namespace {

using i128 = __int128_t;
using u128 = __uint128_t;

uint64_t Sext32(uint32_t v) {
  return static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(v)));
}

// Golden at the working width. For word ops the operands are the
// sign- (signed ops) or zero- (unsigned ops) extended 32-bit
// values; results below are masked/extended per the W rule by the
// caller for multiplies and naturally for div/rem.
uint64_t Golden(int funct3, bool word, uint64_t a, uint64_t b) {
  if (word) {
    const int32_t as = static_cast<int32_t>(a);
    const int32_t bs = static_cast<int32_t>(b);
    const uint32_t au = static_cast<uint32_t>(a);
    const uint32_t bu = static_cast<uint32_t>(b);
    switch (funct3) {
      case 0: return Sext32(au * bu);                                     // MULW
      case 4:                                                             // DIVW
        if (bs == 0) return ~0ull;
        if (as == INT32_MIN && bs == -1) return Sext32(0x80000000u);
        return Sext32(static_cast<uint32_t>(as / bs));
      case 5: return (bu == 0) ? ~0ull : Sext32(au / bu);                 // DIVUW
      case 6:                                                             // REMW
        if (bs == 0) return Sext32(au);
        if (as == INT32_MIN && bs == -1) return 0;
        return Sext32(static_cast<uint32_t>(as % bs));
      case 7: return (bu == 0) ? Sext32(au) : Sext32(au % bu);            // REMUW
      default: return 0;  // MULHW-class: unimplemented encodings, DUT don't-care
    }
  }
  const int64_t as = static_cast<int64_t>(a);
  const int64_t bs = static_cast<int64_t>(b);
  switch (funct3) {
    case 0: return static_cast<uint64_t>(static_cast<u128>(a) * b);       // MUL
    case 1: return static_cast<uint64_t>(static_cast<i128>(as) * bs >> 64);  // MULH
    case 2: return static_cast<uint64_t>(static_cast<i128>(as) * static_cast<u128>(b) >> 64);  // MULHSU
    case 3: return static_cast<uint64_t>(static_cast<u128>(a) * b >> 64);  // MULHU
    case 4:                                                               // DIV
      if (bs == 0) return ~0ull;
      if (as == INT64_MIN && bs == -1) return static_cast<uint64_t>(as);
      return static_cast<uint64_t>(as / bs);
    case 5: return (b == 0) ? ~0ull : a / b;                              // DIVU
    case 6:                                                               // REM
      if (bs == 0) return a;
      if (as == INT64_MIN && bs == -1) return 0;
      return static_cast<uint64_t>(as % bs);
    case 7: return (b == 0) ? a : a % b;                                  // REMU
    default: return 0;
  }
}
}  // namespace
