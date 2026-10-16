// Unit testbench for muserisc_dcache (L1 D$, write-back +
// write-allocate) against a golden flat memory.
//
// Build geometry (sim/Makefile -G): 4 sets x 2 ways x 32-byte
// lines, so a small address pool forces constant conflict
// misses, dirty evictions and clean-victim refills. Cacheable
// windows: C0 = [0x1000, 0x3000), C1 = [2^55, 2^56) (all tag bits toggle);
// the pool also holds I/O addresses outside both windows.
//
// Each phase drives a random mix of loads, stores (random lane
// masks), CLEANs and I/O accesses through the core-side
// valid/ready port under a different bus timing profile
// (latency, inter-beat gaps, req_ready backpressure) and with
// random request spacing, including requests presented while
// the cache is still busy (req_ready low). Checks:
//   - every load returns the golden (architectural) word;
//   - exactly one response per request, never in the accept
//     cycle;
//   - I/O accesses reach the bus as single beats, in order,
//     with the exact address/lanes/data, and never as bursts;
//   - cacheable traffic reaches the bus only as whole-line
//     bursts (refill reads, write-back writes);
//   - after every CLEAN the bus-side memory equals the golden
//     memory for every cacheable address (no lost write-back),
//     and the cache_en strap = 0 phase makes everything I/O.
#include "Vmuserisc_dcache.h"
#include "verilated.h"
#include "verilated_cov.h"
#include "mbus_model.h"

#include <cstdint>
#include <cstdio>
#include <deque>
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
constexpr int kOpLoad = 0, kOpStore = 1, kOpClean = 2;

bool Cacheable(uint64_t a) {
  return (a >= kC0Base && a - kC0Base < kC0Size) ||
         (a >= kC1Base && a - kC1Base < kC1Size);
}

struct Mem {
  std::map<uint64_t, uint64_t> w;  // aligned word -> value
  uint64_t Get(uint64_t a) const {
    const auto it = w.find(a & ~7ull);
    return it == w.end() ? 0x5A5A0000ULL ^ (a & ~7ull) : it->second;
  }
  void Put(uint64_t a, uint8_t be, uint64_t d) {
    uint64_t v = Get(a);
    for (int i = 0; i < 8; ++i) {
      if (be >> i & 1) {
        v = (v & ~(0xFFull << (8 * i))) | (d & (0xFFull << (8 * i)));
      }
    }
    w[a & ~7ull] = v;
  }
};

