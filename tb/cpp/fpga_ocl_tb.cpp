// sigil_fpga_ocl harness (issue #54, FPGA F3): the core-clock half of
// the AWS F2 CL driven only through its OCL AXI4-Lite registers, the
// way fpga/host/sigil_host.c drives the FPGA, with the AXI4 DDR model
// (tb/cpp/axi4_slave_model.h, 512-bit) behind the bridge. Checks the
// register map reset values, scratch/boot-PC read-write, the cycle
// counter (64-bit snapshot read; delta against the harness clock), the
// RX FIFO, and runs a firmware image to its pass string over the
// virtual UART (TX popped through UART_TX_DATA, RX pushed through
// UART_RX_DATA), then holds the SoC again through CTRL.
//
// Usage: fpga_ocl_tb [max_cycles] --load 0xADDR=FILE [--load ...]
//          --exit-string TEXT [--uart-in FILE] [--axi-lat A:B]
//          [--axi-gap N] [--axi-ready PCT] [--axi-seed S]
// Exit status: 0 pass, 1 fail, 2 timeout/usage, 4 AXI protocol error.
#include "Vsigil_fpga_ocl.h"
#include "verilated.h"
#include "axi4_slave_model.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr uint64_t kRamBase = 0x80000000ULL;
constexpr uint64_t kRamSize = 0x8000000ULL;
constexpr int kDw = 64;  // 512-bit AXI, as in the CL

enum : uint32_t {
  R_ID = 0x000, R_VERSION = 0x004, R_CTRL = 0x008, R_STATUS = 0x00C,
  R_BOOT_PC_LO = 0x010, R_BOOT_PC_HI = 0x014, R_CYCLE_LO = 0x018,
  R_CYCLE_HI = 0x01C, R_TRAP_COUNT = 0x020, R_CLK_KHZ = 0x024,
  R_SCRATCH = 0x03C, R_TX_DATA = 0x040, R_TX_STATUS = 0x044,
  R_RX_DATA = 0x048, R_RX_STATUS = 0x04C,
};

std::vector<uint8_t> ReadFile(const char* path, bool* ok) {
  std::vector<uint8_t> d;
  FILE* f = std::fopen(path, "rb");
  *ok = f != nullptr;
  if (!*ok) return d;
  uint8_t buf[65536];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) d.insert(d.end(), buf, buf + n);
  std::fclose(f);
  return d;
}

struct Harness {
  VerilatedContext ctx;
  std::unique_ptr<Vsigil_fpga_ocl> dut;
  Axi4SlaveModel* axi;
  uint64_t cycle = 0, max_cycles;
  int fails = 0;

  Harness(Axi4SlaveModel* a, uint64_t maxc) : dut(new Vsigil_fpga_ocl{&ctx}), axi(a), max_cycles(maxc) {
    dut->clk_i = 0;
    dut->rst_ni = 0;
    dut->ddr_ready_i = 1;
    dut->s_axil_awvalid = 0;
    dut->s_axil_wvalid = 0;
    dut->s_axil_bready = 1;
    dut->s_axil_arvalid = 0;
    dut->s_axil_rready = 1;
    AxiDrive(AxiS{}, dut.get(), kDw);
    for (int i = 0; i < 4; ++i) { dut->clk_i = i & 1; dut->eval(); }
    dut->rst_ni = 1;
  }
  void Tick() {
    if (++cycle > max_cycles) {
      std::fprintf(stderr, "\nFPGA OCL TB TIMEOUT after %llu cycles\n", (unsigned long long)cycle);
      std::exit(2);
    }
    AxiDrive(axi->Outputs(), dut.get(), kDw);
    dut->clk_i = 0;
    dut->eval();
    const AxiM m = AxiSample(dut.get(), kDw);
    dut->clk_i = 1;
    dut->eval();
    axi->Edge(m);
  }
  // AXI4-Lite master: one transaction, blocking (VALIDs held until READY).
  uint32_t Rd(uint32_t a) {
    dut->s_axil_araddr = a;
    dut->s_axil_arvalid = 1;
    for (;;) {
      dut->clk_i = 0;
      dut->eval();
      const bool fire = dut->s_axil_arready;
      Tick();
      if (fire) break;
    }
    dut->s_axil_arvalid = 0;
    for (;;) {
      dut->clk_i = 0;
      dut->eval();
      if (dut->s_axil_rvalid) {
        const uint32_t d = dut->s_axil_rdata;
        Tick();
        return d;
      }
      Tick();
    }
  }
  void Wr(uint32_t a, uint32_t d) {
    dut->s_axil_awaddr = a;
    dut->s_axil_wdata = d;
    dut->s_axil_awvalid = 1;
    dut->s_axil_wvalid = 1;
    while (dut->s_axil_awvalid || dut->s_axil_wvalid) {
      dut->clk_i = 0;
      dut->eval();
      const bool aw = dut->s_axil_awready, w = dut->s_axil_wready;
      Tick();
      if (aw) dut->s_axil_awvalid = 0;
      if (w) dut->s_axil_wvalid = 0;
    }
    for (;;) {
      dut->clk_i = 0;
      dut->eval();
      const bool b = dut->s_axil_bvalid;
      Tick();
      if (b) return;
    }
  }
  uint64_t Cycles() {
    const uint32_t lo = Rd(R_CYCLE_LO);
    return (uint64_t(Rd(R_CYCLE_HI)) << 32) | lo;
  }
  void Check(const char* what, uint32_t got, uint32_t exp) {
    if (got != exp) {
      std::fprintf(stderr, "FPGA OCL TB FAIL: %s = 0x%08x, expected 0x%08x\n", what, got, exp);
      fails++;
    }
  }
};
}  // namespace

