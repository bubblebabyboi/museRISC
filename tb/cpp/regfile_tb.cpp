// Unit test for sigil_regfile: every register written and read
// back on both ports, x0 hardwired, and synchronous-write semantics
// (a read in the write cycle returns the old value; the core has no
// same-cycle bypass in stage 1 by construction).
#include "Vsigil_regfile.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <random>

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vsigil_regfile> dut{new Vsigil_regfile{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;
  uint64_t model[32] = {0};

  auto tick = [&]() {
    dut->clk_i = 0; dut->eval();
    dut->clk_i = 1; dut->eval();
    dut->clk_i = 0; dut->eval();
  };
  auto write = [&](int reg, uint64_t value) {
    dut->we_i = 1;
    dut->waddr_i = static_cast<uint8_t>(reg);
    dut->wdata_i = value;
    tick();
    dut->we_i = 0;
    if (reg != 0) model[reg] = value;
  };
  auto check = [&](int reg) -> bool {
    dut->raddr_a_i = static_cast<uint8_t>(reg);
    dut->raddr_b_i = static_cast<uint8_t>(reg);
    dut->eval();
    ++checks;
    const uint64_t want = (reg == 0) ? 0 : model[reg];
    if (dut->rdata_a_o != want || dut->rdata_b_o != want) {
      std::printf("FAIL x%d got a=0x%016lx b=0x%016lx want=0x%016lx\n", reg,
                  static_cast<unsigned long>(dut->rdata_a_o),
                  static_cast<unsigned long>(dut->rdata_b_o),
                  static_cast<unsigned long>(want));
      return false;
    }
    return true;
  };

  std::mt19937_64 rng(0x5eed5eedULL);
  const uint64_t patterns[] = {0, ~0ull, 0xaaaaaaaaaaaaaaaaULL,
                               0x5555555555555555ULL, 0x8000000000000000ULL, 1};
  for (uint64_t p : patterns) {
    for (int r = 0; r < 32; ++r) write(r, p);
    for (int r = 0; r < 32; ++r) if (!check(r)) return 1;
  }
  for (int i = 0; i < 2000; ++i) {
    const int r = static_cast<int>(rng() % 32);
    write(r, rng());
    if (!check(r)) return 1;
    if (!check(static_cast<int>(rng() % 32))) return 1;
  }

  // Same-cycle read-during-write returns the old value.
  write(7, 0x1111111111111111ULL);
  dut->we_i = 1;
  dut->waddr_i = 7;
  dut->wdata_i = 0x2222222222222222ULL;
  dut->raddr_a_i = 7;
  dut->clk_i = 0;
  dut->eval();
  ++checks;
  if (dut->rdata_a_o != 0x1111111111111111ULL) {
    std::printf("FAIL read-during-write returned new value\n");
    return 1;
  }
  dut->clk_i = 1; dut->eval();
  dut->we_i = 0;
  model[7] = 0x2222222222222222ULL;
  if (!check(7)) return 1;

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("REGFILE TB PASS (%llu checks)\n", static_cast<unsigned long long>(checks));
  return 0;
}
