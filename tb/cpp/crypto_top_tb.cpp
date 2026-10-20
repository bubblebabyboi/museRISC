// Integration KAT for sigil_crypto_top (issue #19), migrated from
// tb/tb_sigil_crypto_top.v. It drives the AXI4-Lite register
// interface end to end (docs/SPEC.md): DIN/DOUT word ordering,
// CTRL engine/op select, STATUS busy/done, MODSEL, and custom
// modulus registers. Leaf engines have their own KATs; vectors are
// reused so failures localise to the register/AXI layer.
#include "Vsigil_crypto_top.h"
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

using Field = std::array<uint64_t, 4>;

int HexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool ParseHex(const char* hex, Field* out) {
  constexpr size_t kDigits = 64;
  if (std::strlen(hex) != kDigits) return false;
  out->fill(0);
  for (size_t pos = 0; pos < kDigits; ++pos) {
    const int v = HexValue(hex[kDigits - 1 - pos]);
    if (v < 0) return false;
    (*out)[pos / 16] |= static_cast<uint64_t>(v) << (4 * (pos % 16));
  }
  return true;
}

std::string ToHex(const Field& value) {
  static constexpr char kDigits[] = "0123456789abcdef";
  std::string out;
  out.reserve(64);
  for (size_t pos = 64; pos > 0; --pos) {
    const size_t nibble = pos - 1;
    out.push_back(kDigits[(value[nibble / 16] >> (4 * (nibble % 16))) & 0xf]);
  }
  return out;
}

Field Small(uint64_t value) {
  Field out{};
  out[0] = value;
  return out;
}

Field SubSmall(Field value, uint64_t amount) {
  uint64_t borrow = amount;
  for (uint64_t& word : value) {
    const uint64_t before = word;
    word -= borrow;
    borrow = before < borrow ? 1 : 0;
    if (borrow == 0) break;
  }
  return value;
}

uint32_t WordAt(const Field& value, int index) {
  return static_cast<uint32_t>(value[index / 2] >> (32 * (index % 2)));
}

