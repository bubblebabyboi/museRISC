// SHA-512 block KATs (issue #19): FIPS 180-4 "abc" and empty-message
// padded blocks, migrated from tb/tb_sha512.v. Exits 0 on pass and 1
// on the first mismatch or timeout.
#include "Vsha512_block.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

namespace {

using Block = std::array<uint64_t, 16>;
using Digest = std::array<uint64_t, 8>;

int HexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

template <size_t Words>
bool ParseHex(const char* hex, std::array<uint64_t, Words>* out) {
  const size_t digits = Words * 16;
  if (std::strlen(hex) != digits) return false;
  out->fill(0);
  for (size_t pos = 0; pos < digits; ++pos) {
    const int v = HexValue(hex[digits - 1 - pos]);
    if (v < 0) return false;
    (*out)[pos / 16] |= static_cast<uint64_t>(v) << (4 * (pos % 16));
  }
  return true;
}

template <size_t Words>
std::string ToHex(const std::array<uint64_t, Words>& value) {
  static constexpr char kDigits[] = "0123456789abcdef";
  std::string out;
  out.reserve(Words * 16);
  for (size_t pos = Words * 16; pos > 0; --pos) {
    const size_t nibble = pos - 1;
    out.push_back(kDigits[(value[nibble / 16] >> (4 * (nibble % 16))) & 0xf]);
  }
  return out;
}

template <typename Port, size_t Words>
void PutWide(Port& port, const std::array<uint64_t, Words>& value) {
  for (size_t i = 0; i < Words * 2; ++i) {
    port[i] = static_cast<uint32_t>(value[i / 2] >> (32 * (i % 2)));
  }
}

template <typename Port, size_t Words>
std::array<uint64_t, Words> FetchWide(const Port& port) {
  std::array<uint64_t, Words> value{};
  for (size_t i = 0; i < Words * 2; ++i) {
    value[i / 2] |= static_cast<uint64_t>(static_cast<uint32_t>(port[i]))
                    << (32 * (i % 2));
  }
  return value;
}

Block PaddedBlock(uint64_t first_word, uint64_t bit_length) {
  Block block{};
  block[15] = first_word;
  block[0] = bit_length;
  return block;
}

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vsha512_block> dut{new Vsha512_block{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;

  auto tick = [&]() {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
    dut->clk = 0;
    dut->eval();
  };

  dut->clk = 0;
  dut->rst_n = 0;
  dut->start = 0;
  dut->cont = 0;  // single-block KATs start from the IV
  PutWide(dut->block_in, Block{});
  tick();
  tick();
  dut->rst_n = 1;
  dut->eval();

  auto run_block = [&](const Block& block, const Digest& want,
                       const char* name) -> bool {
    PutWide(dut->block_in, block);
    dut->start = 1;
    dut->eval();
    tick();
    dut->start = 0;
    dut->eval();

    ++checks;
    if (!dut->busy) {
      std::printf("FAIL %s: busy not set after start\n", name);
      return false;
    }

    int cycles = 0;
    while (!dut->done && cycles < 1000) {
      tick();
      ++cycles;
    }
    ++checks;
    if (!dut->done) {
      std::printf("FAIL %s: timed out waiting for done\n", name);
      return false;
    }

    const Digest got = FetchWide<decltype(dut->digest_out), 8>(dut->digest_out);
    ++checks;
    if (got != want) {
      std::printf("FAIL %s got=%s exp=%s\n", name, ToHex(got).c_str(),
                  ToHex(want).c_str());
      return false;
    }
    std::printf("PASS %s\n", name);

    tick();
    ++checks;
    if (dut->done || dut->busy) {
      std::printf("FAIL %s: done/busy did not return idle\n", name);
      return false;
    }
    return true;
  };

  Digest abc{};
  Digest empty{};
  if (!ParseHex("ddaf35a193617abacc417349ae204131"
                "12e6fa4e89a97ea20a9eeee64b55d39a"
                "2192992a274fc1a836ba3c23a3feebbd"
                "454d4423643ce80e2a9ac94fa54ca49f",
                &abc) ||
      !ParseHex("cf83e1357eefb8bdf1542850d66d8007"
                "d620e4050b5715dc83f4a921d36ce9ce"
                "47d0d13c5d85f2b0ff8318d2877eec2f"
                "63b931bd47417a81a538327af927da3e",
                &empty)) {
    std::printf("FAIL internal digest constant\n");
    return 1;
  }

  if (!run_block(PaddedBlock(0x6162638000000000ULL, 24), abc,
                 "sha512(abc)")) {
    return 1;
  }
  if (!run_block(PaddedBlock(0x8000000000000000ULL, 0), empty,
                 "sha512(empty)")) {
    return 1;
  }

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("TB_SHA512 PASS (%llu checks)\n",
              static_cast<unsigned long long>(checks));
  return 0;
}
