// Core-level harness for the museRISC CPU (muserisc_cpu: core +
// L1 I$/D$) over a paged memory behind the mbus slave model
// (tb/cpp/mbus_model.h) with configurable, seeded random
// latency and backpressure. Two program modes:
//
// - flat binary (directed tests): loaded at PA 0, boot PC 0, a
//   store to EXIT_ADDR ends the test (0 = pass, nonzero =
//   failing test number); --expect-trap freezes at the first trap.
// - ELF64 (riscv-tests, ACT): PT_LOAD segments are placed
//   at their physical addresses, boot PC = entry point, and the
//   run ends on the HTIF convention: a write to `tohost` of 1 =
//   pass, (n << 1) | 1 = failing subtest n.
//
// Stores are observed at the core's data port (dbg_st_*), so
// test exit and HTIF work even though tohost is cacheable and a
// write-back D$ may never send the store to the bus. The same
// observations maintain an architectural shadow memory used by
// the signature/range dumps.
//
// Cacheability in this harness (sim/Makefile -G overrides):
// [0, 0x1000_0000) and [0x8000_0000, 0x1_0000_0000) cacheable,
// so EXIT_ADDR (0x1000_0000) is uncached I/O.
//
// Usage: core_tb <program.bin|elf> [max_cycles] [--expect-trap CAUSE]
//          [--irq-timer-after N] [--no-cache] [--mem-lat A:B]
//          [--mem-gap N] [--mem-ready PCT] [--mem-seed S] [--trace]
// Exit status: 0 pass, 1 test failure, 2 timeout, 3 unexpected trap.
#include "Vmuserisc_cpu.h"
#include "verilated.h"
#include "verilated_cov.h"
#include "mbus_model.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <unordered_map>
#include <vector>

