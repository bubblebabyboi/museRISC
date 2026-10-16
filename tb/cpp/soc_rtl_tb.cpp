// RTL SoC harness (issue #4): unlike soc_tb (C++ platform
// around muserisc_core), this drives muserisc_soc_top --
// core, fabric, boot ROM, CLINT, PLIC, UART and crypto are
// all RTL. The harness only provides external RAM behind
// the SoC's mem_* memory-bus port (128 MiB at 0x8000_0000,
// served by the mbus slave model with optional random
// latency/backpressure, tb/cpp/mbus_model.h), loads binaries
// into it, and captures the UART byte stream
// (uart_tx_valid_o) plus optional RX byte input.
//
// Usage: soc_rtl_tb [max_cycles] --boot 0xADDR
//          --load 0xADDR=FILE [--load ...]
//          [--uart-log FILE] [--uart-in FILE]
//          [--exit-string TEXT] [--trace-traps] [--no-cache]
//          [--mem-lat A:B] [--mem-gap N] [--mem-ready PCT]
//          [--mem-seed S]
// Exit status: 0 exit string seen, 2 timeout/usage error.
// With no --exit-string, success is a trap-free run to
// max_cycles is NOT assumed: timeout (2) is returned.
#include "Vmuserisc_soc_top.h"
#include "verilated.h"
#include "mbus_model.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr uint64_t kRamBase = 0x80000000ULL;
constexpr uint64_t kRamSize = 0x8000000ULL;  // 128 MiB

bool InRam(uint64_t a) { return a >= kRamBase && a - kRamBase < kRamSize; }

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
}  // namespace

