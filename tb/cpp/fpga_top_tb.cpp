// FPGA SoC top harness (issues #52, #62-#67): drives sigil_fpga_top
// the way the AWS F2 CL wrapper and host runtime do -- RAM is an AXI4
// slave memory model standing in for the Shell DDR4 / HBM
// (tb/cpp/axi4_slave_model.h: seeded latency, R gaps, AW/W/AR
// backpressure, AXI protocol checks), the host loads images while
// the SoC is held in reset, releases it, and drains / feeds the
// virtual-UART FIFOs.
//
// Builds: default 128 MiB RAM window over a flat model; with
// -DSIGIL_F2_MAP (fpga_top_tb_f2, -GRAM_SIZE=80 GiB) the real F2 map
// over a sparse model: DDR4 AXI [0, 64 GiB) and HBM AXI [64 GiB,
// 80 GiB) = SoC PA 0x8000_0000 .. 0x14_7FFF_FFFF.
//
// Usage: fpga_top_tb [max_cycles] --load 0xADDR=FILE [--load ...]
//          [--boot 0xADDR] [--no-cache] [--exit-string TEXT]
//          [--fail-string TEXT]
//          [--tohost 0xADDR] [--uart-log FILE] [--uart-in FILE]
//          [--uart-pop PCT] [--rerun N] [--reset-mid N] [--trace-traps]
//          [--engine-test] [--rtc-ns N] [--finisher] [--expect-fin V]
//          [--expect-err 0xADDR] [--check-bursts N] [--poke 0xADDR=0xVAL]
//          [--axi-lat A:B] [--axi-gap N] [--axi-ready PCT]
//          [--axi-seed S] [--axi-rlat A:B] [--axi-blat A:B]
//          [--axi-rw-race] [--axi-ooo] [--axi-early-b N]
//   (AXI slave model options: tb/cpp/axi4_slave_model.h)
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
//     byte (default 50). A low value fills the TX FIFO: the 16550 is
//     back-pressured and no byte may be lost (#63).
//   --engine-test: before the first release, drive the memory engine
//     (fill, address-pattern write, check, check with an injected
//     error) over ranges crossing 4 GiB and the DDR4/HBM boundary
//     (F2 map) and check the model's memory and the engine's counters.
//   --rtc-ns N: set the RTC time base before release (16 ns per cycle).
//   --finisher: the test finisher ends a run: --expect-fin (default
//     0x5555) passes, any other power-off fails, 0x7777 reboots (the
//     SoC is reset, the images reloaded -- other memory kept -- and
//     released again).
//   --expect-err ADDR: allow STATUS.mem_err; at the end the bridge's
//     first-error capture must be an out-of-window read of ADDR.
//   --check-bursts N: the UART must carry N "Bnn:" burst lines of the
//     f2_platform_test pattern, byte-exact.
//   --poke ADDR=VAL: 64-bit word written into RAM with the images.
// Every cycle: cycle_count_o must advance by one, mem_err_o (unless
// --expect-err) and uart_tx_overflow_o must stay low.
//   --fail-string: UART text that ends the run as a failure (after
//     the rest of that line, at most 1M cycles).
// Exit status: 0 pass, 1 fail (tohost != 1, fail string, harness check), 2
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
#ifdef SIGIL_F2_MAP
constexpr uint64_t kRamSize = 0x1400000000ULL;  // 80 GiB: DDR4 + HBM
constexpr uint64_t kDdrSize = 0x1000000000ULL;  // 64 GiB
#else
constexpr uint64_t kRamSize = 0x8000000ULL;   // 128 MiB (DTS)
#endif
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

// The f2_platform_test UART burst line n (without CR LF).
std::string BurstLine(int n) {
  std::string s = "B";
  s += char('0' + n / 10);
  s += char('0' + n % 10);
  s += ':';
  for (int j = 0; j < 56; ++j) s += char('a' + (n * 7 + j) % 26);
  return s;
}
}  // namespace

