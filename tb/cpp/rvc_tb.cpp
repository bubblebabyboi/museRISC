// museRISC in-house core: RVC decompressor unit testbench.
// Exhaustive: all 65536 parcels compared against a golden
// expander written directly from the C-extension manual
// tables (Zca + Zcb + Zcd on RV64), structured differently
// from the RTL so transcription slips don't cancel out.

#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "verilated.h"
#include "verilated_cov.h"
#include "Vmuserisc_rvc.h"

static Vmuserisc_rvc* dut;
static long checks = 0, fails = 0;

namespace gold {

static uint32_t I(uint32_t imm, int rs1, int f3, int rd, int opc) {
  return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) |
         (rd << 7) | opc;
}
static uint32_t R(int f7, int rs2, int rs1, int f3, int rd, int opc) {
  return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) |
         (rd << 7) | opc;
}
static uint32_t S(uint32_t imm, int rs2, int rs1, int f3, int opc) {
  return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) |
         (f3 << 12) | ((imm & 0x1F) << 7) | opc;
}
static uint32_t B(uint32_t imm, int rs2, int rs1, int f3) {
  return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) |
         (rs2 << 20) | (rs1 << 15) | (f3 << 12) |
         (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63;
}
static uint32_t U(uint32_t imm20, int rd, int opc) {
  return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opc;
}
static uint32_t J(uint32_t imm, int rd) {
  return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) |
         (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) |
         (rd << 7) | 0x6F;
}
static int32_t sext(uint32_t v, int bits) {
  return (int32_t)(v << (32 - bits)) >> (32 - bits);
}

struct Out { uint32_t insn; bool illegal; };

