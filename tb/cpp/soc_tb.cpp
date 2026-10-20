// Platform harness for booting firmware/OS payloads on the
// museRISC CPU (muserisc_cpu: core + L1 I$/D$; issue #21). This
// models a minimal machine behind the CPU's memory-bus master
// port (tb/cpp/mbus_model.h, latency/backpressure options as in
// core_tb). Only DRAM is cacheable (muserisc_cpu default PMA);
// ROM, CLINT, PLIC and UART are reached by uncached single-beat
// accesses, so device side effects happen once per load/store:
//
//   0x0000_1000  boot ROM (boot_stub.S; a0=hartid, a1=DTB)
//   0x0200_0000  CLINT  msip / mtimecmp / mtime (1 tick/cycle)
//   0x0C00_0000  PLIC   32 sources, contexts 0=M 1=S (hart 0)
//   0x1000_0000  16550 UART (byte regs), PLIC source 10
//   0x8000_0000  RAM, 128 MiB flat (fast path for kernel boots)
//
// Typical boot: OpenSBI fw_jump.bin at 0x80000000, payload
// (Linux Image or s_hello) at 0x80200000, DTB at 0x83000000.
//
// Usage: soc_tb [max_cycles] --boot 0xADDR
//          --load 0xADDR=FILE [--load ...]
//          [--uart-log FILE] [--uart-in FILE]
//          [--exit-string TEXT] [--no-cache] [--mem-lat A:B]
//          [--mem-gap N] [--mem-ready PCT] [--mem-seed S]
// Exit status: 0 exit string seen, 2 timeout/usage/load error.
// (--dump shows the bus-side RAM image, which can lag dirty
// D$ lines.)
#include "Vmuserisc_cpu.h"
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
constexpr uint64_t kRomBase = 0x1000ULL, kRomSize = 0x1000ULL;
constexpr uint64_t kClintBase = 0x02000000ULL, kClintSize = 0x10000ULL;
constexpr uint64_t kPlicBase = 0x0C000000ULL, kPlicSize = 0x04000000ULL;
constexpr uint64_t kUartBase = 0x10000000ULL, kUartSize = 0x100ULL;
constexpr uint64_t kRamBase = 0x80000000ULL, kRamSize = 0x8000000ULL;
constexpr int kUartIrq = 10;

bool In(uint64_t a, uint64_t base, uint64_t size) {
  return a >= base && a - base < size;
}

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

struct Platform {
  std::vector<uint8_t> ram = std::vector<uint8_t>(kRamSize, 0);
  std::vector<uint8_t> rom = std::vector<uint8_t>(kRomSize, 0);
  // CLINT
  uint32_t msip = 0;
  uint64_t mtimecmp = 0, mtime = 0;
  // PLIC
  uint32_t prio[32] = {};
  uint32_t enable[2] = {};       // per context, sources 0..31
  uint32_t threshold[2] = {};
  bool in_service = false;        // UART source claimed
  // UART 16550 (byte-wide registers)
  uint8_t ier = 0, lcr = 0, mcr = 0, fcr = 0, scr = 0, dll = 0, dlm = 0;
  bool thre_irq = false;          // THR-empty latch, cleared by IIR read
  std::deque<uint8_t> rx;
  std::string uart_out;           // full captured output (exit match)
  FILE* uart_log = nullptr;

  bool Load(uint64_t addr, const std::vector<uint8_t>& data) {
    if (In(addr, kRamBase, kRamSize) &&
        addr - kRamBase + data.size() <= kRamSize) {
      std::memcpy(&ram[addr - kRamBase], data.data(), data.size());
      return true;
    }
    if (In(addr, kRomBase, kRomSize) &&
        addr - kRomBase + data.size() <= kRomSize) {
      std::memcpy(&rom[addr - kRomBase], data.data(), data.size());
      return true;
    }
    return false;
  }

  uint8_t FetchByte(uint64_t a) const {
    if (In(a, kRamBase, kRamSize)) return ram[a - kRamBase];
    if (In(a, kRomBase, kRomSize)) return rom[a - kRomBase];
    return 0;
  }

