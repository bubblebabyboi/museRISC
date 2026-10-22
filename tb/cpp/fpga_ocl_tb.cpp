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
// Version 4 registers (issues #62-#67): RAM_SIZE_MB / CAPS / HOST_FLAGS,
// the RTC time base (set, increment, snapshot read), the memory engine
// driven over OCL (pattern write, check, injected mismatch), the bridge
// error capture registers, FIN_STATUS, and the UART drained through
// UART_TX_DATA3 (up to three bytes per read).
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
  R_HOST_FLAGS = 0x038, R_SCRATCH = 0x03C, R_TX_DATA = 0x040, R_TX_STATUS = 0x044,
  R_RX_DATA = 0x048, R_RX_STATUS = 0x04C, R_TX_DATA3 = 0x050,
  R_RAM_SIZE_MB = 0x054, R_CAPS = 0x058, R_ERR_ADDR_LO = 0x060,
  R_ERR_ADDR_HI = 0x064, R_ERR_INFO = 0x068, R_ERR_COUNT = 0x06C,
  R_FIN_STATUS = 0x070, R_FIN_VALUE = 0x074, R_RTC_LO = 0x080, R_RTC_HI = 0x084,
  R_RTC_INC = 0x088, R_MEM_CTRL = 0x0A0, R_MEM_BASE_LO = 0x0A4,
  R_MEM_BASE_HI = 0x0A8, R_MEM_SIZE_LO = 0x0AC, R_MEM_SIZE_HI = 0x0B0,
  R_MEM_SEED_LO = 0x0B4, R_MEM_SEED_HI = 0x0B8, R_MEM_MISM = 0x0BC,
  R_MEM_FADDR_LO = 0x0C0, R_MEM_FADDR_HI = 0x0C4, R_MEM_CYC_LO = 0x0C8,
  R_MEM_RERR = 0x0D0,
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
    dut->hbm_ready_i = 0;
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
  h.Check("RAM_SIZE_MB", h.Rd(R_RAM_SIZE_MB), 128u);
  h.Check("CAPS", h.Rd(R_CAPS), 0u);
  h.Check("HOST_FLAGS reset", h.Rd(R_HOST_FLAGS), 0u);
  h.Wr(R_HOST_FLAGS, 0x3);
  h.Check("HOST_FLAGS rw", h.Rd(R_HOST_FLAGS), 0x3u);
  h.Check("ERR_INFO clear", h.Rd(R_ERR_INFO), 0u);
  h.Check("ERR_COUNT clear", h.Rd(R_ERR_COUNT), 0u);
  h.Check("FIN_STATUS", h.Rd(R_FIN_STATUS), 0u);
  h.Check("TX_DATA3 empty", h.Rd(R_TX_DATA3), 0u);
  h.Check("CTRL tx_drop rw", (h.Wr(R_CTRL, 0x7), h.Rd(R_CTRL)), 0x7u);
  h.Wr(R_CTRL, 0x3);
  // RTC: default increment 16 ns (62.5 MHz, Q8.24), host set, advance.
  h.Check("RTC_INC default", h.Rd(R_RTC_INC), 0x10000000u);
  const uint64_t rtc_set = 1761091200000000000ULL;
  h.Wr(R_RTC_LO, uint32_t(rtc_set));
  h.Wr(R_RTC_HI, uint32_t(rtc_set >> 32));
  {
    const uint64_t t0 = h.cycle;
    const uint32_t lo = h.Rd(R_RTC_LO);
    const uint64_t r = (uint64_t(h.Rd(R_RTC_HI)) << 32) | lo;
    if (r < rtc_set || r > rtc_set + 16 * (h.cycle - t0 + 64)) {
      std::fprintf(stderr, "FPGA OCL TB FAIL: RTC read 0x%llx after set 0x%llx\n",
                   (unsigned long long)r, (unsigned long long)rtc_set);
      h.fails++;
    }
  }
  // Memory engine over OCL (SoC held): address pattern, check, an
  // injected mismatch.
  auto eng = [&](uint32_t mode, uint64_t base, uint64_t size, uint64_t seed) {
    h.Wr(R_MEM_BASE_LO, uint32_t(base));
    h.Wr(R_MEM_BASE_HI, uint32_t(base >> 32));
    h.Wr(R_MEM_SIZE_LO, uint32_t(size));
    h.Wr(R_MEM_SIZE_HI, uint32_t(size >> 32));
    h.Wr(R_MEM_SEED_LO, uint32_t(seed));
    h.Wr(R_MEM_SEED_HI, uint32_t(seed >> 32));
    h.Wr(R_MEM_CTRL, (mode << 4) | 1);
    int k = 0;
    while ((h.Rd(R_MEM_CTRL) & 0x3u) != 0x2u) {
      if (++k > 1000000) {
        std::fprintf(stderr, "FPGA OCL TB FAIL: memory engine stuck\n");
        std::exit(1);
      }
    }
  };
  const uint64_t eb = 0x400000, es = 0x10000, seed = 0xFEEDFACECAFEF00DULL;
  eng(1, eb, es, seed);
  for (uint64_t a = eb; a < eb + es; a += 8) {
    uint64_t v;
    std::memcpy(&v, &ddr[a], 8);
    if (v != (a ^ seed)) {
      std::fprintf(stderr, "FPGA OCL TB FAIL: engine pattern at 0x%llx\n", (unsigned long long)a);
      h.fails++;
      break;
    }
  }
  eng(3, eb, es, seed);
  h.Check("MEM_CTRL after clean check", h.Rd(R_MEM_CTRL), 0x32u);
  h.Check("MEM_MISM clean", h.Rd(R_MEM_MISM), 0u);
  ddr[eb + 0x5018] ^= 0x80;
  eng(3, eb, es, seed);
  h.Check("MEM_CTRL after bad check", h.Rd(R_MEM_CTRL), 0x36u);
  h.Check("MEM_MISM injected", h.Rd(R_MEM_MISM), 1u);
  h.Check("MEM_FADDR_LO", h.Rd(R_MEM_FADDR_LO), uint32_t(eb + 0x5018));
  h.Check("MEM_RERR", h.Rd(R_MEM_RERR), 0u);
  std::fprintf(stderr, "memory engine over OCL: %u core cycles for a 64 KiB check\n",
               h.Rd(R_MEM_CYC_LO));
  eng(0, eb, es, 0);  // back to zeros
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
  uint64_t reads1 = 0, reads3 = 0;
  while (!pass) {
    // Alternate the one-byte and three-byte drain registers.
    const uint32_t n = h.Rd(R_TX_STATUS) & 0xFFFFu;
    uint32_t got = 0;
    while (got < n && !pass) {
      uint8_t b[3];
      uint32_t nb;
      if ((reads1 + reads3) % 4 == 0) {
        const uint32_t d = h.Rd(R_TX_DATA);
        reads1++;
        nb = (d >> 31) & 1;
        b[0] = uint8_t(d);
      } else {
        const uint32_t d = h.Rd(R_TX_DATA3);
        reads3++;
        nb = (d >> 24) & 3;
        if (((d >> 31) & 1) != (nb != 0)) {
          std::fprintf(stderr, "FPGA OCL TB FAIL: TX_DATA3 0x%08x\n", d);
          return 1;
        }
        for (uint32_t i = 0; i < 3; ++i) b[i] = uint8_t(d >> (8 * i));
      }
      if (nb == 0) {
        std::fprintf(stderr, "FPGA OCL TB FAIL: TX empty with count %u\n", n);
        return 1;
      }
      for (uint32_t i = 0; i < nb && !pass; ++i) {
        std::fputc(int(b[i]), stdout);
        if (b[i] == '\n') std::fflush(stdout);
        out.push_back(char(b[i]));
        pass = out.size() >= exit_string.size() &&
               out.compare(out.size() - exit_string.size(), exit_string.size(), exit_string) == 0;
      }
      got += nb;
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
  h.Check("ERR_INFO after the run", h.Rd(R_ERR_INFO), 0u);
  std::fprintf(stderr, "UART drained with %llu TX_DATA and %llu TX_DATA3 reads\n",
               (unsigned long long)reads1, (unsigned long long)reads3);
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