void SetWord(Field* value, int index, uint32_t word) {
  (*value)[index / 2] |= static_cast<uint64_t>(word) << (32 * (index % 2));
}

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vsigil_crypto_top> dut{
      new Vsigil_crypto_top{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;

  Field secp{};
  Field c255{};
  Field mixed_a{};
  Field mixed_b{};
  Field mixed_want{};
  Field sha_abc{};
  Field sha_empty{};
  if (!ParseHex("ffffffffffffffffffffffffffffffff"
                "fffffffffffffffffffffffefffffc2f",
                &secp) ||
      !ParseHex("7fffffffffffffffffffffffffffffff"
                "ffffffffffffffffffffffffffffffed",
                &c255) ||
      !ParseHex("1234567890abcdef1234567890abcdef"
                "1234567890abcdef1234567890abcdef",
                &mixed_a) ||
      !ParseHex("fedcba0987654321fedcba0987654321"
                "fedcba0987654321fedcba0987654321",
                &mixed_b) ||
      !ParseHex("0dabcd892d293feb6a2a19b97d502825"
                "c6a865e9cd771060354652a4e4897181",
                &mixed_want) ||
      !ParseHex("ba7816bf8f01cfea414140de5dae2223"
                "b00361a396177a9cb410ff61f20015ad",
                &sha_abc) ||
      !ParseHex("e3b0c44298fc1c149afbf4c8996fb924"
                "27ae41e4649b934ca495991b7852b855",
                &sha_empty)) {
    std::printf("FAIL internal crypto-top constant\n");
    return 1;
  }

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
  dut->s_axi_awaddr = 0;
  dut->s_axi_awvalid = 0;
  dut->s_axi_wdata = 0;
  dut->s_axi_wvalid = 0;
  dut->s_axi_bready = 0;
  dut->s_axi_araddr = 0;
  dut->s_axi_arvalid = 0;
  dut->s_axi_rready = 0;
  tick();
  tick();
  dut->rst_n = 1;
  dut->eval();

  auto wr = [&](uint8_t addr, uint32_t data) -> bool {
    dut->s_axi_awaddr = addr;
    dut->s_axi_wdata = data;
    dut->s_axi_awvalid = 1;
    dut->s_axi_wvalid = 1;
    dut->eval();
    ++checks;
    if (!dut->s_axi_awready || !dut->s_axi_wready) {
      std::printf("FAIL wr %02x: write not accepted\n", addr);
      return false;
    }
    tick();
    dut->s_axi_awvalid = 0;
    dut->s_axi_wvalid = 0;
    dut->eval();
    ++checks;
    if (!dut->s_axi_bvalid || dut->s_axi_bresp != 0) {
      std::printf("FAIL wr %02x bvalid=%d bresp=%u\n", addr,
                  dut->s_axi_bvalid ? 1 : 0,
                  static_cast<unsigned>(dut->s_axi_bresp));
      return false;
    }
    dut->s_axi_bready = 1;
    tick();
    dut->s_axi_bready = 0;
    dut->eval();
    ++checks;
    if (dut->s_axi_bvalid) {
      std::printf("FAIL wr %02x: bvalid did not clear\n", addr);
      return false;
    }
    return true;
  };

  auto rd = [&](uint8_t addr, uint32_t* out) -> bool {
    dut->s_axi_araddr = addr;
    dut->s_axi_arvalid = 1;
    dut->eval();
    ++checks;
    if (!dut->s_axi_arready) {
      std::printf("FAIL rd %02x: read not accepted\n", addr);
      return false;
    }
    tick();
    dut->s_axi_arvalid = 0;
    dut->eval();
    ++checks;
    if (!dut->s_axi_rvalid || dut->s_axi_rresp != 0) {
      std::printf("FAIL rd %02x rvalid=%d rresp=%u\n", addr,
                  dut->s_axi_rvalid ? 1 : 0,
                  static_cast<unsigned>(dut->s_axi_rresp));
      return false;
    }
    *out = dut->s_axi_rdata;
    dut->s_axi_rready = 1;
    tick();
    dut->s_axi_rready = 0;
    dut->eval();
    ++checks;
    if (dut->s_axi_rvalid) {
      std::printf("FAIL rd %02x: rvalid did not clear\n", addr);
      return false;
    }
    return true;
  };

  uint32_t status = 0;
  auto wait_done = [&](const char* name) -> bool {
    status = 0;
    for (int tries = 0; tries < 20000 && (status & 0x2u) == 0; ++tries) {
      if (!rd(0x04, &status)) return false;
    }
    ++checks;
    if ((status & 0x2u) == 0) {
      std::printf("FAIL %s: done never set (STATUS=%08x)\n", name, status);
      return false;
    }
    return true;
  };

  auto read_dout = [&](Field* out) -> bool {
    out->fill(0);
    for (int i = 0; i < 8; ++i) {
      uint32_t word = 0;
      if (!rd(static_cast<uint8_t>(0x48 + 4 * i), &word)) return false;
      SetWord(out, i, word);
    }
    return true;
  };

  auto check = [&](const Field& got, const Field& want,
                   const char* name) -> bool {
    ++checks;
    if (got != want) {
      std::printf("FAIL %s got=%s exp=%s\n", name, ToHex(got).c_str(),
                  ToHex(want).c_str());
      return false;
    }
    std::printf("PASS %s\n", name);
    return true;
  };

  auto write_field = [&](uint8_t base, const Field& value) -> bool {
    for (int i = 0; i < 8; ++i) {
      if (!wr(static_cast<uint8_t>(base + 4 * i), WordAt(value, i))) {
        return false;
      }
    }
    return true;
  };

  auto clear_din = [&]() -> bool {
    for (int i = 0; i < 16; ++i) {
      if (!wr(static_cast<uint8_t>(0x08 + 4 * i), 0)) return false;
    }
    return true;
  };

  Field got{};
  uint32_t value = 0;

  // SHA-256("abc"): DIN0 is the first message word (the top
  // word-reverses DIN into the block); DOUT0 is the digest low word.
  if (!wr(0x08, 0x61626380u)) return 1;
  for (int i = 1; i < 15; ++i) {
    if (!wr(static_cast<uint8_t>(0x08 + 4 * i), 0)) return 1;
  }
  if (!wr(0x44, 24) || !wr(0x00, 0x1)) return 1;
  if (!rd(0x04, &value)) return 1;
  ++checks;
  if ((value & 0x2u) != 0) {
    std::printf("FAIL sha256(abc): done not cleared by CTRL write\n");
    return 1;
  }
  if (!wait_done("sha256(abc)") || !read_dout(&got) ||
      !check(got, sha_abc, "sha256(abc) via AXI")) {
    return 1;
  }

  // SHA-256(""): reuse DIN regs, rewrite DIN0 and the last word.
  if (!wr(0x08, 0x80000000u) || !wr(0x44, 0) || !wr(0x00, 0x1)) {
    return 1;
  }
  if (!wait_done("sha256(empty)") || !read_dout(&got) ||
      !check(got, sha_empty, "sha256(empty) via AXI")) {
    return 1;
  }

  // Field mul, mixed vector, secp256k1 (MODSEL=0).
  // a = DIN0..7 (low word first), b = DIN8..15.
  if (!write_field(0x08, mixed_a) || !write_field(0x28, mixed_b) ||
      !wr(0x68, 0) || !wr(0x00, 0xa1)) {
    return 1;
  }
  if (!wait_done("field mul mixed secp") || !read_dout(&got) ||
      !check(got, mixed_want, "field mul mixed secp via AXI")) {
    return 1;
  }

  // Field sub 2-3 mod secp = p-1.
  if (!clear_din() || !wr(0x08, 2) || !wr(0x28, 3) ||
      !wr(0x00, 0x61)) {
    return 1;
  }
  if (!wait_done("field sub 2-3 secp") || !read_dout(&got) ||
      !check(got, SubSmall(secp, 1), "field sub 2-3 secp via AXI")) {
    return 1;
  }

  // Field mul (p-2)^2 with MODSEL=1 (Curve25519) = 4.
  const Field c255_m2 = SubSmall(c255, 2);
  if (!write_field(0x08, c255_m2) || !write_field(0x28, c255_m2) ||
      !wr(0x68, 1) || !wr(0x00, 0xa1)) {
    return 1;
  }
  if (!wait_done("field mul (p-2)^2 c25519") || !read_dout(&got) ||
      !check(got, Small(4), "field mul (p-2)^2 c25519 via AXI")) {
    return 1;
  }

  // Custom modulus via MOD regs (MODSEL=2), mul 2*3.
  if (!write_field(0x6c, secp) || !clear_din() || !wr(0x08, 2) ||
      !wr(0x28, 3) || !wr(0x68, 2)) {
    return 1;
  }
  if (!rd(0x68, &value)) return 1;
  ++checks;
  if ((value & 0x3u) != 2) {
    std::printf("FAIL MODSEL readback got=%08x\n", value);
    return 1;
  }
  if (!wr(0x00, 0xa1) || !wait_done("field mul 2*3 custom mod") ||
      !read_dout(&got) ||
      !check(got, Small(6), "field mul 2*3 custom mod via AXI")) {
    return 1;
  }

  // Engine 1 (Keccak) is reserved: a start must leave STATUS idle
  // (no busy, no done), not hang the slave.
  if (!wr(0x00, 0x11)) return 1;
  for (int i = 0; i < 20; ++i) tick();
  if (!rd(0x04, &value)) return 1;
  ++checks;
  if ((value & 0x3u) != 0) {
    std::printf("FAIL reserved engine 1: STATUS=%08x (want idle)\n", value);
    return 1;
  }
  std::printf("PASS reserved engine 1 stays idle\n");

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("TB_SIGIL_CRYPTO_TOP PASS (%llu checks)\n",
              static_cast<unsigned long long>(checks));
  return 0;
}