  bool UartIrqLevel() const {
    return (!rx.empty() && (ier & 1)) || (thre_irq && (ier & 2));
  }
  bool PlicPending(int src) const {
    return src == kUartIrq && UartIrqLevel() && !in_service;
  }
  // Context external-interrupt-pending: best enabled source
  // beats the threshold.
  bool PlicEip(int ctx) const {
    for (int s = 1; s < 32; ++s) {
      if (PlicPending(s) && (enable[ctx] >> s & 1u) &&
          prio[s] > threshold[ctx]) {
        return true;
      }
    }
    return false;
  }
  uint32_t PlicClaim(int ctx) {
    int best = 0;
    for (int s = 1; s < 32; ++s) {
      // The threshold gates only the EIP notification (spec);
      // priority 0 never interrupts.
      if (PlicPending(s) && (enable[ctx] >> s & 1u) && prio[s] != 0 &&
          (best == 0 || prio[s] > prio[best])) {
        best = s;
      }
    }
    if (best == kUartIrq) in_service = true;
    return uint32_t(best);
  }

  // Side-effect-free byte read, used to compose the aligned
  // 64-bit bus word. Side effects (UART RBR pop / IIR clear,
  // PLIC claim) are applied in Read() for the exact access.
  uint8_t PeekByte(uint64_t a) const {
    if (In(a, kRamBase, kRamSize)) return ram[a - kRamBase];
    if (In(a, kRomBase, kRomSize)) return rom[a - kRomBase];
    if (In(a, kClintBase, kClintSize)) {
      const uint64_t o = a - kClintBase;
      if (o < 4) return uint8_t(msip >> (8 * o));
      if (o >= 0x4000 && o < 0x4008) {
        return uint8_t(mtimecmp >> (8 * (o - 0x4000)));
      }
      if (o >= 0xBFF8 && o < 0xC000) {
        return uint8_t(mtime >> (8 * (o - 0xBFF8)));
      }
      return 0;
    }
    if (In(a, kPlicBase, kPlicSize)) {
      return uint8_t(PeekPlicWord(a & ~3ull) >> (8 * (a & 3)));
    }
    if (In(a, kUartBase, kUartSize)) return PeekUart(a - kUartBase);
    return 0;
  }

  uint32_t PeekPlicWord(uint64_t a) const {
    const uint64_t o = a - kPlicBase;
    if (o < 0x80) return prio[o / 4];
    if (o == 0x1000) {
      uint32_t p = 0;
      for (int s = 1; s < 32; ++s) {
        if (PlicPending(s)) p |= 1u << s;
      }
      return p;
    }
    if (o >= 0x2000 && o < 0x2200) {
      const int ctx = int((o - 0x2000) / 0x80);
      return ((o & 0x7C) == 0 && ctx < 2) ? enable[ctx] : 0;
    }
    if (o >= 0x200000) {
      const int ctx = int((o - 0x200000) / 0x1000);
      if (ctx < 2 && (o & 0xFFC) == 0) return threshold[ctx];
    }
    return 0;
  }

  uint8_t PeekUart(uint64_t o) const {
    const bool dlab = (lcr & 0x80) != 0;
    switch (o & 7) {
      case 0: return dlab ? dll : (rx.empty() ? 0 : rx.front());
      case 1: return dlab ? dlm : ier;
      case 2:  // IIR
        if (!rx.empty() && (ier & 1)) return 0xC4;  // RX available
        if (thre_irq && (ier & 2)) return 0xC2;     // THR empty
        return 0xC1;                                 // no interrupt
      case 3: return lcr;
      case 4: return mcr;
      case 5:  // LSR: THRE | TEMT always, DR when input queued
        return uint8_t(0x60 | (rx.empty() ? 0 : 1));
      case 6: return 0;  // MSR
      default: return scr;
    }
  }

