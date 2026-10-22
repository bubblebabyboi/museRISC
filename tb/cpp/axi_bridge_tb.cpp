// Unit testbench for sigil_mbus_axi4 (issue #52): a randomized
// mbus master (the role of sigil_soc_top's mem_* port) against the
// AXI4 slave model (tb/cpp/axi4_slave_model.h) with seeded random
// latency, R gaps and AW/W/AR backpressure, for any AXI data width
// the build selects (-GAXI_DATA_W=..., -DAXI_DW_BYTES=...).
//
// Traffic, like the L1 caches + uncached accesses: single-beat
// reads (random lanes, random req_inst), 8-beat line-burst reads,
// single-beat writes with random byte enables, 8-beat line write-
// backs (each beat with its own address, random strobes, random
// bubbles between beats), plus random quiesce_i pulses. Checks:
//   - every read beat equals the reference memory;
//   - beat counts and rsp_last (len+1 read beats, one write ack);
//   - no response outside a transaction or in the cycle the
//     request completes (mbus rule);
//   - no request accepted while quiesce_i holds an idle bridge,
//     and idle_o low while a transaction is in progress;
//   - AR/AW address = AXI_BASE + window offset, ARPROT[2] = inst;
//   - err_o stays low;
//   - the AXI rules in the slave model.
//
// Usage: axi_bridge_tb [--txns N] [--quiesce PCT] [axi options]
// Exit 0 on PASS, 1 on a data/protocol mismatch, 4 on an AXI rule.
#include "Vsigil_mbus_axi4.h"
#include "verilated.h"
#include "axi4_slave_model.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <random>
#include <vector>

#ifndef AXI_DW_BYTES
#define AXI_DW_BYTES 8
#endif

namespace {
// Must match the build's -G overrides (sim/Makefile axibridge).
constexpr uint64_t kMemBase = 0x80000000ULL;  // MEM_BASE
constexpr uint64_t kWindow = 0x10000ULL;      // MEM_SIZE
constexpr uint64_t kAxiBase = 0x40000ULL;     // AXI_BASE
constexpr int kDw = AXI_DW_BYTES;

int g_fail = 0;
void Fail(uint64_t cyc, const char* msg) {
  std::fprintf(stderr, "AXI BRIDGE TB FAIL at cycle %llu: %s\n",
               static_cast<unsigned long long>(cyc), msg);
  if (++g_fail > 10) std::exit(1);
}
}  // namespace

