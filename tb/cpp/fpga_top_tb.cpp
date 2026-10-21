// FPGA SoC top harness (issue #52, FPGA F1): drives sigil_fpga_top
// the way the AWS F2 CL wrapper (#54) and host runtime will --
// RAM is an AXI4 slave memory model standing in for the Shell DDR4
// (tb/cpp/axi4_slave_model.h: seeded latency, R gaps, AW/W/AR
// backpressure, AXI protocol checks), the host loads images while
// the SoC is held in reset, releases it, and drains / feeds the
// virtual-UART FIFOs.
//
// Usage: fpga_top_tb [max_cycles] --load 0xADDR=FILE [--load ...]
//          [--boot 0xADDR] [--no-cache] [--exit-string TEXT]
//          [--tohost 0xADDR] [--uart-log FILE] [--uart-in FILE]
//          [--uart-pop PCT] [--rerun N] [--reset-mid N] [--trace-traps]
//          [--axi-lat A:B] [--axi-gap N] [--axi-ready PCT]
//          [--axi-seed S]
//   --tohost: riscv-tests HTIF exit -- the first nonzero write to
//     that RAM address seen on the AXI W channel ends the run (1 =
//     pass). Needs --no-cache (with the L1 on, tohost may never be
//     written back).
//   --rerun N: after a pass, request SoC reset (soc_reset_req_i),
//     wait for soc_in_reset_o (the bridge must quiesce with the AXI
//     side idle), reload the images and run again, N more times.
//   --reset-mid N: in the first run, request SoC reset N cycles
//     after release (mid-traffic: the bridge must finish the
//     transaction in flight before the SoC is reset), then reload
//     and start over; this aborted run does not count.
//   --uart-pop PCT: probability per cycle that the host pops a TX
//     byte (default 50).
// Every cycle: cycle_count_o must advance by one, mem_err_o and
// uart_tx_overflow_o must stay low.
// Exit status: 0 pass, 1 fail (tohost != 1, harness check), 2
// timeout/usage, 4 AXI protocol violation.
#include "Vsigil_fpga_top.h"
#include "verilated.h"
#include "axi4_slave_model.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <memory>
#include <random>
#include <string>
#include <vector>

#ifndef AXI_DW_BYTES
#define AXI_DW_BYTES 8
#endif

namespace {
constexpr uint64_t kRamBase = 0x80000000ULL;  // SoC address
constexpr uint64_t kRamSize = 0x8000000ULL;   // 128 MiB (DTS)
constexpr uint64_t kDdrBase = 0x0;            // DDR_BASE (default)
constexpr int kDw = AXI_DW_BYTES;

std::vector<uint8_t> ReadFile(const char* path, bool* ok) {
  std::vector<uint8_t> data;
  FILE* f = std::fopen(path, "rb");
  *ok = f != nullptr;
  if (!*ok) return data;
  uint8_t buf[65536];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0) {
    data.insert(data.end(), buf, buf + n);
  }
  std::fclose(f);
  return data;
}
unsigned long long U(uint64_t v) { return static_cast<unsigned long long>(v); }
}  // namespace

