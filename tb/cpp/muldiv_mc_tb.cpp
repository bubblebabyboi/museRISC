// Unit test for muserisc_muldiv_mc (multi-cycle RV64M unit) against
// the C++ golden model in muldiv_golden.h, through the generic EX
// handshake (req/ack/kill/done):
//   - exhaustive edge-operand cross product for every op and W form,
//     plus an exhaustive small-operand sweep for the dividers;
//   - a large randomized sweep with operand lengths spread so every
//     divider step count (0..32, W 0..16) is exercised;
//   - exact latency on every path (mul, divide special cases, every
//     divider step count), checked against the documented formula;
//   - done held without ack (result stable), operand/op inputs
//     scrambled while busy (must be ignored), ack noise while busy,
//     back-to-back issue, kill and req-drop at every stage including
//     the done-hold, asynchronous reset mid-operation, and a new op
//     issued right after a squash.
// Build with -DMDU_COMB for the COMB=1 (legacy single-cycle) model:
// latency 0, no kill/scramble tests (the unit has no state).
//
// Usage: muldiv_mc_tb [random_ops]   (default 1,000,000)
#include "Vmuserisc_muldiv_mc.h"
#include "verilated.h"
#include "verilated_cov.h"
#include "muldiv_golden.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <random>

namespace {

#ifdef MDU_COMB
constexpr bool kComb = true;
#else
constexpr bool kComb = false;
#endif

int Clz(uint64_t x) { return x ? __builtin_clzll(x) : 64; }

// Documented latency (cycle of done_o, issue cycle = 0).
int ExpLatency(int f3, bool word, uint64_t a, uint64_t b) {
  if (kComb) return 0;
  if (f3 < 4) return 2;
  const bool sgn = (f3 & 1) == 0;
  const uint64_t a_val = word ? Sext32(static_cast<uint32_t>(a)) : a;
  const uint64_t b_val = word ? Sext32(static_cast<uint32_t>(b)) : b;
  const uint64_t au = word ? (a & 0xffffffffULL) : a;
  const uint64_t bu = word ? (b & 0xffffffffULL) : b;
  const uint64_t most_neg = word ? 0xffffffff80000000ULL : 0x8000000000000000ULL;
  if (bu == 0) return 1;
  if (sgn && a_val == most_neg && b_val == ~0ULL) return 1;
  const uint64_t am = (sgn && (a_val >> 63)) ? (~a_val + 1) : au;
  const uint64_t bm = (sgn && (b_val >> 63)) ? (~b_val + 1) : bu;
  const int d = Clz(bm) - Clz(am) + 1;
  const int n = d <= 0 ? 0 : (d + 1) / 2;
  return 2 + n;
}

struct Opts {
  int ack_delay = 0;     // cycles done is held before ack
  bool scramble = false; // randomize op/operand inputs while busy
  bool ack_noise = false;// random ack while not done (must be ignored)
  int kill_at = -1;      // cycle to squash at (-1: never)
  bool by_drop = false;  // squash by dropping req instead of kill_i
  bool by_reset = false; // squash by asynchronous reset instead
};

class Harness {
 public:
  explicit Harness(VerilatedContext* ctx) : dut_(new Vmuserisc_muldiv_mc{ctx}), rng_(0x6d756c64ULL) {
    dut_->clk_i = 0;
    dut_->rst_ni = 0;
    dut_->req_i = 0;
    dut_->ack_i = 0;
    dut_->kill_i = 0;
    dut_->eval();
    for (int i = 0; i < 3; ++i) Tick();
    dut_->rst_ni = 1;
    dut_->eval();
  }

  void Tick() {
    dut_->clk_i = 1;
    dut_->eval();
    dut_->clk_i = 0;
    dut_->eval();
    ++cycles_;
  }

  void Scramble() {
    dut_->funct3_i = static_cast<uint8_t>(rng_() & 7);
    dut_->word_op_i = rng_() & 1;
    dut_->a_i = rng_();
    dut_->b_i = rng_();
  }

  bool Fail(const char* what, int f3, bool word, uint64_t a, uint64_t b, int cyc) {
    std::printf("FAIL %s f3=%d word=%d a=0x%016lx b=0x%016lx cycle=%d lat=%d got=0x%016lx want=0x%016lx done=%d\n",
                what, f3, word ? 1 : 0, static_cast<unsigned long>(a), static_cast<unsigned long>(b), cyc,
                ExpLatency(f3, word, a, b), static_cast<unsigned long>(dut_->result_o),
                static_cast<unsigned long>(Golden(f3, word, a, b)), dut_->done_o);
    return false;
  }

