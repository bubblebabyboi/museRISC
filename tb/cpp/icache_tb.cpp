// Unit testbench for muserisc_icache (L1 I$, read-only).
//
// Build geometry (sim/Makefile -G): 4 sets x 2 ways x 32-byte
// lines; cacheable C0 = [0x1000, 0x3000), C1 = [2^55,
// 2^56); I/O fetches elsewhere are single beats.
//
// Random fetch streams (aligned 32-bit words, both halves of
// each bus word) over a conflict-heavy line pool and I/O
// addresses, under several bus timing profiles. Memory is
// rewritten at random points ("code modified + D$ cleaned"),
// always immediately followed by an inval_i pulse (FENCE.I),
// sometimes while a refill is in flight. Checks:
//   - a fetch accepted after the last modify+inval returns the
//     current memory word; one accepted before it may return
//     the old or the new word (it was in flight);
//   - after an inval that hit a refill in flight, the refilled
//     line is not left valid (the next fetch sees new data);
//   - one response per request, never in the accept cycle;
//   - I/O fetches are single beats with the exact address and
//     lanes, line refills are aligned full-line bursts.
#include "Vmuserisc_icache.h"
#include "verilated.h"
#include "verilated_cov.h"
#include "mbus_model.h"

#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <random>
#include <vector>