int main(int argc, char** argv) {
  uint64_t max_cycles = 400000000, boot_pc = 0x1000, tohost = 0;
  std::vector<std::pair<uint64_t, const char*>> loads;
  const char* uart_log_path = nullptr;
  const char* uart_in_path = nullptr;
  std::string exit_string;
  bool trace_traps = false, cache_en = true;
  int uart_pop_pct = 50, reruns = 0;
  uint64_t reset_mid = 0;
  AxiConfig axi_cfg;
  for (int i = 1; i < argc; ++i) {
    auto need = [&](int i) { return i + 1 < argc; };
    if (const int n = axi_cfg.Parse(argc, argv, i)) {
      i += n - 1;
    } else if (std::strcmp(argv[i], "--no-cache") == 0) {
      cache_en = false;
    } else if (std::strcmp(argv[i], "--load") == 0 && need(i)) {
      char* eq = std::strchr(argv[++i], '=');
      if (eq == nullptr) {
        std::fprintf(stderr, "--load wants 0xADDR=FILE\n");
        return 2;
      }
      loads.push_back({std::strtoull(argv[i], nullptr, 0), eq + 1});
    } else if (std::strcmp(argv[i], "--boot") == 0 && need(i)) {
      boot_pc = std::strtoull(argv[++i], nullptr, 0);
    } else if (std::strcmp(argv[i], "--tohost") == 0 && need(i)) {
      tohost = std::strtoull(argv[++i], nullptr, 0);
    } else if (std::strcmp(argv[i], "--uart-log") == 0 && need(i)) {
      uart_log_path = argv[++i];
    } else if (std::strcmp(argv[i], "--uart-in") == 0 && need(i)) {
      uart_in_path = argv[++i];
    } else if (std::strcmp(argv[i], "--uart-pop") == 0 && need(i)) {
      uart_pop_pct = std::atoi(argv[++i]);
    } else if (std::strcmp(argv[i], "--reset-mid") == 0 && need(i)) {
      reset_mid = std::strtoull(argv[++i], nullptr, 0);
    } else if (std::strcmp(argv[i], "--rerun") == 0 && need(i)) {
      reruns = std::atoi(argv[++i]);
    } else if (std::strcmp(argv[i], "--exit-string") == 0 && need(i)) {
      exit_string = argv[++i];
    } else if (std::strcmp(argv[i], "--trace-traps") == 0) {
      trace_traps = true;
    } else if (argv[i][0] == '+') {
      // Verilator plusarg, handled by commandArgs.
    } else {
      max_cycles = std::strtoull(argv[i], nullptr, 0);
    }
  }
  if (loads.empty() || (exit_string.empty() && tohost == 0)) {
    std::fprintf(stderr,
                 "usage: %s [max_cycles] --load 0xADDR=FILE ... "
                 "(--exit-string TEXT | --tohost 0xADDR)\n", argv[0]);
    return 2;
  }
  std::vector<std::vector<uint8_t>> images;
  for (const auto& [addr, path] : loads) {
    bool ok;
    images.push_back(ReadFile(path, &ok));
    if (!ok || addr < kRamBase || addr - kRamBase + images.back().size() > kRamSize) {
      std::fprintf(stderr, "cannot load %s at 0x%llx\n", path, U(addr));
      return 2;
    }
  }
  std::vector<uint8_t> ddr(kRamSize, 0);
  auto load_all = [&]() {
    std::fill(ddr.begin(), ddr.end(), 0);
    for (size_t k = 0; k < loads.size(); ++k) {
      std::memcpy(&ddr[loads[k].first - kRamBase], images[k].data(),
                  images[k].size());
    }
  };
  load_all();
  for (size_t k = 0; k < loads.size(); ++k) {
    std::fprintf(stderr, "loaded %zu bytes at 0x%llx from %s\n",
                 images[k].size(), U(loads[k].first), loads[k].second);
  }
  std::fprintf(stderr, "fpga_top_tb: %d-bit AXI, %s, caches %s\n", kDw * 8,
               axi_cfg.Describe().c_str(), cache_en ? "on" : "off");

  Axi4SlaveModel axi(axi_cfg, kDw, kDdrBase, &ddr);
  // HTIF tohost snoop on the AXI write channel.
  int tohost_result = -1;  // -1 none, else the value written
  uint64_t tohost_val = 0;
  if (tohost != 0) {
    const uint64_t t = tohost - kRamBase + kDdrBase;
    axi.SetWriteObserver([&](uint64_t blk, const uint8_t* data, uint64_t strb) {
      if (t < blk || t >= blk + kDw) return;
      const int off = int(t - blk);
      uint64_t v = 0;
      bool any = false;
      for (int k = 0; k < 8 && off + k < kDw; ++k) {
        if ((strb >> (off + k)) & 1) {
          v |= uint64_t(data[off + k]) << (8 * k);
          any = true;
        }
      }
      if (any && v != 0 && tohost_result < 0) {
        tohost_val = v;
        tohost_result = (v == 1) ? 1 : 0;
      }
    });
  }

  FILE* uart_log = uart_log_path ? std::fopen(uart_log_path, "wb") : nullptr;
  std::vector<uint8_t> rx_bytes;
  if (uart_in_path != nullptr) {
    bool ok;
    rx_bytes = ReadFile(uart_in_path, &ok);
    if (!ok) {
      std::fprintf(stderr, "cannot open %s\n", uart_in_path);
      return 2;
    }
  }
  std::deque<uint8_t> rxq(rx_bytes.begin(), rx_bytes.end());
  std::mt19937_64 host_rng(axi_cfg.seed ^ 0x5157);

  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vsigil_fpga_top> dut{new Vsigil_fpga_top{&context}};
  dut->clk_i = 0;
  dut->rst_ni = 0;
  dut->soc_reset_req_i = 1;
  dut->boot_pc_i = boot_pc;
  dut->cache_en_i = cache_en ? 1 : 0;
  dut->uart_tx_pop_i = 0;
  dut->uart_rx_data_i = 0;
  dut->uart_rx_push_i = 0;
  AxiDrive(AxiS{}, dut.get(), kDw);
  for (int i = 0; i < 4; ++i) {
    dut->clk_i = static_cast<uint8_t>(i & 1);
    dut->eval();
  }
  dut->rst_ni = 1;

  // Phases: HOLD (load done; keep reset requested for a while),
  // RUN, RESETTING (reset requested, waiting for soc_in_reset_o).
  enum Phase { HOLD, RUN, RESETTING } phase = HOLD;
  uint64_t phase_cycles = 0, run_start = 0, prev_count = 0;
  bool have_count = false;
  int runs_left = reruns;
  int run_idx = 0;
  std::string uart_out;
  int rc = 2;
  uint64_t cycle = 0;
  for (; cycle < max_cycles; ++cycle) {
    // Host side of the control interface (inputs for this cycle).
    if (phase == HOLD && phase_cycles >= 64 && dut->soc_in_reset_o) {
      // Images are loaded (backdoor, as the host's DMA/PCIe writes
      // would be); release the SoC.
      dut->soc_reset_req_i = 0;
      phase = RUN;
      phase_cycles = 0;
      run_start = cycle;
      uart_out.clear();
      rxq.assign(rx_bytes.begin(), rx_bytes.end());
      tohost_result = -1;
    }
    const bool pop = dut->uart_tx_valid_o &&
                     int(host_rng() % 100) < uart_pop_pct;
    dut->uart_tx_pop_i = pop;
    dut->uart_rx_push_i = 0;
    if (phase == RUN && !rxq.empty() && !dut->uart_rx_full_o) {
      dut->uart_rx_data_i = rxq.front();
      dut->uart_rx_push_i = 1;
    }
    const AxiS s = axi.Outputs();
    AxiDrive(s, dut.get(), kDw);
    dut->clk_i = 0;
    dut->eval();
    // Samples before the edge.
    const AxiM m = AxiSample(dut.get(), kDw);
    const uint8_t tx_byte = dut->uart_tx_data_o;
    const bool rx_taken = dut->uart_rx_push_i && !dut->uart_rx_full_o;
    if (trace_traps && dut->trap_o) {
      std::fprintf(stderr, "trap cy=%llu cause=0x%llx pc=0x%llx\n", U(cycle),
                   U(dut->trap_cause_o), U(dut->trap_pc_o));
    }
    if (have_count && dut->cycle_count_o != prev_count + 1) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: cycle_count_o %llu after %llu\n",
                   U(dut->cycle_count_o), U(prev_count));
      return 1;
    }
    prev_count = dut->cycle_count_o;
    // Counting starts when the synchronized rst_ni releases.
    have_count = have_count || prev_count != 0;
    if (dut->mem_err_o) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: mem_err_o (AXI error response)\n");
      return 1;
    }
    if (dut->uart_tx_overflow_o) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: virtual UART TX FIFO overflow\n");
      return 1;
    }
    dut->clk_i = 1;
    dut->eval();
    axi.Edge(m);
    phase_cycles++;
    if (rx_taken) rxq.pop_front();
    if (pop) {
      std::fputc(tx_byte, stdout);
      if (tx_byte == '\n') std::fflush(stdout);
      if (uart_log) std::fputc(tx_byte, uart_log);
      if (phase == RUN) uart_out.push_back(char(tx_byte));
      if (uart_out.size() > (1u << 20)) uart_out.erase(0, uart_out.size() - 1024);
    }

    bool passed = false;
    if (phase == RUN) {
      if (tohost_result == 0) {
        std::fprintf(stderr, "\nFPGA TOP TB FAIL: tohost = 0x%llx (test %llu)\n",
                     U(tohost_val), U(tohost_val >> 1));
        rc = 1;
        break;
      }
      passed = (tohost_result == 1) ||
               (!exit_string.empty() && pop &&
                uart_out.find(exit_string) != std::string::npos);
    }
    if (phase == RUN && reset_mid != 0 && cycle - run_start == reset_mid) {
      std::fflush(stdout);
      std::fprintf(stderr, "\nreset requested mid-run at %llu cycles after release\n",
                   U(reset_mid));
      reset_mid = 0;
      dut->soc_reset_req_i = 1;
      phase = RESETTING;
      phase_cycles = 0;
    } else if (passed) {
      std::fflush(stdout);
      std::fprintf(stderr,
                   "\nFPGA TOP TB PASS run %d (%s at %llu cycles after reset "
                   "release)\n",
                   run_idx, tohost_result == 1 ? "tohost=1" : "exit string",
                   U(cycle - run_start));
      if (runs_left == 0) {
        rc = 0;
        break;
      }
      runs_left--;
      run_idx++;
      dut->soc_reset_req_i = 1;
      phase = RESETTING;
      phase_cycles = 0;
    } else if (phase == RESETTING && dut->soc_in_reset_o) {
      if (!axi.Idle()) {
        std::fprintf(stderr, "FPGA TOP TB FAIL: SoC reset with AXI traffic in flight\n");
        return 1;
      }
      std::fprintf(stderr, "soc reset after %llu cycles of quiesce; reloading\n",
                   U(phase_cycles));
      load_all();
      phase = HOLD;
      phase_cycles = 0;
    } else if (phase == RESETTING && phase_cycles > 1000000) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: SoC reset never took effect\n");
      return 1;
    }
  }
  std::fflush(stdout);
  if (rc == 2) {
    std::fprintf(stderr, "\nFPGA TOP TB TIMEOUT after %llu cycles\n", U(max_cycles));
  }
  std::fprintf(stderr, "%s\n", axi.Stats().c_str());
  if (uart_log) std::fclose(uart_log);
  dut->final();
  return rc;
}