int main(int argc, char** argv) {
  uint64_t max_cycles = 400000000;
  std::vector<std::pair<uint64_t, const char*>> loads;
  const char* uart_in = nullptr;
  std::string exit_string;
  AxiConfig cfg;
  for (int i = 1; i < argc; ++i) {
    const bool more = i + 1 < argc;
    if (const int n = cfg.Parse(argc, argv, i)) {
      i += n - 1;
    } else if (!std::strcmp(argv[i], "--load") && more) {
      char* eq = std::strchr(argv[++i], '=');
      if (!eq) return 2;
      loads.push_back({std::strtoull(argv[i], nullptr, 0), eq + 1});
    } else if (!std::strcmp(argv[i], "--exit-string") && more) {
      exit_string = argv[++i];
    } else if (!std::strcmp(argv[i], "--uart-in") && more) {
      uart_in = argv[++i];
    } else if (argv[i][0] != '+') {
      max_cycles = std::strtoull(argv[i], nullptr, 0);
    }
  }
  if (loads.empty() || exit_string.empty()) {
    std::fprintf(stderr, "usage: %s [max_cycles] --load 0xADDR=FILE --exit-string TEXT\n", argv[0]);
    return 2;
  }
  std::vector<uint8_t> ddr(kRamSize, 0);
  for (auto& [addr, path] : loads) {
    bool ok;
    auto img = ReadFile(path, &ok);
    if (!ok || addr < kRamBase || addr - kRamBase + img.size() > kRamSize) return 2;
    std::memcpy(&ddr[addr - kRamBase], img.data(), img.size());
  }
  std::string rx;
  if (uart_in) {
    bool ok;
    auto d = ReadFile(uart_in, &ok);
    if (!ok) return 2;
    rx.assign(d.begin(), d.end());
  }
  Axi4SlaveModel axi(cfg, kDw, 0, &ddr);
  Harness h(&axi, max_cycles);
  std::fprintf(stderr, "fpga_ocl_tb: 512-bit AXI, %s\n", cfg.Describe().c_str());
  for (int i = 0; i < 8; ++i) h.Tick();

  // Register map after reset.
  h.Check("ID", h.Rd(R_ID), 0x5349474Cu);
  h.Check("VERSION", h.Rd(R_VERSION), 0x00040001u);
  h.Check("CLK_KHZ", h.Rd(R_CLK_KHZ), 62500u);
  h.Check("CTRL", h.Rd(R_CTRL), 0x3u);
  h.Check("STATUS", h.Rd(R_STATUS), 0x41u);  // held, DDR ready
  h.Check("BOOT_PC_LO", h.Rd(R_BOOT_PC_LO), 0x1000u);
  h.Check("BOOT_PC_HI", h.Rd(R_BOOT_PC_HI), 0u);
  h.Check("TX_DATA empty", h.Rd(R_TX_DATA), 0u);
  h.Check("unmapped", h.Rd(0x0F0), 0xBAADDEC0u);
  h.Wr(R_SCRATCH, 0xA5C30F96u);
  h.Check("SCRATCH", h.Rd(R_SCRATCH), 0xA5C30F96u);
  h.Wr(R_BOOT_PC_HI, 0x12345678u);
  h.Check("BOOT_PC_HI rw", h.Rd(R_BOOT_PC_HI), 0x12345678u);
  h.Wr(R_BOOT_PC_HI, 0);
  // Cycle counter: the delta between two snapshots equals the harness
  // cycles between the two CYCLE_LO reads.
  const uint64_t c0 = h.Cycles();
  const uint64_t t0 = h.cycle;
  for (int i = 0; i < 1000; ++i) h.Tick();
  const uint64_t c1 = h.Cycles();
  const uint64_t t1 = h.cycle;
  if (c1 - c0 != t1 - t0) {
    std::fprintf(stderr, "FPGA OCL TB FAIL: cycle counter delta %llu vs %llu harness cycles\n",
                 (unsigned long long)(c1 - c0), (unsigned long long)(t1 - t0));
    h.fails++;
  }

  // Release and run the image, draining TX / feeding RX over OCL.
  h.Wr(R_CTRL, 0x2);
  const uint64_t run_c0 = h.Cycles();
  std::string out;
  size_t rx_i = 0;
  bool pass = false;
  while (!pass) {
    const uint32_t n = h.Rd(R_TX_STATUS) & 0xFFFFu;
    for (uint32_t k = 0; k < n && !pass; ++k) {
      const uint32_t d = h.Rd(R_TX_DATA);
      if (!(d & 0x80000000u)) {
        std::fprintf(stderr, "FPGA OCL TB FAIL: TX_DATA empty with count %u\n", n);
        return 1;
      }
      std::fputc(int(d & 0xFF), stdout);
      if ((d & 0xFF) == '\n') std::fflush(stdout);
      out.push_back(char(d & 0xFF));
      pass = out.size() >= exit_string.size() &&
             out.compare(out.size() - exit_string.size(), exit_string.size(), exit_string) == 0;
    }
    if (rx_i < rx.size() && !(h.Rd(R_RX_STATUS) & 0x80000000u)) {
      h.Wr(R_RX_DATA, uint8_t(rx[rx_i++]));
    }
    const uint32_t st = h.Rd(R_STATUS);
    if (st & 0x6u) {
      std::fprintf(stderr, "FPGA OCL TB FAIL: STATUS 0x%08x (mem_err / tx_overflow)\n", st);
      return 1;
    }
    if (!n) for (int i = 0; i < 64; ++i) h.Tick();
  }
  const uint64_t run_c1 = h.Cycles();
  std::fflush(stdout);
  // Hold again: the SoC must quiesce and report soc_in_reset.
  h.Wr(R_CTRL, 0x3);
  int k = 0;
  while (!(h.Rd(R_STATUS) & 1u)) {
    if (++k > 100000) {
      std::fprintf(stderr, "FPGA OCL TB FAIL: SoC did not re-enter reset\n");
      return 1;
    }
  }
  if (!axi.Idle()) {
    std::fprintf(stderr, "FPGA OCL TB FAIL: AXI traffic in flight while held\n");
    return 1;
  }
  h.Check("TRAP_COUNT cleared while held", h.Rd(R_TRAP_COUNT), 0u);
  std::fprintf(stderr, "\n%s\n", axi.Stats().c_str());
  if (h.fails) {
    std::fprintf(stderr, "FPGA OCL TB FAIL: %d register checks\n", h.fails);
    return 1;
  }
  std::fprintf(stderr, "FPGA OCL TB PASS (\"%s\" after %llu core cycles; %llu harness cycles total)\n",
               exit_string.c_str(), (unsigned long long)(run_c1 - run_c0),
               (unsigned long long)h.cycle);
  h.dut->final();
  return 0;
}