static Out expand(uint16_t c) {
  const int quad = c & 3;
  const int f3 = (c >> 13) & 7;
  auto bit = [&](int i) { return (c >> i) & 1; };
  auto bits = [&](int hi, int lo) {
    return (c >> lo) & ((1u << (hi - lo + 1)) - 1);
  };
  const int rdp = 8 + bits(4, 2), rs1p = 8 + bits(9, 7);
  const int rd = bits(11, 7), rs2 = bits(6, 2);
  const int32_t imm6 = sext((bit(12) << 5) | bits(6, 2), 6);
  Out o{0, false};

  if (quad == 0) {
    switch (f3) {
      case 0: {  // c.addi4spn
        uint32_t imm = (bits(10,7) << 6) | (bits(12,11) << 4) |
                       (bit(5) << 3) | (bit(6) << 2);
        if (imm == 0) o.illegal = true;
        o.insn = I(imm, 2, 0, rdp, 0x13);
        return o;
      }
      case 1: case 3: {  // c.fld / c.ld
        uint32_t imm = (bit(6) << 7) | (bit(5) << 6) | (bits(12,10) << 3);
        o.insn = I(imm, rs1p, 3, rdp, f3 == 1 ? 0x07 : 0x03);
        return o;
      }
      case 2: {  // c.lw
        uint32_t imm = (bit(5) << 6) | (bits(12,10) << 3) | (bit(6) << 2);
        o.insn = I(imm, rs1p, 2, rdp, 0x03);
        return o;
      }
      case 4: {  // Zcb
        uint32_t imm_b = (bit(5) << 1) | bit(6);
        uint32_t imm_h = bit(5) << 1;
        switch (bits(12, 10)) {
          case 0: o.insn = I(imm_b, rs1p, 4, rdp, 0x03); return o;
          case 1: o.insn = I(imm_h, rs1p, bit(6) ? 1 : 5, rdp, 0x03); return o;
          case 2: o.insn = S(imm_b, rdp, rs1p, 0, 0x23); return o;
          case 3:
            if (bit(6)) o.illegal = true;
            o.insn = S(imm_h, rdp, rs1p, 1, 0x23);
            return o;
          default: o.illegal = true; return o;
        }
      }
      case 5: case 7: {  // c.fsd / c.sd
        uint32_t imm = (bit(6) << 7) | (bit(5) << 6) | (bits(12,10) << 3);
        o.insn = S(imm, rdp, rs1p, 3, f3 == 5 ? 0x27 : 0x23);
        return o;
      }
      case 6: {  // c.sw
        uint32_t imm = (bit(5) << 6) | (bits(12,10) << 3) | (bit(6) << 2);
        o.insn = S(imm, rdp, rs1p, 2, 0x23);
        return o;
      }
    }
  }
  if (quad == 1) {
    switch (f3) {
      case 0: o.insn = I(imm6, rd, 0, rd, 0x13); return o;
      case 1:
        if (rd == 0) o.illegal = true;
        o.insn = I(imm6, rd, 0, rd, 0x1B);
        return o;
      case 2: o.insn = I(imm6, 0, 0, rd, 0x13); return o;
      case 3:
        if (rd == 2) {
          int32_t imm = sext((bit(12) << 9) | (bits(4,3) << 7) |
                             (bit(5) << 6) | (bit(2) << 5) |
                             (bit(6) << 4), 10);
          if (imm == 0) o.illegal = true;
          o.insn = I(imm, 2, 0, 2, 0x13);
        } else {
          if (imm6 == 0) o.illegal = true;
          o.insn = U(imm6, rd, 0x37);
        }
        return o;
      case 4: {
        int sub = bits(11, 10);
        uint32_t shamt = (bit(12) << 5) | bits(6, 2);
        if (sub == 0) { o.insn = I(shamt, rs1p, 5, rs1p, 0x13); return o; }
        if (sub == 1) { o.insn = I(0x400 | shamt, rs1p, 5, rs1p, 0x13); return o; }
        if (sub == 2) { o.insn = I(imm6, rs1p, 7, rs1p, 0x13); return o; }
        int rs2p = 8 + bits(4, 2);
        if (!bit(12)) {
          switch (bits(6, 5)) {
            case 0: o.insn = R(0x20, rs2p, rs1p, 0, rs1p, 0x33); break;
            case 1: o.insn = R(0, rs2p, rs1p, 4, rs1p, 0x33); break;
            case 2: o.insn = R(0, rs2p, rs1p, 6, rs1p, 0x33); break;
            case 3: o.insn = R(0, rs2p, rs1p, 7, rs1p, 0x33); break;
          }
          return o;
        }
        switch (bits(6, 5)) {
          case 0: o.insn = R(0x20, rs2p, rs1p, 0, rs1p, 0x3B); return o;
          case 1: o.insn = R(0, rs2p, rs1p, 0, rs1p, 0x3B); return o;
          case 2: o.insn = R(1, rs2p, rs1p, 0, rs1p, 0x33); return o;
          case 3:
            switch (bits(4, 2)) {
              case 0: o.insn = I(255, rs1p, 7, rs1p, 0x13); return o;
              case 1: o.insn = I(0x604, rs1p, 1, rs1p, 0x13); return o;
              case 2: o.insn = R(4, 0, rs1p, 4, rs1p, 0x3B); return o;
              case 3: o.insn = I(0x605, rs1p, 1, rs1p, 0x13); return o;
              case 4: o.insn = R(4, 0, rs1p, 0, rs1p, 0x3B); return o;
              case 5: o.insn = I(0xFFF, rs1p, 4, rs1p, 0x13); return o;
              default: o.illegal = true; return o;
            }
        }
        o.illegal = true;
        return o;
      }
      case 5: {
        uint32_t imm = (bit(12) << 11) | (bit(8) << 10) |
                       (bits(10,9) << 8) | (bit(6) << 7) |
                       (bit(7) << 6) | (bit(2) << 5) |
                       (bit(11) << 4) | (bits(5,3) << 1);
        o.insn = J(sext(imm, 12), 0);
        return o;
      }
      case 6: case 7: {
        uint32_t imm = (bit(12) << 8) | (bits(6,5) << 6) |
                       (bit(2) << 5) | (bits(11,10) << 3) |
                       (bits(4,3) << 1);
        o.insn = B(sext(imm, 9), 0, rs1p, f3 == 7 ? 1 : 0);
        return o;
      }
    }
  }
  if (quad == 2) {
    switch (f3) {
      case 0:
        o.insn = I((bit(12) << 5) | bits(6, 2), rd, 1, rd, 0x13);
        return o;
      case 1: {
        uint32_t imm = (bits(4,2) << 6) | (bit(12) << 5) | (bits(6,5) << 3);
        o.insn = I(imm, 2, 3, rd, 0x07);
        return o;
      }
      case 2: {
        if (rd == 0) o.illegal = true;
        uint32_t imm = (bits(3,2) << 6) | (bit(12) << 5) | (bits(6,4) << 2);
        o.insn = I(imm, 2, 2, rd, 0x03);
        return o;
      }
      case 3: {
        if (rd == 0) o.illegal = true;
        uint32_t imm = (bits(4,2) << 6) | (bit(12) << 5) | (bits(6,5) << 3);
        o.insn = I(imm, 2, 3, rd, 0x03);
        return o;
      }
      case 4:
        if (!bit(12)) {
          if (rs2 == 0) {
            if (rd == 0) o.illegal = true;
            o.insn = I(0, rd, 0, 0, 0x67);
          } else {
            o.insn = R(0, rs2, 0, 0, rd, 0x33);
          }
        } else if (rs2 == 0) {
          o.insn = (rd == 0) ? 0x00100073u : I(0, rd, 0, 1, 0x67);
        } else {
          o.insn = R(0, rs2, rd, 0, rd, 0x33);
        }
        return o;
      case 5: case 7: {
        uint32_t imm = (bits(9,7) << 6) | (bits(12,10) << 3);
        o.insn = S(imm, rs2, 2, 3, f3 == 5 ? 0x27 : 0x23);
        return o;
      }
      case 6: {
        uint32_t imm = (bits(8,7) << 6) | (bits(12,9) << 2);
        o.insn = S(imm, rs2, 2, 2, 0x23);
        return o;
      }
    }
  }
  o.illegal = true;
  return o;
}
}  // namespace gold

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const char* cov_path = std::getenv("COV_FILE");
  dut = new Vmuserisc_rvc{&context};

  for (uint32_t c = 0; c < 65536; c++) {
    if ((c & 3) == 3) continue;  // not a 16-bit parcel
    dut->in_i = (uint16_t)c;
    dut->eval();
    gold::Out g = gold::expand((uint16_t)c);
    checks++;
    bool ok = (dut->illegal_o == (g.illegal ? 1 : 0)) &&
              (g.illegal || dut->out_o == g.insn);
    if (!ok) {
      if (fails < 15)
        std::printf("FAIL c=%04x got=%08x ill=%d want=%08x ill=%d\n",
                    c, dut->out_o, dut->illegal_o, g.insn, g.illegal);
      fails++;
    }
  }

  dut->final();
  // Write coverage while the model (which owns the counters) is
  // still alive; writing after `delete dut` read freed memory.
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  delete dut;
  if (fails) { std::printf("RVC TB FAIL (%ld/%ld)\n", fails, checks);
    return 1; }
  std::printf("RVC TB PASS (%ld checks)\n", checks);
  return 0;
}