namespace {
constexpr uint64_t kExitAddr = 0x10000000ULL;
constexpr uint64_t kDevBase = 0x20000000ULL;  // side-effect test device


struct PagedMem {
  std::unordered_map<uint64_t, std::array<uint8_t, 4096>> pages;
  uint8_t Rb(uint64_t a) const {
    const auto it = pages.find(a >> 12);
    return it == pages.end() ? 0 : it->second[a & 0xFFF];
  }
  void Wb(uint64_t a, uint8_t v) { pages[a >> 12][a & 0xFFF] = v; }
  uint64_t R64(uint64_t a) const {
    uint64_t v = 0;
    for (int i = 7; i >= 0; --i) v = (v << 8) | Rb(a + uint64_t(i));
    return v;
  }
};

uint16_t Rd16(const std::vector<uint8_t>& f, size_t o) {
  return uint16_t(f[o]) | (uint16_t(f[o + 1]) << 8);
}
uint32_t Rd32(const std::vector<uint8_t>& f, size_t o) {
  return Rd16(f, o) | (uint32_t(Rd16(f, o + 2)) << 16);
}
uint64_t Rd64f(const std::vector<uint8_t>& f, size_t o) {
  return Rd32(f, o) | (uint64_t(Rd32(f, o + 4)) << 32);
}
bool IsElf(const std::vector<uint8_t>& f) {
  return f.size() > 64 && f[0] == 0x7f && f[1] == 'E' && f[2] == 'L' &&
         f[3] == 'F' && f[4] == 2 && f[5] == 1;  // ELF64 little-endian
}

// Loads PT_LOAD segments; returns entry PC and the `tohost`
// address (0 if the symbol is absent).
bool LoadElf(const std::vector<uint8_t>& f, PagedMem* mem, uint64_t* entry,
             uint64_t* tohost, uint64_t* sig_begin, uint64_t* sig_end) {
  *entry = Rd64f(f, 24);
  *tohost = 0;
  *sig_begin = *sig_end = 0;
  const uint64_t phoff = Rd64f(f, 32);
  const int phnum = Rd16(f, 56);
  const size_t phsize = Rd16(f, 54);
  for (int i = 0; i < phnum; ++i) {
    const size_t p = phoff + size_t(i) * phsize;
    if (Rd32(f, p) != 1) continue;  // PT_LOAD
    const uint64_t off = Rd64f(f, p + 8), va = Rd64f(f, p + 16);
    const uint64_t filesz = Rd64f(f, p + 32);
    for (uint64_t j = 0; j < filesz; ++j) mem->Wb(va + j, f[off + j]);
  }
  const uint64_t shoff = Rd64f(f, 40);
  const int shnum = Rd16(f, 60);
  const size_t shsize = Rd16(f, 58);
  for (int i = 0; i < shnum; ++i) {
    const size_t s = shoff + size_t(i) * shsize;
    if (Rd32(f, s + 4) != 2) continue;  // SHT_SYMTAB
    const uint64_t soff = Rd64f(f, s + 24), ssize = Rd64f(f, s + 32);
    const size_t str = shoff + size_t(Rd32(f, s + 40)) * shsize;
    const uint64_t stroff = Rd64f(f, str + 24);
    const uint64_t entsize = Rd64f(f, s + 56);
    for (uint64_t o = soff; o + entsize <= soff + ssize; o += entsize) {
      const char* name =
          reinterpret_cast<const char*>(f.data() + stroff + Rd32(f, o));
      if (std::strcmp(name, "tohost") == 0) *tohost = Rd64f(f, o + 8);
      if (std::strcmp(name, "begin_signature") == 0) {
        *sig_begin = Rd64f(f, o + 8);
      }
      if (std::strcmp(name, "end_signature") == 0) {
        *sig_end = Rd64f(f, o + 8);
      }
    }
  }
  return *tohost != 0;
}
}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <program.bin> [max_cycles] [--expect-trap CAUSE]\n", argv[0]);
    return 2;
  }
  const char* prog_path = argv[1];
  uint64_t max_cycles = 1000000;
  long expect_trap = -1;
  long irq_timer_after = -1;
  bool trace = std::getenv("CORE_TB_TRACE") != nullptr;
  bool cache_en = true;
  MbusConfig bus_cfg;
  for (int i = 2; i < argc; ++i) {
    if (const int n = bus_cfg.Parse(argc, argv, i)) {
      i += n - 1;
    } else if (std::strcmp(argv[i], "--expect-trap") == 0 && i + 1 < argc) {
      expect_trap = std::atol(argv[++i]);
    } else if (std::strcmp(argv[i], "--irq-timer-after") == 0 && i + 1 < argc) {
      irq_timer_after = std::atol(argv[++i]);
    } else if (std::strcmp(argv[i], "--trace") == 0) {
      trace = true;
    } else if (std::strcmp(argv[i], "--no-cache") == 0) {
      cache_en = false;
    } else {
      max_cycles = std::strtoull(argv[i], nullptr, 0);
    }
  }

  std::vector<uint8_t> prog;
  FILE* f = std::fopen(prog_path, "rb");
  if (f == nullptr) {
    std::fprintf(stderr, "cannot open %s\n", prog_path);
    return 2;
  }
  uint8_t buf[65536];
  size_t nread = 0;
  while ((nread = std::fread(buf, 1, sizeof(buf), f)) > 0) {
    prog.insert(prog.end(), buf, buf + nread);
  }
  std::fclose(f);
  if (prog.empty()) {
    std::fprintf(stderr, "empty program %s\n", prog_path);
    return 2;
  }
  // mem: what the bus sees. arch: initial image + every store
  // the core issued (architectural view for HTIF and dumps).
  PagedMem mem;
  uint64_t boot_pc = 0, tohost_addr = 0, sig_begin = 0, sig_end = 0;
  const bool elf_mode = IsElf(prog);
  if (elf_mode) {
    if (!LoadElf(prog, &mem, &boot_pc, &tohost_addr, &sig_begin, &sig_end)) {
      std::fprintf(stderr, "ELF %s has no tohost symbol\n", prog_path);
      return 2;
    }
  } else {
    for (size_t i = 0; i < prog.size(); ++i) mem.Wb(i, prog[i]);
  }
  PagedMem arch = mem;

  // Side-effect test device at kDevBase (uncached I/O in this
  // harness's map), used by mmio_bypass_directed.S:
  //   +0x00 R  read counter: returns the number of data reads of
  //            this register seen so far (post-increment)
  //   +0x08 R  number of write beats seen at +0x10
  //   +0x10 W  write counter
  // Any burst or instruction fetch into the device window is a
  // harness error (it must never be cached).
  uint64_t dev_reads = 0, dev_writes = 0;
  bool dev_bad = false;
  auto in_dev = [](uint64_t a) { return a >= kDevBase && a < kDevBase + 0x100; };
  MbusModel bus(
      bus_cfg,
      [&](uint64_t a, uint8_t, bool inst, bool burst) -> uint64_t {
        if (in_dev(a)) {
          if (inst || burst) {
            dev_bad = true;
            return 0;
          }
          if ((a & ~7ull) == kDevBase) return dev_reads++;
          if ((a & ~7ull) == kDevBase + 8) return dev_writes;
          return 0;
        }
        return mem.R64(a & ~7ull);
      },
      [&](uint64_t a, uint8_t be, uint64_t wdata) {
        if (in_dev(a)) {
          if ((a & ~7ull) == kDevBase + 0x10) dev_writes++;
          return;
        }
        const uint64_t base = a & ~7ull;
        for (int i = 0; i < 8; ++i) {
          if ((be & (1u << i)) != 0) {
            mem.Wb(base + uint64_t(i), static_cast<uint8_t>(wdata >> (8 * i)));
          }
        }
      });

  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_cpu> dut{new Vmuserisc_cpu{&context}};
  const char* cov_path = std::getenv("COV_FILE");

  auto finish = [&](int rc) {
    if (dev_bad) {
      std::printf("CORE TB FAIL %s: burst or fetch into the I/O test device\n",
                  prog_path);
      rc = 1;
    }
    // Debug aid for ACT triage: dump the signature area so it
    // can be diffed against the Sail-generated .sig file.
    if (std::getenv("CORE_TB_SIGDUMP") != nullptr && sig_end > sig_begin) {
      for (uint64_t a = sig_begin; a < sig_end; a += 8) {
        std::printf("SIG %016llx\n",
                    static_cast<unsigned long long>(arch.R64(a)));
      }
    }
    // ... or an arbitrary range: CORE_TB_DUMP=0xADDR:0xLEN
    if (const char* dump = std::getenv("CORE_TB_DUMP")) {
      char* sep = nullptr;
      const uint64_t base = std::strtoull(dump, &sep, 0);
      const uint64_t len = (sep && *sep == ':')
                               ? std::strtoull(sep + 1, nullptr, 0) : 0;
      for (uint64_t a = base; a < base + len; a += 8) {
        std::printf("SIG %016llx\n",
                    static_cast<unsigned long long>(arch.R64(a)));
      }
    }
    dut->final();
    if (cov_path != nullptr) context.coveragep()->write(cov_path);
    return rc;
  };

  dut->clk_i = 0;
  dut->rst_ni = 0;
  dut->boot_pc_i = boot_pc;
  dut->cache_en_i = cache_en ? 1 : 0;
  dut->bus_req_ready_i = 0;
  dut->bus_rsp_valid_i = 0;
  dut->bus_rsp_rdata_i = 0;
  dut->bus_rsp_last_i = 0;
  // Legacy --expect-trap runs freeze at the first trap; normal
  // runs let the core take traps to its handlers.
  dut->trap_halt_i = (expect_trap >= 0) ? 1 : 0;
  dut->irq_m_timer_i = 0;
  dut->irq_m_soft_i = 0;
  dut->irq_m_ext_i = 0;
  dut->irq_s_timer_i = 0;
  dut->irq_s_ext_i = 0;
  bool irq_active = false;
  // Pulse every IRQ pin once while still in reset (mie = 0, so no
  // trap can be taken) so the level inputs exercised only by the
  // unit testbench still toggle through the core pins.
  dut->irq_m_soft_i = 1;
  dut->irq_m_ext_i = 1;
  dut->irq_s_timer_i = 1;
  dut->irq_s_ext_i = 1;
  for (int i = 0; i < 4; ++i) {
    dut->clk_i = static_cast<uint8_t>(i & 1);
    dut->eval();
  }
  dut->irq_m_soft_i = 0;
  dut->irq_m_ext_i = 0;
  dut->irq_s_timer_i = 0;
  dut->irq_s_ext_i = 0;
  dut->eval();
  dut->rst_ni = 1;

  for (uint64_t cycle = 0; cycle < max_cycles; ++cycle) {
    if (irq_timer_after >= 0 &&
        cycle >= static_cast<uint64_t>(irq_timer_after) && !irq_active) {
      dut->irq_m_timer_i = 1;
      irq_active = true;
    }
    // Level interrupt: clear once it is taken. Only an interrupt
    // trap (mcause bit 63) counts: a synchronous exception taken
    // while the IRQ is pending must leave the line raised
    // (irq_exc_race_directed).
    if (irq_active && dut->trap_o && (dut->trap_cause_o >> 63) != 0) {
      dut->irq_m_timer_i = 0;
      irq_active = false;
      irq_timer_after = -1;
    }
    // Clock-low phase: drive the bus slave outputs, settle.
    dut->clk_i = 0;
    MbusDrive(&bus, dut.get());
    dut->eval();
    if (trace) {
      std::printf("cy %4llu fetch_pa 0x%lx bus %d%d a 0x%lx w%d len %u be 0x%02x | rsp %d 0x%016lx | st %d 0x%lx\n",
                  static_cast<unsigned long long>(cycle),
                  static_cast<unsigned long>(dut->dbg_fetch_pa_o),
                  dut->bus_req_valid_o, dut->bus_req_ready_i,
                  static_cast<unsigned long>(dut->bus_req_addr_o),
                  dut->bus_req_write_o, dut->bus_req_len_o, dut->bus_req_be_o,
                  dut->bus_rsp_valid_i,
                  static_cast<unsigned long>(dut->bus_rsp_rdata_i),
                  dut->dbg_st_valid_o,
                  static_cast<unsigned long>(dut->dbg_st_addr_o));
    }

    if (dut->trap_o && expect_trap >= 0) {
      const uint64_t cause = dut->trap_cause_o;
      if (cause == static_cast<uint64_t>(expect_trap)) {
        std::printf("CORE TB PASS %s (expected trap cause %llu at pc 0x%lx, %llu cycles)\n",
                    prog_path, static_cast<unsigned long long>(cause),
                    static_cast<unsigned long>(dut->trap_pc_o),
                    static_cast<unsigned long long>(cycle));
        return finish(0);
      }
      std::printf("CORE TB TRAP %s cause=%llu pc=0x%lx cycle=%llu\n", prog_path,
                  static_cast<unsigned long long>(cause),
                  static_cast<unsigned long>(dut->trap_pc_o),
                  static_cast<unsigned long long>(cycle));
      return finish(3);
    }

    // Sample this cycle's handshakes, then the rising edge.
    const MbusModel::Req req = MbusSample(dut.get());
    const bool st = dut->dbg_st_valid_o;
    const uint64_t daddr = dut->dbg_st_addr_o;
    const uint8_t be = dut->dbg_st_be_o;
    const uint64_t wdata = dut->dbg_st_wdata_o;
    dut->clk_i = 1;
    dut->eval();
    bus.Edge(req);
    if (st) {
      if (!elf_mode && daddr == kExitAddr) {
        const long code = static_cast<long>(wdata & 0xffffffffULL);
        if (code == 0) {
          std::printf("CORE TB PASS %s (%llu cycles)\n", prog_path,
                      static_cast<unsigned long long>(cycle + 1));
          return finish(0);
        }
        std::printf("CORE TB FAIL %s test %ld (%llu cycles)\n", prog_path, code,
                    static_cast<unsigned long long>(cycle + 1));
        return finish(1);
      }
      const uint64_t base = daddr & ~7ull;
      for (int i = 0; i < 8; ++i) {
        if ((be & (1u << i)) != 0) {
          arch.Wb(base + uint64_t(i), static_cast<uint8_t>(wdata >> (8 * i)));
        }
      }
      if (elf_mode && (base >> 12) == (tohost_addr >> 12)) {
        const uint64_t th = arch.R64(tohost_addr);
        if (th != 0) {
          if (th == 1) {
            std::printf("CORE TB PASS %s (htif, %llu cycles)\n", prog_path,
                        static_cast<unsigned long long>(cycle + 1));
            return finish(0);
          }
          std::printf("CORE TB FAIL %s test %llu (htif, %llu cycles)\n",
                      prog_path, static_cast<unsigned long long>(th >> 1),
                      static_cast<unsigned long long>(cycle + 1));
          return finish(1);
        }
      }
    }
  }
  std::printf("CORE TB TIMEOUT %s after %llu cycles (fetch pa 0x%lx; bus %s)\n",
              prog_path, static_cast<unsigned long long>(max_cycles),
              static_cast<unsigned long>(dut->dbg_fetch_pa_o),
              bus_cfg.Describe().c_str());
  return finish(2);
}