  // Aligned 64-bit bus word with no side effects (cache line
  // refills; only single-beat data reads get Read()).
  uint64_t PeekWord(uint64_t addr) const {
    uint64_t v = 0;
    for (int i = 0; i < 8; ++i) {
      v |= uint64_t(PeekByte((addr & ~7ull) + i)) << (8 * i);
    }
    return v;
  }

  // One load transaction (exact address from the core). Returns
  // the full aligned 64-bit word around the address; applies
  // read side effects for UART RBR/IIR and PLIC claim.
  uint64_t Read(uint64_t addr) {
    uint64_t v = PeekWord(addr);
    if (In(addr, kUartBase, kUartSize)) {
      const uint64_t o = (addr - kUartBase) & 7;
      const bool dlab = (lcr & 0x80) != 0;
      if (o == 0 && !dlab && !rx.empty()) rx.pop_front();
      if (o == 2) thre_irq = false;
    } else if (In(addr, kPlicBase, kPlicSize)) {
      const uint64_t o = addr - kPlicBase;
      if (o >= 0x200004 && (o & 0xFFC) == 4) {
        const int ctx = int((o - 0x200000) / 0x1000);
        if (ctx < 2) {
          const uint32_t claim = PlicClaim(ctx);
          const int sh = int((addr & 7) * 8);
          v = (v & ~(0xFFFFFFFFull << sh)) | (uint64_t(claim) << sh);
        }
      }
    }
    return v;
  }

  // One store transaction: byte lanes of the aligned bus word.
  void Write(uint64_t addr, uint8_t be, uint64_t wdata) {
    // PLIC claim/complete is word-granular; handle it whole.
    if (In(addr, kPlicBase, kPlicSize)) {
      const uint64_t o = addr - kPlicBase;
      if (o >= 0x200004 && (o & 0xFFC) == 4) {
        const uint32_t src =
            uint32_t(wdata >> (8 * (addr & 7))) & 0xFFFFFFFFu;
        const int ctx = int((o - 0x200000) / 0x1000);
        // Ignored for a source not enabled for the context (spec).
        if (src == kUartIrq && ctx < 2 && (enable[ctx] >> src & 1u))
          in_service = false;
        return;
      }
    }
    const uint64_t base = addr & ~7ull;
    for (int i = 0; i < 8; ++i) {
      if (!(be & (1u << i))) continue;
      const uint64_t a = base + i;
      const uint8_t b = uint8_t(wdata >> (8 * i));
      if (In(a, kRamBase, kRamSize)) {
        ram[a - kRamBase] = b;
      } else if (In(a, kClintBase, kClintSize)) {
        const uint64_t o = a - kClintBase;
        auto merge = [](uint64_t* r, int byte, uint8_t v) {
          *r = (*r & ~(0xFFull << (8 * byte))) | (uint64_t(v) << (8 * byte));
        };
        uint64_t tmp;
        if (o < 4) {
          tmp = msip; merge(&tmp, int(o), b); msip = uint32_t(tmp);
        } else if (o >= 0x4000 && o < 0x4008) {
          merge(&mtimecmp, int(o - 0x4000), b);
        } else if (o >= 0xBFF8 && o < 0xC000) {
          merge(&mtime, int(o - 0xBFF8), b);
        }
      } else if (In(a, kPlicBase, kPlicSize)) {
        WritePlicByte(a, b);
      } else if (In(a, kUartBase, kUartSize)) {
        WriteUart(a - kUartBase, b);
      }
      // ROM and unmapped: ignored (no bus-fault pin on the core).
    }
  }

  void WritePlicByte(uint64_t a, uint8_t b) {
    const uint64_t o = a - kPlicBase;
    auto merge = [](uint32_t* r, int byte, uint8_t v) {
      *r = (*r & ~(0xFFu << (8 * byte))) | (uint32_t(v) << (8 * byte));
    };
    // Priorities and thresholds are WARL with 3 implemented bits,
    // as in rtl/soc/muserisc_plic.sv.
    if (o < 0x80) {
      merge(&prio[o / 4], int(o & 3), b);
      prio[o / 4] &= 7u;
    } else if (o >= 0x2000 && o < 0x2200) {
      const int ctx = int((o - 0x2000) / 0x80);
      if (ctx < 2 && (o & 0x7C) == 0) merge(&enable[ctx], int(o & 3), b);
    } else if (o >= 0x200000 && (o & 0xFFC) == 0) {
      const int ctx = int((o - 0x200000) / 0x1000);
      if (ctx < 2) {
        merge(&threshold[ctx], int(o & 3), b);
        threshold[ctx] &= 7u;
      }
    }
  }