struct Req {
  int op;
  uint64_t addr, wdata;
  uint8_t be;
};

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
  const std::unique_ptr<Vmuserisc_dcache> dut{new Vmuserisc_dcache{&context}};
  std::mt19937_64 rng(12345);
  auto rnd = [&](uint64_t n) { return rng() % n; };

  Mem golden;   // architectural memory
  Mem busmem;   // what the bus slave holds
  // I/O log: single beats the bus saw (addr, be, write, data).
  struct Beat { uint64_t addr; uint8_t be; bool write; uint64_t data; };
  std::deque<Beat> io_seen;
  bool bad_burst = false;

  // Address pool: lines that alias onto the 4 sets (stride 4*32)
  // in both windows, plus I/O addresses.
  std::vector<uint64_t> lines_fixed;
  for (int i = 0; i < 6; ++i) lines_fixed.push_back(kC0Base + uint64_t(i) * 4 * kLineBytes);
  for (int i = 0; i < 5; ++i) lines_fixed.push_back(kC0Base + 0x20 + uint64_t(i) * 4 * kLineBytes);
  for (int i = 0; i < 4; ++i) lines_fixed.push_back(kC1Base + 0x40 + uint64_t(i) * 4 * kLineBytes);
  lines_fixed.push_back(kC0Base + kC0Size - kLineBytes);  // last cacheable line
  const std::vector<uint64_t> io_fixed = {0x0, 0x800, 0x3000, 0x10000000, 0x80001000ULL,
                                    0x7FFFFFF8ULL, 0x0C200004ULL};
  // High PA bits: tag/index extraction must ignore nothing it
  // should not (all pool addresses are below 2^56).

  long checks = 0, n_load = 0, n_store = 0, n_clean = 0, n_io = 0;
  for (int phase = 0; phase < 12; ++phase) {
    MbusConfig cfg;
    cfg.seed = 100 + phase;
    switch (phase % 6) {
      case 0: cfg.lat_min = 1; cfg.lat_max = 1; break;
      case 1: cfg.lat_min = 1; cfg.lat_max = 12; cfg.gap_max = 3; break;
      case 2: cfg.lat_min = 2; cfg.lat_max = 6; cfg.ready_pct = 30; break;
      case 3: cfg.lat_min = 1; cfg.lat_max = 3; cfg.gap_max = 1; cfg.ready_pct = 60; break;
      case 4: cfg.lat_min = 5; cfg.lat_max = 20; cfg.ready_pct = 90; break;
      default: cfg.lat_min = 1; cfg.lat_max = 2; cfg.gap_max = 5; cfg.ready_pct = 50; break;
    }
    // Per-phase pools: the fixed lines plus random lines far up
    // in C1, and random I/O addresses (incl. PA bits 63:56 set).
    std::vector<uint64_t> lines = lines_fixed, io = io_fixed;
    for (int i = 0; i < 4; ++i) {
      lines.push_back(kC1Base | (rng() & (kC1Size - 1) & ~uint64_t(kLineBytes - 1)));
    }
    io.push_back((rng() & (kC1Base - 1) & ~uint64_t(7)) | 0x100000);
    io.push_back((rng() | (1ULL << 63)) & ~uint64_t(31));
    const bool cache_en = phase != 5;  // one phase with the strap off
    MbusModel bus(
        cfg,
        [&](uint64_t a, uint8_t be, bool, bool burst) {
          if (!burst) io_seen.push_back({a, be, false, 0});
          return busmem.Get(a);
        },
        [&](uint64_t a, uint8_t be, uint64_t d) {
          busmem.Put(a, be, d);
          // Single-beat writes are I/O; bursts are full lines.
          if (be != 0xFF || !Cacheable(a) || !cache_en) io_seen.push_back({a, be, true, d});
        });

    // Reset (the D$ is not cleaned across phases: reset drops
    // its contents, so flush first if anything may be dirty).
    dut->clk_i = 0;
    dut->rst_ni = 0;
    dut->cache_en_i = cache_en;
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
    Req cur{};
    std::deque<Beat> io_expect;
    int idle = 0;
    int ops_left = 3000;
    long cyc = 0;
    while (ops_left > 0 || have_req || pending) {
      if (++cyc > 2000000) {
        CHECK(false, "phase %d hang", phase);
        break;
      }
      // New request? (Allowed while the previous response is
      // arriving: the request then waits for req_ready.)
      if (!have_req && ops_left > 0 && idle == 0) {
        const int r = int(rnd(100));
        const bool last = ops_left == 1;
        if (last || r < 4) {
          cur = {kOpClean, 0, 0, 0};
        } else if (r < 14) {
          cur.op = rnd(2) ? kOpStore : kOpLoad;
          cur.addr = io[rnd(io.size())] + (rnd(2) ? 0 : 8 * rnd(4));
          cur.be = uint8_t(1u << rnd(8));
          cur.wdata = rng();
        } else {
          cur.op = (r < 55) ? kOpLoad : kOpStore;
          const uint64_t line = lines[rnd(lines.size())];
          cur.addr = line + 8 * rnd(kLineBytes / 8);
          const int sz = int(rnd(4));
          const int lane = int(rnd(8)) & ~((1 << sz) - 1);
          cur.be = (sz == 3) ? 0xFF : uint8_t(((1u << (1 << sz)) - 1) << lane);
          if (rnd(8) == 0) cur.be = uint8_t(rng());  // arbitrary lanes
          cur.addr |= uint64_t(lane);
          cur.wdata = rng();
        }
        have_req = true;
        --ops_left;
        idle = int(rnd(3));
      } else if (idle > 0) {
        --idle;
      }
      dut->req_valid_i = have_req;
      dut->req_addr_i = cur.addr;
      dut->req_op_i = cur.op;
      dut->req_wdata_i = cur.wdata;
      dut->req_be_i = cur.be;
      dut->clk_i = 0;
      MbusDrive(&bus, dut.get());
      dut->eval();

      // Response for the outstanding request.
      if (dut->rsp_valid_o) {
        CHECK(pending, "response with nothing outstanding");
        pending = false;
      }
      const bool fire = have_req && dut->req_ready_o;
      // Sample the bus beat before the edge.
      const MbusModel::Req br = MbusSample(dut.get());
      if (br.fire && br.len != 0 && !br.write && (br.addr % kLineBytes) != 0) bad_burst = true;
      if (br.fire && br.len != 0 && (!Cacheable(br.addr) || !cache_en)) bad_burst = true;
      if (br.fire && br.len != 0 && br.len != kLineBytes / 8 - 1) bad_burst = true;
      static Req inflight;
      static uint64_t expect_load;
      if (dut->rsp_valid_o && inflight.op == kOpLoad) {
        CHECK(dut->rsp_rdata_o == expect_load,
              "phase %d load 0x%llx got 0x%016llx want 0x%016llx", phase,
              (unsigned long long)inflight.addr,
              (unsigned long long)dut->rsp_rdata_o,
              (unsigned long long)expect_load);
        ++checks;
      }
      if (dut->rsp_valid_o && inflight.op == kOpClean) {
        // Memory must now be up to date for every line.
        for (uint64_t l : lines) {
          for (int b = 0; b < kLineBytes; b += 8) {
            CHECK(busmem.Get(l + b) == golden.Get(l + b),
                  "phase %d clean: 0x%llx bus 0x%016llx golden 0x%016llx",
                  phase, (unsigned long long)(l + b),
                  (unsigned long long)busmem.Get(l + b),
                  (unsigned long long)golden.Get(l + b));
            ++checks;
          }
        }
        // I/O beats so far must match, in order.
        CHECK(io_seen.size() == io_expect.size(), "phase %d io count %zu vs %zu",
              phase, io_seen.size(), io_expect.size());
        while (!io_seen.empty() && !io_expect.empty()) {
          const Beat s = io_seen.front(), e = io_expect.front();
          CHECK(s.addr == e.addr && s.be == e.be && s.write == e.write &&
                    (!s.write || s.data == e.data),
                "phase %d io beat 0x%llx/%02x/%d vs 0x%llx/%02x/%d", phase,
                (unsigned long long)s.addr, s.be, s.write,
                (unsigned long long)e.addr, e.be, e.write);
          io_seen.pop_front();
          io_expect.pop_front();
          ++checks;
        }
        io_seen.clear();
        io_expect.clear();
      }
      if (fire) {
        CHECK(!pending, "request accepted while one is outstanding");
        inflight = cur;
        pending = true;
        const bool c = cache_en && Cacheable(cur.addr);
        if (cur.op == kOpLoad) {
          expect_load = golden.Get(cur.addr);
          ++n_load;
          if (!c) { io_expect.push_back({cur.addr, cur.be, false, 0}); ++n_io; }
        } else if (cur.op == kOpStore) {
          golden.Put(cur.addr, cur.be, cur.wdata);
          ++n_store;
          if (!c) {
            io_expect.push_back({cur.addr, cur.be, true, cur.wdata});
            ++n_io;
          }
        } else {
          ++n_clean;
        }
        have_req = false;
      }
      dut->clk_i = 1;
      dut->eval();
      bus.Edge(br);
    }
    CHECK(!bad_burst, "phase %d illegal burst on the bus", phase);
  }
  std::printf("dcache_tb: %ld checks, %ld loads, %ld stores, %ld cleans, %ld I/O, %d errors\n",
              checks, n_load, n_store, n_clean, n_io, g_errors);
  dut->final();
  if (const char* cov = std::getenv("COV_FILE")) context.coveragep()->write(cov);
  if (g_errors != 0) {
    std::printf("DCACHE TB FAIL\n");
    return 1;
  }
  std::printf("DCACHE TB PASS\n");
  return 0;
}