namespace {
constexpr int kLineBytes = 32;
constexpr uint64_t kC0Base = 0x1000, kC0Size = 0x2000;
// C1 is the upper half of the 56-bit PA space so random lines
// in it toggle every tag bit.
constexpr uint64_t kC1Base = 0x0080000000000000ULL, kC1Size = 0x0080000000000000ULL;
bool Cacheable(uint64_t a) {
  return (a >= kC0Base && a - kC0Base < kC0Size) ||
         (a >= kC1Base && a - kC1Base < kC1Size);
}
int g_errors = 0;
#define CHECK(c, ...)                                   \
  do {                                                  \
    if (!(c)) {                                         \
      if (g_errors++ < 20) {                            \
        std::printf("FAIL line %d: ", __LINE__);        \
        std::printf(__VA_ARGS__);                       \
        std::printf("\n");                              \
      }                                                 \
    }                                                   \
  } while (0)
}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_icache> dut{new Vmuserisc_icache{&context}};
  std::mt19937_64 rng(777);
  auto rnd = [&](uint64_t n) { return rng() % n; };

  uint64_t version = 1;
  auto word_of = [&](uint64_t a, uint64_t v) {
    // Deterministic contents per (address, version).
    uint64_t x = (a & ~7ull) * 0x9E3779B97F4A7C15ULL ^ (v * 0xC2B2AE3D27D4EB4FULL);
    return x ^ (x >> 29);
  };
  std::vector<uint64_t> lines_fixed;
  for (int i = 0; i < 6; ++i) lines_fixed.push_back(kC0Base + uint64_t(i) * 4 * kLineBytes);
  for (int i = 0; i < 4; ++i) lines_fixed.push_back(kC1Base + 0x20 + uint64_t(i) * 4 * kLineBytes);
  const std::vector<uint64_t> io_fixed = {0x0, 0x900, 0x3000, 0x80001000ULL, 0x10000000};

  long checks = 0, n_fetch = 0, n_inval = 0, n_kill = 0, n_io = 0;
  for (int phase = 0; phase < 10; ++phase) {
    MbusConfig cfg;
    cfg.seed = 900 + phase;
    switch (phase % 5) {
      case 0: break;
      case 1: cfg.lat_min = 1; cfg.lat_max = 10; cfg.gap_max = 2; break;
      case 2: cfg.lat_min = 2; cfg.lat_max = 4; cfg.ready_pct = 40; break;
      case 3: cfg.lat_min = 1; cfg.lat_max = 2; cfg.gap_max = 4; cfg.ready_pct = 70; break;
      default: cfg.lat_min = 6; cfg.lat_max = 15; break;
    }
    // Per-phase pools: the fixed lines plus random lines far up
    // in C1, and random I/O addresses (incl. PA bits 63:56 set).
    std::vector<uint64_t> lines = lines_fixed, io = io_fixed;
    for (int i = 0; i < 4; ++i) {
      lines.push_back(kC1Base | (rng() & (kC1Size - 1) & ~uint64_t(kLineBytes - 1)));
    }
    io.push_back((rng() & (kC1Base - 1) & ~uint64_t(7)) | 0x100000);
    io.push_back((rng() | (1ULL << 63)) & ~uint64_t(31));
    const bool cache_en = phase != 4;
    bool bad_beat = false;
    uint64_t io_expect_addr = 0;
    bool io_expect = false;
    MbusModel bus(
        cfg,
        [&](uint64_t a, uint8_t be, bool inst, bool burst) {
          if (!inst) bad_beat = true;
          if (!burst) {
            const uint8_t want = (io_expect_addr & 4) ? 0xF0 : 0x0F;
            if (!io_expect || a != io_expect_addr || be != want) bad_beat = true;
          }
          return word_of(a, version);
        },
        [&](uint64_t, uint8_t, uint64_t) { bad_beat = true; });

    dut->clk_i = 0;
    dut->rst_ni = 0;
    dut->cache_en_i = cache_en;
    dut->inval_i = 0;
    dut->req_valid_i = 0;
    dut->bus_req_ready_i = 0;
    dut->bus_rsp_valid_i = 0;
    dut->eval();
    dut->clk_i = 1;
    dut->eval();
    dut->clk_i = 0;
    dut->rst_ni = 1;
    dut->eval();

    bool have_req = false, pending = false;
    uint64_t req_addr = 0, inflight_addr = 0, inflight_ver = 0;
    int ops_left = 3000, idle = 0;
    long cyc = 0;
    while (ops_left > 0 || have_req || pending) {
      if (++cyc > 2000000) {
        CHECK(false, "phase %d hang", phase);
        break;
      }
      if (!have_req && ops_left > 0 && idle == 0) {
        if (rnd(12) == 0) {
          req_addr = io[rnd(io.size())] + 4 * rnd(4);
        } else {
          req_addr = lines[rnd(lines.size())] + 4 * rnd(kLineBytes / 4);
        }
        have_req = true;
        --ops_left;
        idle = int(rnd(3));
      } else if (idle > 0) {
        --idle;
      }
      // Code modification + FENCE.I, sometimes mid-refill.
      bool inval = false;
      if (rnd(150) == 0) {
        ++version;
        inval = true;
        ++n_inval;
      }
      dut->inval_i = inval;
      dut->req_valid_i = have_req;
      dut->req_addr_i = req_addr;
      dut->clk_i = 0;
      MbusDrive(&bus, dut.get());
      dut->eval();
      if (inval && pending && !dut->rsp_valid_o) ++n_kill;

      if (dut->rsp_valid_o) {
        CHECK(pending, "response with nothing outstanding");
        const uint64_t w_now = word_of(inflight_addr, version);
        const uint64_t w_then = word_of(inflight_addr, inflight_ver);
        const uint32_t got = dut->rsp_rdata_o;
        const int sh = (inflight_addr & 4) ? 32 : 0;
        const uint32_t now = uint32_t(w_now >> sh), then = uint32_t(w_then >> sh);
        if (inflight_ver == version) {
          CHECK(got == now, "phase %d fetch 0x%llx got 0x%08x want 0x%08x",
                phase, (unsigned long long)inflight_addr, got, now);
        } else {
          // Any version current while it was in flight.
          bool ok = false;
          for (uint64_t v = inflight_ver; v <= version; ++v) {
            ok = ok || got == uint32_t(word_of(inflight_addr, v) >> sh);
          }
          CHECK(ok,
                "phase %d in-flight fetch 0x%llx got 0x%08x (0x%08x/0x%08x)",
                phase, (unsigned long long)inflight_addr, got, then, now);
        }
        ++checks;
        pending = false;
      }
      const bool fire = have_req && dut->req_ready_o;
      if (fire) {
        CHECK(!pending, "accept while outstanding");
        pending = true;
        inflight_addr = req_addr;
        // A request accepted in the same cycle as inval_i is
        // looked up after it: it must see the new version.
        inflight_ver = version;
        io_expect = !(cache_en && Cacheable(req_addr));
        io_expect_addr = req_addr;
        if (io_expect) ++n_io;
        ++n_fetch;
        have_req = false;
      }
      const MbusModel::Req br = MbusSample(dut.get());
      if (br.fire && br.len != 0 &&
          ((br.addr % kLineBytes) != 0 || br.len != kLineBytes / 8 - 1 ||
           !cache_en || !Cacheable(br.addr))) {
        bad_beat = true;
      }
      dut->clk_i = 1;
      dut->eval();
      bus.Edge(br);
    }
    CHECK(!bad_beat, "phase %d illegal bus beat", phase);
  }
  std::printf("icache_tb: %ld checks, %ld fetches, %ld invals (%ld during a miss), %ld I/O, %d errors\n",
              checks, n_fetch, n_inval, n_kill, n_io, g_errors);
  dut->final();
  if (const char* cov = std::getenv("COV_FILE")) context.coveragep()->write(cov);
  if (g_errors != 0) {
    std::printf("ICACHE TB FAIL\n");
    return 1;
  }
  std::printf("ICACHE TB PASS\n");
  return 0;
}
