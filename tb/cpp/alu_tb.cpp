// Unit test for sigil_alu: directed edge cases plus randomized
// comparison against an independent C++ golden model written from
// the RV64I spec rules (W variants compute at 32-bit width and
// sign-extend the result). Exits 0 on pass, 1 on first mismatch.
#include "Vsigil_alu.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <random>

namespace {
// Must match alu_op_e declaration order in sigil_pkg.sv. If the
// order ever diverges these tests fail loudly (directed cases
// cover every operation), and the end-to-end asm tests catch it too.
enum AluOp { ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, COPY_B, N_OPS };

uint64_t Golden(int op, bool word, uint64_t a, uint64_t b) {
  if (word) {
    const uint32_t a32 = static_cast<uint32_t>(a);
    const uint32_t b32 = static_cast<uint32_t>(b);
    const unsigned sh = b32 & 31u;
    uint32_t r = 0;
    switch (op) {
      case ADD: r = a32 + b32; break;
      case SUB: r = a32 - b32; break;
      case SLL: r = a32 << sh; break;
      case SLT: r = (static_cast<int32_t>(a32) < static_cast<int32_t>(b32)) ? 1u : 0u; break;
      case SLTU: r = (a32 < b32) ? 1u : 0u; break;
      case XOR: r = a32 ^ b32; break;
      case SRL: r = a32 >> sh; break;
      case SRA: r = static_cast<uint32_t>(static_cast<int32_t>(a32) >> sh); break;
      case OR: r = a32 | b32; break;
      case AND: r = a32 & b32; break;
      case COPY_B: r = b32; break;
      default: r = 0; break;
    }
    return static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(r)));
  }
  const unsigned sh = b & 63u;
  switch (op) {
    case ADD: return a + b;
    case SUB: return a - b;
    case SLL: return a << sh;
    case SLT: return (static_cast<int64_t>(a) < static_cast<int64_t>(b)) ? 1u : 0u;
    case SLTU: return (a < b) ? 1u : 0u;
    case XOR: return a ^ b;
    case SRL: return a >> sh;
    case SRA: return static_cast<uint64_t>(static_cast<int64_t>(a) >> sh);
    case OR: return a | b;
    case AND: return a & b;
    case COPY_B: return b;
    default: return 0;
  }
}
}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vsigil_alu> dut{new Vsigil_alu{&context}};

  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;
  auto run_one = [&](int op, bool word, uint64_t a, uint64_t b) -> bool {
    dut->op_i = static_cast<uint8_t>(op);
    dut->word_op_i = word ? 1 : 0;
    dut->a_i = a;
    dut->b_i = b;
    dut->eval();
    ++checks;
    const uint64_t want = Golden(op, word, a, b);
    if (dut->result_o != want) {
      std::printf("FAIL op=%d word=%d a=0x%016lx b=0x%016lx got=0x%016lx want=0x%016lx\n",
                  op, word ? 1 : 0, static_cast<unsigned long>(a),
                  static_cast<unsigned long>(b),
                  static_cast<unsigned long>(dut->result_o),
                  static_cast<unsigned long>(want));
      return false;
    }
    return true;
  };

  // Directed edges: zeros, ones, sign boundaries, shift extremes,
  // and words whose 32-bit sign differs from the 64-bit sign.
  const uint64_t edges[] = {0, 1, 2, 31, 32, 63, 64,
                            0x7fffffffULL, 0x80000000ULL, 0xffffffffULL,
                            0x7fffffffffffffffULL, 0x8000000000000000ULL,
                            0xffffffffffffffffULL, 0x0000000080000000ULL,
                            0xffffffff00000000ULL, 0xdeadbeefcafef00dULL};
  for (int op = 0; op < N_OPS; ++op) {
    for (int word = 0; word < 2; ++word) {
      for (uint64_t a : edges) {
        for (uint64_t b : edges) {
          if (!run_one(op, word != 0, a, b)) return 1;
        }
      }
    }
  }

  // Undefined op encodings must produce zero (decoder never emits
  // them, but the ALU spec is total).
  for (int op = N_OPS; op < 16; ++op) {
    for (int word = 0; word < 2; ++word) {
      if (!run_one(op, word != 0, 0xdeadbeefcafef00dULL, 0x123456789abcdef0ULL)) {
        return 1;
      }
    }
  }

  std::mt19937_64 rng(0x5eed5eedULL);
  for (int i = 0; i < 200000; ++i) {
    const int op = static_cast<int>(rng() % N_OPS);
    const bool word = (rng() & 1u) != 0;
    if (!run_one(op, word, rng(), rng())) return 1;
  }

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("ALU TB PASS (%llu checks)\n", static_cast<unsigned long long>(checks));
  return 0;
}