int main(int argc, char** argv) {
  uint64_t max_cycles = 400000000, boot_pc = 0x1000, tohost = 0;
  std::vector<std::pair<uint64_t, const char*>> loads;
  std::vector<std::pair<uint64_t, uint64_t>> pokes;
  const char* uart_log_path = nullptr;
  const char* uart_in_path = nullptr;
  std::string exit_string, fail_string;
  bool trace_traps = false, cache_en = true, engine_test = false;
  bool finisher = false;
  int uart_pop_pct = 50, reruns = 0, check_bursts = 0;
  uint64_t reset_mid = 0, rtc_ns = 0, expect_fin = 0x5555, expect_err = 0;
  bool have_expect_err = false;
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
    } else if (std::strcmp(argv[i], "--poke") == 0 && need(i)) {
      char* eq = std::strchr(argv[++i], '=');
      if (eq == nullptr) return 2;
      pokes.push_back({std::strtoull(argv[i], nullptr, 0), std::strtoull(eq + 1, nullptr, 0)});
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
    } else if (std::strcmp(argv[i], "--fail-string") == 0 && need(i)) {
      fail_string = argv[++i];
    } else if (std::strcmp(argv[i], "--trace-traps") == 0) {
      trace_traps = true;
    } else if (std::strcmp(argv[i], "--engine-test") == 0) {
      engine_test = true;
    } else if (std::strcmp(argv[i], "--rtc-ns") == 0 && need(i)) {
      rtc_ns = std::strtoull(argv[++i], nullptr, 0);
    } else if (std::strcmp(argv[i], "--finisher") == 0) {
      finisher = true;
    } else if (std::strcmp(argv[i], "--expect-fin") == 0 && need(i)) {
      expect_fin = std::strtoull(argv[++i], nullptr, 0);
    } else if (std::strcmp(argv[i], "--expect-err") == 0 && need(i)) {
      expect_err = std::strtoull(argv[++i], nullptr, 0);
      have_expect_err = true;
    } else if (std::strcmp(argv[i], "--check-bursts") == 0 && need(i)) {
      check_bursts = std::atoi(argv[++i]);
    } else if (argv[i][0] == '+') {
      // Verilator plusarg, handled by commandArgs.
    } else {
      max_cycles = std::strtoull(argv[i], nullptr, 0);
    }
  }
  if (loads.empty() || (exit_string.empty() && tohost == 0 && !finisher)) {
    std::fprintf(stderr,
                 "usage: %s [max_cycles] --load 0xADDR=FILE ... "
                 "(--exit-string TEXT | --tohost 0xADDR | --finisher)\n", argv[0]);
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
#ifdef SIGIL_F2_MAP
  SparseMem ram;
  ram.AddRegion(0, kDdrSize);                      // DDR4
  ram.AddRegion(kDdrSize, kRamSize - kDdrSize);    // HBM
  auto ram_write = [&](uint64_t a, const uint8_t* d, size_t n) { ram.WriteBlock(a, d, n); };
  auto ram_clear = [&]() { ram.Clear(); };
  auto ram_rd64 = [&](uint64_t a) { return ram.Read64(a); };
  auto ram_wr64 = [&](uint64_t a, uint64_t v) { ram.Write64(a, v); };
  Axi4SlaveModel axi(axi_cfg, kDw, &ram);
#else
  std::vector<uint8_t> ddr(kRamSize, 0);
  auto ram_write = [&](uint64_t a, const uint8_t* d, size_t n) { std::memcpy(&ddr[a], d, n); };
  auto ram_clear = [&]() { std::fill(ddr.begin(), ddr.end(), 0); };
  auto ram_rd64 = [&](uint64_t a) {
    uint64_t v;
    std::memcpy(&v, &ddr[a], 8);
    return v;
  };
  auto ram_wr64 = [&](uint64_t a, uint64_t v) { std::memcpy(&ddr[a], &v, 8); };
  Axi4SlaveModel axi(axi_cfg, kDw, kDdrBase, &ddr);
#endif
  // Images (and pokes) only; with clear = false the rest of RAM is kept
  // and, like sigil_host, images in the pmem window (0xC_8000_0000 ..
  // 0x10_7FFF_FFFF) are not reloaded (a reboot after a finisher 0x7777).
  auto load_all = [&](bool clear) {
    if (clear) ram_clear();
    for (size_t k = 0; k < loads.size(); ++k) {
      if (!clear && loads[k].first >= 0xC80000000ULL && loads[k].first < 0x1080000000ULL) continue;
      ram_write(loads[k].first - kRamBase, images[k].data(), images[k].size());
    }
    for (const auto& [a, v] : pokes) ram_wr64(a - kRamBase, v);
  };
  load_all(true);
  for (size_t k = 0; k < loads.size(); ++k) {
    std::fprintf(stderr, "loaded %zu bytes at 0x%llx from %s\n",
                 images[k].size(), U(loads[k].first), loads[k].second);
  }
  std::fprintf(stderr, "fpga_top_tb: %d-bit AXI, RAM window %llu MiB, %s, caches %s\n",
               kDw * 8, U(kRamSize >> 20), axi_cfg.Describe().c_str(),
               cache_en ? "on" : "off");

  // HTIF tohost snoop on the AXI write channel.
  int tohost_result = -1;  // -1 none, else the value written
  uint64_t tohost_val = 0;
  if (tohost != 0) {
    const uint64_t t = tohost - kRamBase + kDdrBase;
    axi.SetWriteObserver([&, t](uint64_t blk, const uint8_t* data, uint64_t strb) {
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
  dut->uart_tx_drop_i = 0;
  dut->err_clr_i = 0;
  dut->rtc_set_i = 0;
  dut->rtc_inc_i = 0x10000000u;  // 16 ns per cycle (62.5 MHz), Q8.24
  dut->eng_start_i = 0;
  AxiDrive(AxiS{}, dut.get(), kDw);
  for (int i = 0; i < 4; ++i) {
    dut->clk_i = static_cast<uint8_t>(i & 1);
    dut->eval();
  }
  dut->rst_ni = 1;

  // One clock cycle with the AXI model (inputs already set).
  auto step = [&]() {
    const AxiS s = axi.Outputs();
    AxiDrive(s, dut.get(), kDw);
    dut->clk_i = 0;
    dut->eval();
    const AxiM m = AxiSample(dut.get(), kDw);
    dut->clk_i = 1;
    dut->eval();
    axi.Edge(m);
  };
  for (int i = 0; i < 8; ++i) step();

  // ---- memory engine checks (SoC held) ---------------------------------
  int tb_fails = 0;
  auto check = [&](const char* what, uint64_t got, uint64_t exp) {
    if (got != exp) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: %s = 0x%llx, expected 0x%llx\n", what, U(got), U(exp));
      tb_fails++;
    }
  };
  auto engine = [&](int mode, uint64_t base, uint64_t size, uint64_t seed) {
    dut->eng_mode_i = mode;
    dut->eng_base_i = base;
    dut->eng_size_i = size;
    dut->eng_seed_i = seed;
    dut->eng_start_i = 1;
    step();
    dut->eng_start_i = 0;
    uint64_t n = 0;
    while (!dut->eng_done_o || dut->eng_busy_o) {
      step();
      if (++n > 50000000) {
        std::fprintf(stderr, "FPGA TOP TB FAIL: memory engine never finished\n");
        std::exit(1);
      }
    }
    std::fprintf(stderr,
                 "engine mode %d base 0x%llx size 0x%llx: %llu cycles (%.2f B/cycle), "
                 "mismatches %u first 0x%llx, resp errors %u, fail %d\n",
                 mode, U(base), U(size), U(dut->eng_cycles_o),
                 double(size) / double(dut->eng_cycles_o ? dut->eng_cycles_o : 1),
                 unsigned(dut->eng_mism_o), U(dut->eng_fail_addr_o),
                 unsigned(dut->eng_rerr_o), int(dut->eng_fail_o));
  };
  if (engine_test) {
#ifdef SIGIL_F2_MAP
    const uint64_t fill_base = 0x100000000ULL - 0x4000, fill_size = 0x8000;   // across 4 GiB
    const uint64_t pat_base = kDdrSize - 0x4000, pat_size = 0x8000;          // DDR4 end / HBM start
#else
    const uint64_t fill_base = 0x100000, fill_size = 0x8000;
    const uint64_t pat_base = 0x200000, pat_size = 0x8000;
#endif
    const uint64_t seed = 0x0123456789ABCDEFULL;
    for (uint64_t a = fill_base; a < fill_base + fill_size; a += 8) ram_wr64(a, ~a);
    engine(0, fill_base, fill_size, 0);  // fill zeros
    for (uint64_t a = fill_base; a < fill_base + fill_size; a += 8) {
      if (ram_rd64(a) != 0) {
        check("engine fill", ram_rd64(a), 0);
        break;
      }
    }
    check("fill errors", dut->eng_fail_o, 0);
    engine(2, fill_base, fill_size, 0);  // check zeros
    check("check zeros mismatches", dut->eng_mism_o, 0);
    engine(1, pat_base, pat_size, seed);  // address pattern
    for (uint64_t a = pat_base; a < pat_base + pat_size; a += 8) {
      if (ram_rd64(a) != (a ^ seed)) {
        check("engine pattern word", ram_rd64(a), a ^ seed);
        break;
      }
    }
    engine(3, pat_base, pat_size, seed);
    check("pattern check mismatches", dut->eng_mism_o, 0);
    check("pattern check fail", dut->eng_fail_o, 0);
    const uint64_t bad = pat_base + pat_size / 2 + 0x238;
    ram_wr64(bad, ram_rd64(bad) ^ 0x10);
    engine(3, pat_base, pat_size, seed);
    check("injected error: mismatches", dut->eng_mism_o, 1);
    check("injected error: address", dut->eng_fail_addr_o, bad);
    check("injected error: fail", dut->eng_fail_o, 1);
    engine(0, 0, 0, 0);  // size 0 completes at once
    check("size-0 run cycles <= 2", dut->eng_cycles_o <= 2, 1);
    load_all(true);
    if (tb_fails) return 1;
    std::fprintf(stderr, "FPGA TOP TB engine checks PASS\n");
  }
  if (rtc_ns != 0) {
    dut->rtc_set_ns_i = rtc_ns;
    dut->rtc_set_i = 1;
    step();
    dut->rtc_set_i = 0;
    step();
    check("rtc after set", dut->rtc_ns_o >= rtc_ns && dut->rtc_ns_o < rtc_ns + 100, 1);
  }

  // Phases: HOLD (load done; keep reset requested for a while),
  // RUN, RESETTING (reset requested, waiting for soc_in_reset_o).
  enum Phase { HOLD, RUN, RESETTING } phase = HOLD;
  uint64_t phase_cycles = 0, run_start = 0, prev_count = 0;
  bool have_count = false;
  int runs_left = reruns;
  int run_idx = 0, reboots = 0;
  bool reboot_pending = false;
  std::string uart_out, all_out;
  int rc = 2;
  uint64_t cycle = 0, fail_at = 0;
  for (; cycle < max_cycles; ++cycle) {
    if (fail_at != 0 && cycle - fail_at > 1000000) {
      std::fprintf(stderr, "\nFPGA TOP TB FAIL: fail string at %llu cycles after release\n",
                   U(fail_at - run_start));
      rc = 1;
      break;
    }
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
    if (dut->mem_err_o && !have_expect_err) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: mem_err_o (AXI error response), first: "
                   "addr 0x%llx info 0x%08x count %u\n", U(dut->err_addr_o),
                   unsigned(dut->err_info_o), unsigned(dut->err_count_o));
      return 1;
    }
    if (dut->uart_tx_overflow_o) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: virtual UART TX FIFO overflow\n");
      return 1;
    }
    const bool fin = dut->fin_event_o;
    const uint32_t fin_val = dut->fin_value_o;
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
      if (check_bursts) all_out.push_back(char(tx_byte));
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
      if (pop && fail_at == 0 && !fail_string.empty() &&
          uart_out.find(fail_string) != std::string::npos) {
        fail_at = cycle;
      }
      if (pop && fail_at != 0 && tx_byte == '\n') {
        std::fflush(stdout);
        std::fprintf(stderr, "\nFPGA TOP TB FAIL: fail string at %llu cycles after release\n",
                     U(fail_at - run_start));
        rc = 1;
        break;
      }
      if (finisher && fin && !dut->uart_tx_valid_o && phase_cycles > 4) {
        // Finisher written and the UART drained.
        std::fflush(stdout);
        if ((fin_val & 0xFFFF) == 0x7777) {
          std::fprintf(stderr, "\nfinisher: reboot (0x%08x) at %llu cycles after release\n",
                       fin_val, U(cycle - run_start));
          reboots++;
          reboot_pending = true;
          dut->soc_reset_req_i = 1;
          phase = RESETTING;
          phase_cycles = 0;
          continue;
        }
        std::fprintf(stderr, "\nfinisher: 0x%08x (%s, code %u) at %llu cycles after release\n",
                     fin_val, (fin_val & 0xFFFF) == 0x5555 ? "power off" : "fail",
                     fin_val >> 16, U(cycle - run_start));
        if (fin_val != expect_fin) {
          std::fprintf(stderr, "FPGA TOP TB FAIL: finisher 0x%08x, expected 0x%08llx\n",
                       fin_val, U(expect_fin));
          rc = 1;
          break;
        }
        passed = true;
      }
      passed = passed || (tohost_result == 1) ||
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
                   run_idx, tohost_result == 1 ? "tohost=1" : finisher ? "finisher" : "exit string",
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
      load_all(!reboot_pending);
      reboot_pending = false;
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
  if (rc == 0 && have_expect_err) {
    const uint32_t info = dut->err_info_o;
    std::fprintf(stderr, "bridge error capture: addr 0x%llx info 0x%08x count %u\n",
                 U(dut->err_addr_o), info, unsigned(dut->err_count_o));
    if (!dut->mem_err_o || dut->err_addr_o != expect_err || !((info >> 31) & 1) ||
        !((info >> 29) & 1) || ((info >> 30) & 1)) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: expected an out-of-window read of 0x%llx\n",
                   U(expect_err));
      rc = 1;
    }
    // Clear and check.
    dut->err_clr_i = 1;
    step();
    dut->err_clr_i = 0;
    step();
    if (dut->mem_err_o || dut->err_info_o != 0 || dut->err_count_o != 0) {
      std::fprintf(stderr, "FPGA TOP TB FAIL: err_clr_i did not clear the capture\n");
      rc = 1;
    }
  }
  if (rc == 0 && check_bursts) {
    int seen = 0;
    for (int n = 0; n < check_bursts; ++n) {
      const std::string want = BurstLine(n) + "\r\n";
      const size_t at = all_out.find(want.substr(0, 4));
      if (at == std::string::npos || all_out.compare(at, want.size(), want) != 0) {
        std::fprintf(stderr, "FPGA TOP TB FAIL: UART burst line %d missing or corrupt: \"%s\"\n",
                     n, at == std::string::npos ? "" : all_out.substr(at, want.size()).c_str());
        rc = 1;
        break;
      }
      seen++;
    }
    if (rc == 0) std::fprintf(stderr, "UART bursts: %d lines byte-exact\n", seen);
  }
  if (rc == 0 && finisher) std::fprintf(stderr, "reboots: %d\n", reboots);
  std::fprintf(stderr, "%s\n", axi.Stats().c_str());
  // The mbus is one transaction at a time and a write is acknowledged
  // only after its B, so the bridge must never issue a read that
  // overlaps a write still waiting for its B (--axi-rw-race counts
  // them; AXI itself gives no read/write channel ordering).
  if (axi.rw_races() != 0) {
    std::fprintf(stderr, "FPGA TOP TB FAIL: %llu AXI reads overtook an unacknowledged write\n",
                 U(axi.rw_races()));
    if (rc == 0) rc = 1;
  }
  if (uart_log) std::fclose(uart_log);
  dut->final();
  return rc;
}