  void WriteUart(uint64_t o, uint8_t b) {
    const bool dlab = (lcr & 0x80) != 0;
    switch (o & 7) {
      case 0:
        if (dlab) { dll = b; break; }
        std::fputc(b, stdout);
        std::fflush(stdout);
        if (uart_log) { std::fputc(b, uart_log); std::fflush(uart_log); }
        uart_out.push_back(char(b));
        if (ier & 2) thre_irq = true;  // THR instantly empty again
        break;
      case 1:
        if (dlab) { dlm = b; break; }
        ier = b & 0x0F;
        if (ier & 2) thre_irq = true;  // enabling THRE with THR empty
        break;
      case 2:
        fcr = b;
        if (b & 2) rx.clear();
        break;
      case 3: lcr = b; break;
      case 4: mcr = b; break;
      case 7: scr = b; break;
      default: break;
    }
  }
};
}  // namespace

int main(int argc, char** argv) {
  uint64_t max_cycles = 100000000, boot_pc = kRomBase;
  std::vector<std::pair<uint64_t, const char*>> loads;
  const char* uart_log_path = nullptr;
  const char* uart_in_path = nullptr;
  std::string exit_string;
  bool trace_traps = false;
  std::vector<uint64_t> breakpoints;
  long trace_after_trap = 0;
  uint64_t sample_pc_every = 0, sample_pc_from = 0;
  uint64_t trace_mmio_from = ~0ull;  // --trace-mmio-from CYCLE
  uint64_t cur_cycle = 0;
  std::vector<std::pair<uint64_t, uint64_t>> dumps;
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
    } else if (std::strcmp(argv[i], "--dump") == 0 && need(i)) {
      const char* spec = argv[++i];
      const char* colon = std::strchr(spec, ':');
      dumps.push_back({std::strtoull(spec, nullptr, 0),
                       colon ? std::strtoull(colon + 1, nullptr, 0) : 64});
    } else if (std::strcmp(argv[i], "--trace-mmio-from") == 0 && need(i)) {
      // Log every single-beat (I/O) bus access from this cycle on.
      trace_mmio_from = std::strtoull(argv[++i], nullptr, 0);
    } else if (std::strcmp(argv[i], "--sample-pc") == 0 && need(i)) {
      // FROM:EVERY guest fetch sampler for long-boot diagnosis.
      // EVERY must not be a multiple of the timer-tick period
      // (40,000 cycles for the DT 10 MHz timebase at HZ=250),
      // or every sample lands at the same point of the tick
      // handler; use e.g. 5024721.
      const char* spec = argv[++i];
      const char* colon = std::strchr(spec, ':');
      sample_pc_from = std::strtoull(spec, nullptr, 0);
      sample_pc_every = colon ? std::strtoull(colon + 1, nullptr, 0) : 0;
    } else if (std::strcmp(argv[i], "--trace-after-trap") == 0 && need(i)) {
      trace_after_trap = std::atol(argv[++i]);
    } else if (std::strcmp(argv[i], "--bp") == 0 && need(i)) {
      // One-shot fetch breakpoints: log each listed PC once.
      breakpoints.push_back(std::strtoull(argv[++i], nullptr, 0));
    } else {
      max_cycles = std::strtoull(argv[i], nullptr, 0);
    }
  }
  if (loads.empty()) {
    std::fprintf(stderr, "usage: %s [max_cycles] --load 0xADDR=FILE ...\n",
                 argv[0]);
    return 2;
  }
  Platform plat;
  for (const auto& [addr, path] : loads) {
    bool ok;
    const auto data = ReadFile(path, &ok);
    if (!ok || !plat.Load(addr, data)) {
      std::fprintf(stderr, "cannot load %s at 0x%llx\n", path,
                   static_cast<unsigned long long>(addr));
      return 2;
    }
    std::fprintf(stderr, "loaded %zu bytes at 0x%llx from %s\n",
                 data.size(), static_cast<unsigned long long>(addr), path);
  }
  if (uart_log_path != nullptr) {
    plat.uart_log = std::fopen(uart_log_path, "wb");
  }
  if (uart_in_path != nullptr) {
    bool ok;
    const auto in = ReadFile(uart_in_path, &ok);
    if (!ok) {
      std::fprintf(stderr, "cannot open %s\n", uart_in_path);
      return 2;
    }
    for (uint8_t b : in) plat.rx.push_back(b);
  }

  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_cpu> dut{new Vmuserisc_cpu{&context}};
  // Bus slave: instruction fetches and line refills are
  // side-effect free; single-beat data reads/writes reach the
  // devices exactly once.
  MbusModel bus(
      bus_cfg,
      [&](uint64_t a, uint8_t be, bool inst, bool burst) -> uint64_t {
        if (inst) {
          uint64_t w = 0;
          for (int i = 0; i < 8; ++i) {
            w |= uint64_t(plat.FetchByte((a & ~7ull) + i)) << (8 * i);
          }
          return w;
        }
        if (burst) return plat.PeekWord(a);
        const uint64_t v = plat.Read(a);
        if (cur_cycle >= trace_mmio_from) {
          std::fprintf(stderr, "mmio cy=%llu R a=0x%llx be=%02x v=0x%016llx\n",
                       static_cast<unsigned long long>(cur_cycle),
                       static_cast<unsigned long long>(a), be,
                       static_cast<unsigned long long>(v));
        }
        return v;
      },
      [&](uint64_t a, uint8_t be, uint64_t wdata) {
        if (cur_cycle >= trace_mmio_from && !(a >= kRamBase && a - kRamBase < kRamSize)) {
          std::fprintf(stderr, "mmio cy=%llu W a=0x%llx be=%02x v=0x%016llx\n",
                       static_cast<unsigned long long>(cur_cycle),
                       static_cast<unsigned long long>(a), be,
                       static_cast<unsigned long long>(wdata));
        }
        plat.Write(a, be, wdata);
      });
  dut->clk_i = 0;
  dut->rst_ni = 0;
  dut->boot_pc_i = boot_pc;
  dut->cache_en_i = cache_en ? 1 : 0;
  dut->bus_req_ready_i = 0;
  dut->bus_rsp_valid_i = 0;
  dut->bus_rsp_rdata_i = 0;
  dut->bus_rsp_last_i = 0;
  dut->trap_halt_i = 0;
  dut->irq_m_timer_i = dut->irq_m_soft_i = dut->irq_m_ext_i = 0;
  dut->irq_s_timer_i = dut->irq_s_ext_i = 0;
  for (int i = 0; i < 4; ++i) {
    dut->clk_i = static_cast<uint8_t>(i & 1);
    dut->eval();
  }
  dut->rst_ni = 1;

  size_t exit_match = 0;
  long pc_window = 0;
  for (uint64_t cycle = 0; cycle < max_cycles; ++cycle) {
    cur_cycle = cycle;
    plat.mtime++;
    dut->irq_m_timer_i = plat.mtime >= plat.mtimecmp ? 1 : 0;
    dut->irq_m_soft_i = (plat.msip & 1) ? 1 : 0;
    dut->irq_m_ext_i = plat.PlicEip(0) ? 1 : 0;
    dut->irq_s_ext_i = plat.PlicEip(1) ? 1 : 0;
    if (cycle >= trace_mmio_from) {
      static int last_irq = -1;
      const int now_irq = (dut->irq_m_ext_i << 2) | (dut->irq_s_ext_i << 1) |
                          dut->irq_m_timer_i;
      if (now_irq != last_irq) {
        std::fprintf(stderr, "irq cy=%llu mext=%d sext=%d mtimer=%d uart_lvl=%d in_service=%d ier=%x\n",
                     static_cast<unsigned long long>(cycle), dut->irq_m_ext_i,
                     dut->irq_s_ext_i, dut->irq_m_timer_i,
                     plat.UartIrqLevel() ? 1 : 0, plat.in_service ? 1 : 0,
                     plat.ier);
        last_irq = now_irq;
      }
    }
    // Clock-low phase: bus slave outputs, settle.
    dut->clk_i = 0;
    MbusDrive(&bus, dut.get());
    dut->eval();
    for (size_t b = 0; b < breakpoints.size(); ++b) {
      if (breakpoints[b] != 0 && dut->dbg_fetch_pa_o == breakpoints[b]) {
        std::fprintf(stderr, "bp hit 0x%llx cy=%llu\n",
                     static_cast<unsigned long long>(breakpoints[b]),
                     static_cast<unsigned long long>(cycle));
        breakpoints[b] = 0;
      }
    }
    if (trace_traps && dut->trap_o) {
      std::fprintf(stderr, "trap cy=%llu cause=0x%llx pc=0x%llx\n",
                   static_cast<unsigned long long>(cycle),
                   static_cast<unsigned long long>(dut->trap_cause_o),
                   static_cast<unsigned long long>(dut->trap_pc_o));
      if (trace_after_trap > 0 && pc_window == 0) {
        pc_window = trace_after_trap;
      }
    }
    if (sample_pc_every != 0 && cycle >= sample_pc_from &&
        (cycle % sample_pc_every) == 0) {
      std::fprintf(stderr, "sample cy=%llu fetch_pa=0x%llx bus_addr=0x%llx\n",
                   static_cast<unsigned long long>(cycle),
                   static_cast<unsigned long long>(dut->dbg_fetch_pa_o),
                   static_cast<unsigned long long>(dut->bus_req_addr_o));
    }
    if (pc_window > 0) {
      std::fprintf(stderr, "  fetch cy=%llu pc=0x%llx\n",
                   static_cast<unsigned long long>(cycle),
                   static_cast<unsigned long long>(dut->dbg_fetch_pa_o));
      pc_window--;
    }
    const MbusModel::Req req = MbusSample(dut.get());
    const size_t out_before = plat.uart_out.size();
    dut->clk_i = 1;
    dut->eval();
    bus.Edge(req);
    if (!exit_string.empty() && plat.uart_out.size() > out_before) {
      const size_t from =
          exit_match > 0 ? plat.uart_out.size() - exit_match : 0;
      (void)from;
      if (plat.uart_out.find(exit_string, exit_match) !=
          std::string::npos) {
        std::fprintf(stderr, "\nSOC TB PASS (exit string at %llu cycles)\n",
                     static_cast<unsigned long long>(cycle + 1));
        dut->final();
        return 0;
      }
      // Keep the match window bounded: keep a tail shorter than
      // the needle so a spanning match is still found.
      if (plat.uart_out.size() > (1u << 20)) {
        exit_match = plat.uart_out.size() - exit_string.size();
      }
    }
  }
  for (const auto& [addr, len] : dumps) {
    for (uint64_t a = addr; a < addr + len; a += 8) {
      uint64_t v = 0;
      for (int i = 0; i < 8; ++i) {
        v |= uint64_t(plat.FetchByte(a + i)) << (8 * i);
      }
      std::fprintf(stderr, "DUMP 0x%llx: 0x%016llx\n",
                   static_cast<unsigned long long>(a),
                   static_cast<unsigned long long>(v));
    }
  }
  std::fprintf(stderr, "\nSOC TB TIMEOUT after %llu cycles (fetch pa 0x%llx)\n",
               static_cast<unsigned long long>(max_cycles),
               static_cast<unsigned long long>(dut->dbg_fetch_pa_o));
  dut->final();
  return 2;
}

