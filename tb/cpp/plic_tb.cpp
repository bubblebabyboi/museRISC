// Unit test for the RTL PLIC (rtl/soc/muserisc_plic.sv): register
// access over the 64-bit bus, WARL 3-bit priorities/thresholds,
// the claim arbitration (highest priority > 0 among pending
// enabled sources regardless of threshold, ties to the lowest id,
// 0 = none), the claim side effect, completion (ignored for a
// source not enabled for the context) and level re-pending, and
// both contexts' EIP outputs (priority above the threshold). A cycle-level
// reference model of the documented behaviour (module header) is
// compared against the DUT on every cycle of directed sequences
// and of a long random stream with heavy priority ties.
//
// Usage: plic_tb [cycles] [seed]   (defaults 2,000,000, 0x91c)
#include "Vmuserisc_plic.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <random>

namespace {
uint64_t g_checks = 0;
long g_fails = 0;

#define CHECK(cond)                                                     \
  do {                                                                  \
    ++g_checks;                                                         \
    if (!(cond)) {                                                      \
      if (g_fails < 20)                                                 \
        std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);     \
      ++g_fails;                                                        \
    }                                                                   \
  } while (0)

constexpr uint32_t kClaim0 = 0x200004, kClaim1 = 0x201004;

// Reference model: 32 sources (0 unused), contexts 0 and 1.
struct Model {
  uint32_t prio[32] = {};
  uint32_t en[2] = {};
  uint32_t thr[2] = {};
  uint32_t claimed = 0;
  uint32_t src = 0;

  uint32_t Pending() const { return src & ~claimed; }
  static constexpr uint32_t kPrioMask = 7;   // 3 implemented bits
  bool Elig(int c, int s) const {             // claimable
    return s >= 1 && (Pending() >> s & 1u) && (en[c] >> s & 1u) &&
           prio[s] != 0;
  }
  uint32_t Best(int c) const {  // first strictly-greater wins
    uint32_t best = 0, bp = 0;
    for (int s = 1; s < 32; ++s)
      if (Elig(c, s) && (best == 0 || prio[s] > bp)) { best = s; bp = prio[s]; }
    return best;
  }
  bool Eip(int c) const {
    for (int s = 1; s < 32; ++s) if (Elig(c, s) && prio[s] > thr[c]) return true;
    return false;
  }
  uint32_t Word(uint32_t off, bool re) const {
    if (off < 0x80) return prio[(off >> 2) & 31];
    switch (off) {
      case 0x1000: return Pending();
      case 0x2000: return en[0];
      case 0x2080: return en[1];
      case 0x200000: return thr[0];
      case 0x201000: return thr[1];
      case kClaim0: return re ? Best(0) : 0;
      case kClaim1: return re ? Best(1) : 0;
      default: return 0;
    }
  }
  uint64_t Read(uint32_t addr, bool re) const {
    const uint32_t a = addr & ~7u;
    return (uint64_t(Word(a + 4, re)) << 32) | Word(a, re);
  }
  static uint32_t Merge(uint32_t cur, uint64_t wdata, uint8_t be, bool hi) {
    for (int i = 0; i < 4; ++i)
      if (be >> (i + (hi ? 4 : 0)) & 1u) {
        const uint32_t b = uint32_t(wdata >> (8 * (i + (hi ? 4 : 0)))) & 0xffu;
        cur = (cur & ~(0xffu << (8 * i))) | (b << (8 * i));
      }
    return cur;
  }
  // One clock edge with this cycle's bus request.
  void Edge(uint32_t addr, bool re, uint8_t be, uint64_t wdata) {
    const uint32_t woff = addr & ~3u;
    const bool hi = addr & 4u;
    const bool is_claim = woff == kClaim0 || woff == kClaim1;
    const uint32_t cval = woff == kClaim0 ? Best(0) : woff == kClaim1 ? Best(1) : 0;
    uint32_t nclaimed = claimed;
    if (re && is_claim && cval != 0) nclaimed |= 1u << (cval & 31);
    if (be != 0) {
      const uint32_t sw = uint32_t(hi ? wdata >> 32 : wdata);
      if (is_claim) {
        const int c = woff == kClaim1 ? 1 : 0;
        // Only for a source enabled for the context; later write wins.
        if (sw < 32 && (en[c] >> sw & 1u)) nclaimed &= ~(1u << sw);
      } else if (woff < 0x80) {
        prio[(woff >> 2) & 31] = Merge(prio[(woff >> 2) & 31], wdata, be, hi) & kPrioMask;
      } else if (woff == 0x2000) {
        en[0] = Merge(en[0], wdata, be, hi);
      } else if (woff == 0x2080) {
        en[1] = Merge(en[1], wdata, be, hi);
      } else if (woff == 0x200000) {
        thr[0] = Merge(thr[0], wdata, be, hi) & kPrioMask;
      } else if (woff == 0x201000) {
        thr[1] = Merge(thr[1], wdata, be, hi) & kPrioMask;
      }
    }
    claimed = nclaimed;
  }
};

