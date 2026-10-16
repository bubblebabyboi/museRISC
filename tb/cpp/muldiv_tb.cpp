// Unit test for muserisc_muldiv: RV64M golden model in C++ using
// __int128 arithmetic, formulated directly from the spec rules
// (truncation toward zero, dividend-signed remainder, divide-by-
// zero and signed-overflow results), directed edges plus randoms.
#include "Vmuserisc_muldiv.h"
#include "verilated.h"
#include "verilated_cov.h"
#include "muldiv_golden.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <random>

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_muldiv> dut{new Vmuserisc_muldiv{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;

  auto run_one = [&](int funct3, bool word, uint64_t a, uint64_t b) -> bool {
    // Word-mode funct3 1..3 are unimplemented encodings (no MULHW);
    // the decoder never emits them, so they are not checked.
    if (word && funct3 >= 1 && funct3 <= 3) return true;
    dut->funct3_i = static_cast<uint8_t>(funct3);
    dut->word_op_i = word ? 1 : 0;
    dut->a_i = a;
    dut->b_i = b;
    dut->eval();
    ++checks;
    const uint64_t want = Golden(funct3, word, a, b);
    if (dut->result_o != want) {
      std::printf("FAIL funct3=%d word=%d a=0x%016lx b=0x%016lx got=0x%016lx want=0x%016lx\n",
                  funct3, word ? 1 : 0, static_cast<unsigned long>(a),
                  static_cast<unsigned long>(b),
                  static_cast<unsigned long>(dut->result_o),
                  static_cast<unsigned long>(want));
      return false;
    }
    return true;
  };

  const uint64_t edges[] = {0, 1, 2, 3,
                            static_cast<uint64_t>(-1), static_cast<uint64_t>(-2),
                            0x7fffffffULL, 0x80000000ULL, 0xffffffffULL,
                            0x7fffffffffffffffULL, 0x8000000000000000ULL,
                            0xffffffffffffffffULL, 0x0000000080000000ULL,
                            0xffffffff80000000ULL, 0xdeadbeefcafef00dULL,
                            0x4000000000000000ULL};
  for (int f3 = 0; f3 < 8; ++f3) {
    for (int word = 0; word < 2; ++word) {
      for (uint64_t a : edges) {
        for (uint64_t b : edges) {
          if (!run_one(f3, word != 0, a, b)) return 1;
        }
      }
    }
  }

  std::mt19937_64 rng(0x5eed5eedULL);
  for (int i = 0; i < 200000; ++i) {
    const int f3 = static_cast<int>(rng() % 8);
    const bool word = (rng() & 1u) != 0;
    uint64_t a = rng(), b = rng();
    // Bias toward small divisors so quotient paths vary richly.
    if (i % 3 == 0) b &= 0xff;
    if (!run_one(f3, word, a, b)) return 1;
  }

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("MULDIV TB PASS (%llu checks)\n", static_cast<unsigned long long>(checks));
  return 0;
}