  // Idle cycles with req low: done must stay low (MC).
  bool Idle(int n) {
    dut_->req_i = 0;
    dut_->ack_i = 0;
    dut_->kill_i = 0;
    for (int i = 0; i < n; ++i) {
      dut_->eval();
      if (dut_->done_o) return Fail("done while idle", 0, false, 0, 0, i);
      Tick();
    }
    return true;
  }

  // Issue one op; returns false on any mismatch. Leaves the unit idle
  // (acked or squashed) with req still driven high only if the next
  // call starts immediately (back-to-back).
  bool Run(int f3, bool word, uint64_t a, uint64_t b, const Opts& o) {
    const bool dont_care = word && f3 >= 1 && f3 <= 3;  // no MULHW
    const int lat = ExpLatency(f3, word, a, b);
    const uint64_t want = Golden(f3, word, a, b);
    dut_->req_i = 1;
    dut_->ack_i = 0;
    dut_->kill_i = 0;
    dut_->funct3_i = static_cast<uint8_t>(f3);
    dut_->word_op_i = word ? 1 : 0;
    dut_->a_i = a;
    dut_->b_i = b;
    int c = 0;
    for (;; ++c) {
      if (c > 0 && o.scramble) Scramble();
      if (c == o.kill_at) return Squash(o, f3, word, a, b, c);
      dut_->ack_i = (o.ack_noise && c > 0 && (rng_() & 1)) ? 1 : 0;
      dut_->eval();
      if (dut_->done_o) break;
      if (c >= lat) return Fail("late done", f3, word, a, b, c);
      Tick();
    }
    if (c != lat) return Fail("early done", f3, word, a, b, c);
    ++checks_;
    if (lat >= 2 && f3 >= 4) ++hist_[word ? 1 : 0][lat - 2];
    if (!dont_care && dut_->result_o != want) return Fail("result", f3, word, a, b, c);
    const uint64_t got = dut_->result_o;
    // Done held without ack: result must stay stable.
    for (int k = 0; k < o.ack_delay; ++k) {
      dut_->ack_i = 0;
      Tick();
      if (o.scramble) Scramble();
      if (c + 1 + k == o.kill_at) return Squash(o, f3, word, a, b, c + 1 + k);
      dut_->eval();
      if (!dut_->done_o || dut_->result_o != got) return Fail("hold", f3, word, a, b, c + 1 + k);
    }
    dut_->ack_i = 1;
    dut_->eval();
    Tick();
    dut_->ack_i = 0;
    return true;
  }

  // Squash at the current cycle (kill_i, or req dropped), then check
  // the unit is idle the next cycle.
  bool Squash(const Opts& o, int f3, bool word, uint64_t a, uint64_t b, int c) {
    if (o.by_reset) {
      dut_->rst_ni = 0;           // asynchronous: takes effect now
      dut_->eval();
      if (dut_->done_o) return Fail("done in reset", f3, word, a, b, c);
      dut_->req_i = 0;
    } else if (o.by_drop) {
      dut_->req_i = 0;
    } else {
      dut_->kill_i = 1;
      dut_->req_i = rng_() & 1;  // kill wins whether or not req is held
    }
    dut_->ack_i = 0;
    dut_->eval();
    Tick();
    dut_->rst_ni = 1;
    dut_->kill_i = 0;
    dut_->req_i = 0;
    dut_->eval();
    if (dut_->done_o) return Fail("done after squash", f3, word, a, b, c);
    ++kills_;
    return true;
  }

  uint64_t Rand() { return rng_(); }
  uint64_t checks_ = 0, kills_ = 0, cycles_ = 0;
  uint64_t hist_[2][40] = {};
  std::unique_ptr<Vmuserisc_muldiv_mc> dut_;