int main(int argc, char** argv) {
  uint64_t max_cycles = 100000000, boot_pc = 0x1000;
  std::vector<std::pair<uint64_t, const char*>> loads;
  const char* uart_log_path = nullptr;
  const char* uart_in_path = nullptr;
  std::string exit_string;
  bool trace_traps = false;
  bool cache_en = true;
  MbusConfig bus_cfg;
  for (int i = 1; i < argc; ++i) {
    auto need = [&](int i) { return i + 1 < argc; };
    if (const int n = bus_cfg.Parse(argc, argv, i)) {
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
    } else if (std::strcmp(argv[i], "--uart-log") == 0 && need(i)) {
      uart_log_path = argv[++i];
    } else if (std::strcmp(argv[i], "--uart-in") == 0 && need(i)) {
      uart_in_path = argv[++i];
    } else if (std::strcmp(argv[i], "--exit-string") == 0 && need(i)) {
      exit_string = argv[++i];
    } else if (std::strcmp(argv[i], "--trace-traps") == 0) {
      trace_traps = true;
    } else {
      max_cycles = std::strtoull(argv[i], nullptr, 0);
    }
  }
  if (loads.empty()) {
    std::fprintf(stderr, "usage: %s [max_cycles] --load 0xADDR=FILE ...\n",
                 argv[0]);
    return 2;
  }
  std::vector<uint8_t> ram(kRamSize, 0);
  for (const auto& [addr, path] : loads) {
    bool ok;
    const auto data = ReadFile(path, &ok);
    if (!ok || !InRam(addr) || addr - kRamBase + data.size() > kRamSize) {
      std::fprintf(stderr, "cannot load %s at 0x%llx\n", path,
                   static_cast<unsigned long long>(addr));
      return 2;
    }
    std::memcpy(&ram[addr - kRamBase], data.data(), data.size());
    std::fprintf(stderr, "loaded %zu bytes at 0x%llx from %s\n",
                 data.size(), static_cast<unsigned long long>(addr), path);
  }
  FILE* uart_log = uart_log_path ? std::fopen(uart_log_path, "wb") : nullptr;
  std::deque<uint8_t> rxq;
  if (uart_in_path != nullptr) {
    bool ok;
    const auto in = ReadFile(uart_in_path, &ok);
    if (!ok) {
      std::fprintf(stderr, "cannot open %s\n", uart_in_path);
      return 2;
    }
    for (uint8_t b : in) rxq.push_back(b);
  }
  auto fetch64 = [&](uint64_t a) -> uint64_t {
    uint64_t v = 0;
    for (int i = 0; i < 8; ++i) {
      const uint64_t b = (a & ~7ull) + i;
      if (InRam(b)) v |= uint64_t(ram[b - kRamBase]) << (8 * i);
    }
    return v;
  };
  // External RAM behind the SoC's memory bus (RAM has no read
  // side effects, so every read is the same).
  MbusModel bus(
      bus_cfg,
      [&](uint64_t a, uint8_t, bool, bool) { return fetch64(a); },
      [&](uint64_t a, uint8_t be, uint64_t wdata) {
        const uint64_t base = a & ~7ull;
        for (int i = 0; i < 8; ++i) {
          if ((be & (1u << i)) && InRam(base + i)) {
            ram[base + i - kRamBase] = uint8_t(wdata >> (8 * i));
          }
        }
      });

  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_soc_top> dut{
      new Vmuserisc_soc_top{&context}};
  dut->clk_i = 0;
  dut->rst_ni = 0;
  dut->boot_pc_i = boot_pc;
  dut->cache_en_i = cache_en ? 1 : 0;
  dut->mem_req_ready_i = 0;
  dut->mem_rsp_valid_i = 0;
  dut->mem_rsp_rdata_i = 0;
  dut->mem_rsp_last_i = 0;
  dut->uart_rx_i = 1;
  dut->uart_rx_data_i = 0;
  dut->uart_rx_valid_i = 0;
  dut->ext_irq_i = 0;
  for (int i = 0; i < 4; ++i) {
    dut->clk_i = static_cast<uint8_t>(i & 1);
    dut->eval();
  }
  dut->rst_ni = 1;

  std::string uart_out;
  uint64_t rx_pace = 0;
  for (uint64_t cycle = 0; cycle < max_cycles; ++cycle) {
    // Push at most one RX byte every 8 cycles via the
    // parallel byte port (serial RX is exercised by the
    // UART unit behaviour, not this platform harness).
    dut->uart_rx_valid_i = 0;
    if (!rxq.empty() && rx_pace == 0) {
      dut->uart_rx_data_i = rxq.front();
      rxq.pop_front();
      dut->uart_rx_valid_i = 1;
      rx_pace = 8;
    }
    if (rx_pace > 0) rx_pace--;
    dut->clk_i = 0;
    // External RAM bus slave outputs for this cycle, settle.
    {
      const auto d = bus.Outputs();
      dut->mem_req_ready_i = d.req_ready;
      dut->mem_rsp_valid_i = d.rsp_valid;
      dut->mem_rsp_rdata_i = d.rsp_rdata;
      dut->mem_rsp_last_i = d.rsp_last;
    }
    dut->eval();
    if (trace_traps && dut->trap_o) {
      std::fprintf(stderr, "trap cy=%llu cause=0x%llx pc=0x%llx\n",
                   static_cast<unsigned long long>(cycle),
                   static_cast<unsigned long long>(dut->trap_cause_o),
                   static_cast<unsigned long long>(dut->trap_pc_o));
    }
    MbusModel::Req req{};
    req.valid = dut->mem_req_valid_o;
    req.fire = req.valid && dut->mem_req_ready_i;
    req.addr = dut->mem_req_addr_o;
    req.write = dut->mem_req_write_o;
    req.len = dut->mem_req_len_o;
    req.wdata = dut->mem_req_wdata_o;
    req.be = dut->mem_req_be_o;
    req.last = dut->mem_req_last_o;
    req.inst = dut->mem_req_inst_o;
    const bool tx_valid = dut->uart_tx_valid_o != 0;
    const uint8_t tx_byte = dut->uart_tx_data_o;
    dut->clk_i = 1;
    dut->eval();
    bus.Edge(req);
    if (tx_valid) {
      std::fputc(tx_byte, stdout);
      std::fflush(stdout);
      if (uart_log) {
        std::fputc(tx_byte, uart_log);
        std::fflush(uart_log);
      }
      uart_out.push_back(char(tx_byte));
      if (!exit_string.empty() &&
          uart_out.find(exit_string) != std::string::npos) {
        std::fprintf(stderr, "\nSOC RTL TB PASS (exit string at %llu cycles)\n",
                     static_cast<unsigned long long>(cycle + 1));
        dut->final();
        return 0;
      }
      if (uart_out.size() > (1u << 20)) {
        uart_out.erase(0, uart_out.size() - 1024);
      }
    }
  }
  std::fprintf(stderr, "\nSOC RTL TB TIMEOUT after %llu cycles\n",
               static_cast<unsigned long long>(max_cycles));
  dut->final();
  return 2;
}