int main(int argc, char** argv) {
  AxiConfig cfg;
  uint64_t txns = 20000;
  int quiesce_pct = 2;
  for (int i = 1; i < argc; ++i) {
    if (const int n = cfg.Parse(argc, argv, i)) {
      i += n - 1;
    } else if (std::strcmp(argv[i], "--txns") == 0 && i + 1 < argc) {
      txns = std::strtoull(argv[++i], nullptr, 0);
    } else if (std::strcmp(argv[i], "--quiesce") == 0 && i + 1 < argc) {
      quiesce_pct = std::atoi(argv[++i]);
    }
  }
  std::mt19937_64 rng(cfg.seed * 7919 + 17);
  auto rnd = [&](uint64_t n) { return n ? rng() % n : 0; };

  // AXI memory (the model's) and the reference image of the window.
  std::vector<uint8_t> mem(kWindow);
  for (auto& b : mem) b = uint8_t(rng());
  std::vector<uint8_t> ref = mem;
  Axi4SlaveModel axi(cfg, kDw, kAxiBase, &mem);

  VerilatedContext ctx;
  ctx.commandArgs(argc, argv);
  const std::unique_ptr<Vsigil_mbus_axi4> dut{new Vsigil_mbus_axi4{&ctx}};
  dut->clk_i = 0;
  dut->rst_ni = 0;
  dut->quiesce_i = 0;
  dut->req_valid_i = 0;
  AxiDrive(AxiS{}, dut.get(), kDw);
  for (int i = 0; i < 4; ++i) {
    dut->clk_i = uint8_t(i & 1);
    dut->eval();
  }
  dut->rst_ni = 1;

  // Master state.
  enum Kind { RD1, RDL, WR1, WRL };
  bool active = false;     // a transaction is in progress
  bool req_done = false;   // all request beats accepted
  bool offering = false;   // a beat is on the request channel
  Kind kind = RD1;
  uint64_t addr = 0;       // first beat address (window offset)
  int beat = 0, nbeats = 1, rsp_beats = 0;
  bool inst = false;
  uint64_t wdata = 0;
  uint8_t be = 0xFF;
  int idle_gap = 0;
  bool quiesce = false;
  uint64_t done = 0, n_rd1 = 0, n_rdl = 0, n_wr1 = 0, n_wrl = 0, n_q = 0;
  uint64_t cyc = 0;
  const uint64_t max_cyc = txns * 400 + 100000;
  bool ar_seen = false, aw_seen = false;

  while (done < txns && cyc < max_cyc) {
    // Quiesce pulses (only change between transactions or anytime:
    // the bridge must finish what it started either way).
    if (rnd(1000) < uint64_t(quiesce_pct) * 10) {
      quiesce = !quiesce;
      if (quiesce) n_q++;
    }
    if (quiesce && rnd(8) == 0) quiesce = false;
    // Start a new transaction.
    if (!active && idle_gap == 0) {
      kind = Kind(rnd(4));
      nbeats = (kind == RDL || kind == WRL) ? 8 : 1;
      addr = (kind == RDL || kind == WRL) ? (rnd(kWindow) & ~uint64_t(63))
                                          : (rnd(kWindow) & ~uint64_t(7));
      inst = (kind == RD1 || kind == RDL) && rnd(2);
      active = true;
      req_done = false;
      beat = 0;
      rsp_beats = 0;
      offering = false;
      ar_seen = aw_seen = false;
    }
    if (!active && idle_gap > 0) idle_gap--;
    // Offer the next request beat (writes may bubble between beats).
    if (active && !req_done && !offering) {
      if (beat == 0 || rnd(4) != 0) {
        offering = true;
        wdata = rng();
        be = (kind == WR1 || kind == WRL) ? uint8_t(rnd(255) + 1)
                                          : uint8_t(rnd(255) + 1);
      }
    }
    const uint64_t baddr = addr + (kind == WRL ? 8 * uint64_t(beat) : 0);
    dut->quiesce_i = quiesce;
    dut->req_valid_i = offering;
    dut->req_addr_i = kMemBase + baddr;
    dut->req_write_i = (kind == WR1 || kind == WRL);
    dut->req_len_i = uint8_t(nbeats - 1);
    dut->req_wdata_i = wdata;
    dut->req_be_i = be;
    dut->req_last_i = (kind == WRL) ? (beat == nbeats - 1) : 1;
    dut->req_inst_i = inst;

    const AxiS s = axi.Outputs();
    AxiDrive(s, dut.get(), kDw);
    dut->clk_i = 0;
    dut->eval();
    const AxiM m = AxiSample(dut.get(), kDw);
    const bool fire = offering && dut->req_ready_o;
    const bool rsp = dut->rsp_valid_o;
    const uint64_t rdata = dut->rsp_rdata_o;
    const bool rlast = dut->rsp_last_o;
    const bool idle = dut->idle_o;
    char msg[200];

    // Checks on this cycle's outputs.
    if (quiesce && idle && dut->req_ready_o) Fail(cyc, "req_ready while quiesced and idle");
    if (active && (beat > 0 || req_done) && idle) Fail(cyc, "idle_o during a transaction");
    if (dut->err_o) Fail(cyc, "err_o set");
    if (m.arvalid && s.arready) {
      const uint64_t want = kAxiBase + (addr & ~uint64_t(nbeats > 1 ? kDw - 1 : 7));
      if (!active || ar_seen || m.araddr != want) {
        std::snprintf(msg, sizeof msg, "AR addr 0x%llx want 0x%llx",
                      (unsigned long long)m.araddr, (unsigned long long)want);
        Fail(cyc, msg);
      }
      if (((m.arprot >> 2) & 1) != (inst ? 1 : 0)) Fail(cyc, "ARPROT[2] != req_inst");
      ar_seen = true;
    }
    if (m.awvalid && s.awready) {
      const uint64_t want = kAxiBase + (addr & ~uint64_t(nbeats > 1 ? kDw - 1 : 7));
      if (!active || aw_seen || m.awaddr != want) Fail(cyc, "AW address/count");
      aw_seen = true;
    }
    if (rsp) {
      if (!active || !req_done) {
        Fail(cyc, "response outside a transaction / before the request completed");
      } else if (kind == RD1 || kind == RDL) {
        const uint64_t a = (kind == RDL ? addr + 8 * uint64_t(rsp_beats) : addr) & ~uint64_t(7);
        uint64_t want = 0;
        for (int k = 0; k < 8; ++k) want |= uint64_t(ref[a + k]) << (8 * k);
        if (rdata != want) {
          std::snprintf(msg, sizeof msg,
                        "read beat %d at +0x%llx: got 0x%016llx want 0x%016llx",
                        rsp_beats, (unsigned long long)a,
                        (unsigned long long)rdata, (unsigned long long)want);
          Fail(cyc, msg);
        }
        if (rlast != (rsp_beats == nbeats - 1)) Fail(cyc, "rsp_last on wrong read beat");
      } else if (!rlast) {
        Fail(cyc, "write ack without rsp_last");
      }
    }
    dut->clk_i = 1;
    dut->eval();
    axi.Edge(m);

    // Advance the master.
    if (rsp && active && req_done) {
      rsp_beats++;
      const bool is_rd = (kind == RD1 || kind == RDL);
      if ((is_rd && rsp_beats == nbeats) || !is_rd) {
        active = false;
        done++;
        idle_gap = int(rnd(4));
        (kind == RD1 ? n_rd1 : kind == RDL ? n_rdl : kind == WR1 ? n_wr1 : n_wrl)++;
      }
    }
    if (fire) {
      if (kind == WR1 || kind == WRL) {
        for (int k = 0; k < 8; ++k) {
          if ((be >> k) & 1) ref[(baddr & ~uint64_t(7)) + k] = uint8_t(wdata >> (8 * k));
        }
      }
      offering = false;
      beat++;
      if (kind != WRL || beat == nbeats) req_done = true;
    }
    cyc++;
  }
  dut->final();
  if (done < txns) {
    std::fprintf(stderr, "AXI BRIDGE TB FAIL: timeout after %llu cycles (%llu/%llu txns)\n",
                 (unsigned long long)cyc, (unsigned long long)done,
                 (unsigned long long)txns);
    return 1;
  }
  if (mem != ref) {
    std::fprintf(stderr, "AXI BRIDGE TB FAIL: final memory differs from reference\n");
    return 1;
  }
  if (g_fail) return 1;
  std::printf("AXI BRIDGE TB PASS [%d-bit AXI, %s]: %llu txns (%llu rd1, %llu rd-line, "
              "%llu wr1, %llu wr-line, %llu quiesce pulses) in %llu cycles; %s\n",
              kDw * 8, cfg.Describe().c_str(), (unsigned long long)done,
              (unsigned long long)n_rd1, (unsigned long long)n_rdl,
              (unsigned long long)n_wr1, (unsigned long long)n_wrl,
              (unsigned long long)n_q, (unsigned long long)cyc,
              axi.Stats().c_str());
  return 0;
}