 private:
  std::mt19937_64 rng_;
};

const uint64_t kEdges[] = {
    0, 1, 2, 3, 5, 7, 0x10,
    static_cast<uint64_t>(-1), static_cast<uint64_t>(-2), static_cast<uint64_t>(-3),
    0x7fffffffULL, 0x80000000ULL, 0x80000001ULL, 0xffffffffULL, 0x100000000ULL,
    0x7fffffffffffffffULL, 0x8000000000000000ULL, 0x8000000000000001ULL,
    0xffffffff80000000ULL, 0xffffffff7fffffffULL,
    0xdeadbeefcafef00dULL, 0x4000000000000000ULL, 0x00000000c0000000ULL,
    0x5555555555555555ULL, 0xaaaaaaaaaaaaaaaaULL, 0x0000000100000001ULL};

uint64_t RandOperand(Harness& h) {
  const uint64_t r = h.Rand();
  switch (r % 8) {
    case 0: return kEdges[h.Rand() % (sizeof(kEdges) / sizeof(kEdges[0]))];
    case 1: return static_cast<uint64_t>(static_cast<int64_t>(h.Rand() % 33) - 16);
    case 2: case 3: return h.Rand() >> (h.Rand() % 64);                 // positive, random length
    case 4: return ~(h.Rand() >> (h.Rand() % 64));                      // negative, random length
    case 5: return (h.Rand() >> (h.Rand() % 32)) & 0xffffffffULL;      // 32-bit lengths
    default: return h.Rand();
  }
}

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  long n_random = 1000000;
  if (argc > 1 && argv[1][0] != '+') n_random = std::strtol(argv[1], nullptr, 0);
  Harness h(&context);
  const char* cov_path = std::getenv("COV_FILE");
  const Opts plain;

  // 1. Edge cross product, every op and W form, ack immediately,
  //    back-to-back (no idle gap between ops).
  for (int f3 = 0; f3 < 8; ++f3)
    for (int w = 0; w < 2; ++w)
      for (uint64_t a : kEdges)
        for (uint64_t b : kEdges)
          if (!h.Run(f3, w != 0, a, b, plain)) return 1;
  if (!h.Idle(2)) return 1;

  // 2. Small operands, exhaustive, dividers and multipliers.
  for (int f3 = 0; f3 < 8; ++f3)
    for (int w = 0; w < 2; ++w)
      for (int64_t a = -20; a <= 20; ++a)
        for (int64_t b = -20; b <= 20; ++b)
          if (!h.Run(f3, w != 0, static_cast<uint64_t>(a), static_cast<uint64_t>(b), plain)) return 1;

  // 3. Every divider step count: |a| = 2^i - 1 .. 2^i, |b| = 1,
  //    shifted so clz differences span the whole range.
  for (int f3 = 4; f3 < 8; ++f3)
    for (int w = 0; w < 2; ++w)
      for (int ia = 0; ia < 64; ++ia)
        for (int ib = 0; ib < 64; ++ib) {
          const uint64_t a = (1ULL << ia) | (h.Rand() & ((1ULL << ia) - 1));
          const uint64_t b = (1ULL << ib) | (h.Rand() & ((1ULL << ib) - 1));
          if (!h.Run(f3, w != 0, a, b, plain)) return 1;
          if (!h.Run(f3, w != 0, ~a + 1, b, plain)) return 1;
        }

  // 4. Randomized sweep with handshake stress.
  for (long i = 0; i < n_random; ++i) {
    const int f3 = static_cast<int>(h.Rand() % 8);
    const bool word = (h.Rand() & 1) != 0;
    const uint64_t a = RandOperand(h);
    const uint64_t b = RandOperand(h);
    Opts o;
    const uint64_t r = h.Rand();
    o.ack_delay = (r & 3) == 0 ? static_cast<int>((r >> 2) % 4) : 0;
    if (!kComb) {
      o.scramble = ((r >> 4) & 1) != 0;
      o.ack_noise = ((r >> 5) & 1) != 0;
      if (((r >> 6) & 7) == 0) {  // 1/8 of ops are squashed
        const int lat = ExpLatency(f3, word, a, b);
        o.kill_at = static_cast<int>((r >> 9) % static_cast<uint64_t>(lat + o.ack_delay + 1));
        o.by_drop = ((r >> 16) & 1) != 0;
        o.by_reset = ((r >> 17) & 7) == 0;
      }
    }
    if (!h.Run(f3, word, a, b, o)) return 1;
    // Gap: mostly back-to-back.
    const int gap = ((r >> 20) & 3) == 0 ? static_cast<int>((r >> 22) % 3) : 0;
    if (gap && !h.Idle(gap)) return 1;
  }

  // Every divider step count must have been hit (n = lat - 2).
  if (!kComb) {
    for (int n = 0; n <= 32; ++n)
      if (h.hist_[0][n] == 0) { std::printf("FAIL: 64-bit divide with %d steps never seen\n", n); return 1; }
    for (int n = 0; n <= 16; ++n)
      if (h.hist_[1][n] == 0) { std::printf("FAIL: word divide with %d steps never seen\n", n); return 1; }
  }

  h.dut_->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("MULDIV_MC%s TB PASS (%llu checks, %llu squashes, %llu cycles)\n", kComb ? " (COMB=1)" : "",
              static_cast<unsigned long long>(h.checks_), static_cast<unsigned long long>(h.kills_),
              static_cast<unsigned long long>(h.cycles_));
  return 0;
}