struct Bench {
  Vmuserisc_plic* d;
  Model m;
  void Drive(uint32_t addr, bool re, uint8_t be, uint64_t wdata) {
    d->addr_i = addr; d->re_i = re; d->be_i = be; d->wdata_i = wdata;
    d->irq_sources_i = m.src;
    d->clk_i = 0; d->eval();
  }
  // Compare outputs for the driven request, then clock it.
  uint64_t Cycle(uint32_t addr, bool re, uint8_t be, uint64_t wdata) {
    Drive(addr, re, be, wdata);
    const uint64_t got = d->rdata_o;
    CHECK(got == m.Read(addr, re));
    CHECK(d->eip_o == unsigned((m.Eip(1) ? 2 : 0) | (m.Eip(0) ? 1 : 0)));
    d->clk_i = 1; d->eval();
    m.Edge(addr, re, be, wdata);
    return got;
  }
  void Idle() { Cycle(0x3ff000, false, 0, 0); }
  void W32(uint32_t off, uint32_t v) {
    Cycle(off, false, (off & 4) ? 0xf0 : 0x0f, (off & 4) ? uint64_t(v) << 32 : v);
  }
  uint32_t R32(uint32_t off, bool re = false) {
    const uint64_t r = Cycle(off, re, 0, 0);
    return uint32_t((off & 4) ? r >> 32 : r);
  }
  uint32_t Claim(int c) { return R32(c ? kClaim1 : kClaim0, true); }
  void Complete(int c, uint32_t id) { W32(c ? kClaim1 : kClaim0, id); }
};
}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_plic> dut{new Vmuserisc_plic{&context}};
  const long cycles = argc > 1 ? std::strtol(argv[1], nullptr, 0) : 2000000;
  const uint64_t seed = argc > 2 ? std::strtoull(argv[2], nullptr, 0) : 0x91c;
  Bench b{dut.get(), {}};
  dut->rst_ni = 0; dut->clk_i = 0; dut->eval();
  dut->rst_ni = 1; dut->eval();

  // ---- Directed ----
  // Reset state: nothing eligible, claims return 0.
  b.m.src = 0xfffffffe;
  CHECK(b.Claim(0) == 0 && b.Claim(1) == 0);
  CHECK(dut->eip_o == 0);
  // Priorities: ties at 5 for 3/7/9, 6 for 20; 0 never wins.
  b.W32(3 * 4, 5); b.W32(7 * 4, 5); b.W32(9 * 4, 5); b.W32(20 * 4, 6);
  CHECK(b.R32(20 * 4) == 6 && b.R32(7 * 4) == 5);
  b.W32(0x2000, (1u << 3) | (1u << 7) | (1u << 9) | (1u << 20) | (1u << 30));
  b.m.src = (1u << 3) | (1u << 7) | (1u << 9) | (1u << 30);  // 20 idle, 30 prio 0
  b.Idle();
  CHECK(dut->eip_o == 1);
  CHECK(b.R32(0x1000) == b.m.src);
  CHECK(b.Claim(0) == 3);                  // tie at 5: lowest id
  CHECK(b.R32(0x1000) == ((1u << 7) | (1u << 9) | (1u << 30)));
  CHECK(b.Claim(0) == 7);
  b.m.src |= 1u << 20;
  b.Idle();
  CHECK(b.Claim(0) == 20);                 // strictly higher priority
  CHECK(b.Claim(0) == 9);
  CHECK(b.Claim(0) == 0);                  // only 30 left, priority 0
  CHECK(dut->eip_o == 0);
  // Completion: level sources still asserted re-pend.
  b.Complete(0, 7);
  CHECK(b.Claim(0) == 7);
  b.m.src &= ~(1u << 3);                   // 3 deasserts while claimed
  b.Complete(0, 3); b.Complete(0, 7); b.Complete(0, 9); b.Complete(0, 20);
  b.Idle();
  CHECK(b.Claim(0) == 20);
  b.Complete(0, 20);
  // Threshold gates EIP only (priority <= threshold); a claim
  // still returns the best pending enabled source.
  b.W32(0x200000, 5);
  b.Idle();
  CHECK(dut->eip_o == 1);                  // 20 (6) is above
  b.m.src &= ~(1u << 20);
  b.Idle();
  CHECK(dut->eip_o == 0);
  CHECK(b.Claim(0) == 7);                  // 5 <= threshold, still claimed
  b.Complete(0, 7);
  b.W32(0x200000, 4);
  CHECK(dut->eip_o == 1);
  // Context 1 is independent: own enables and threshold.
  b.W32(0x2080, 1u << 9);
  b.W32(0x201000, 0);
  b.Idle();
  CHECK((dut->eip_o & 2) != 0);
  CHECK(b.Claim(1) == 9);
  CHECK((dut->eip_o & 2) == 0);            // claimed source drops out
  CHECK(b.Claim(0) == 7);                  // context 0 skips 9 too
  // A completion for a source not enabled for the context is
  // ignored (7 is enabled only for context 0).
  b.Complete(1, 7);
  CHECK(b.R32(0x1000) == (b.m.src & ~((1u << 7) | (1u << 9))));
  b.Complete(1, 9); b.Complete(0, 7);
  CHECK(b.R32(0x1000) == b.m.src);
  // A read without re_i has no side effect and returns 0.
  CHECK(b.R32(kClaim0, false) == 0);
  CHECK(b.R32(0x1000) == b.m.Pending());
  // Byte-enable merge into a priority register (upper bus half),
  // and WARL: only 3 bits are implemented.
  b.Cycle(5 * 4, false, 0x10, uint64_t(0xfd) << 32);
  CHECK(b.R32(5 * 4) == 5);
  b.W32(6 * 4, 0xffffffffu);
  CHECK(b.R32(6 * 4) == 7);
  b.W32(0x201000, 0x12345678u);
  CHECK(b.R32(0x201000) == 0);
  // Out-of-range completion id is ignored.
  b.Complete(0, 40);

  // ---- Random ----
  std::mt19937_64 rng(seed);
  const uint32_t offs[] = {0x1000, 0x2000, 0x2080, 0x200000, 0x201000, kClaim0, kClaim1,
                           0x3ff000};
  long claims = 0, nonzero = 0;
  for (long n = 0; n < cycles; ++n) {
    uint32_t off = (rng() % 4 == 0) ? uint32_t(rng() % 32) * 4 : offs[rng() % 8];
    uint64_t v;
    switch (rng() % 4) {                    // priority classes: many ties
      case 0: v = rng() % 4; break;
      case 1: v = rng() % 8; break;
      case 2: v = uint32_t(rng()); break;
      default: v = (rng() % 2) ? 0xffffffffu : 0; break;
    }
    if (off == 0x2000 || off == 0x2080) v = uint32_t(rng() & rng());
    if (off == 0x200000 || off == 0x201000) v = (rng() % 8 == 0) ? uint32_t(rng()) : rng() % 6;
    if (off == kClaim0 || off == kClaim1) v = rng() % 34;
    const int kind = rng() % 4;
    const bool re = kind == 0;
    uint8_t be = 0;
    if (kind == 1) be = (off & 4) ? 0xf0 : 0x0f;
    if (kind == 2) be = uint8_t(rng());     // partial / both halves
    if (rng() % 32 == 0) b.m.src = uint32_t(rng() & rng());
    const uint32_t addr = off | (rng() % 8 == 0 ? (rng() & 3) : 0);
    const uint64_t r = b.Cycle(addr, re, be, (off & 4) ? v << 32 : v);
    if (re && ((addr & ~3u) == kClaim0 || (addr & ~3u) == kClaim1)) {
      ++claims;
      if (uint32_t((addr & 4) ? r >> 32 : r)) ++nonzero;
    }
  }

  if (const char* cov = std::getenv("COV_FILE")) context.coveragep()->write(cov);
  if (g_fails) {
    std::printf("PLIC TB FAIL (%ld failures, %llu checks, seed 0x%llx)\n", g_fails,
                (unsigned long long)g_checks, (unsigned long long)seed);
    return 1;
  }
  std::printf("PLIC TB PASS (%llu checks, %ld random cycles, %ld claim reads, %ld nonzero, "
              "seed 0x%llx)\n",
              (unsigned long long)g_checks, cycles, claims, nonzero,
              (unsigned long long)seed);
  return 0;
}
