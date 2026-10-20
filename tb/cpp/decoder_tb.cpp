// Unit test for sigil_decoder: sweeps opcode x funct3 x funct7
// space (plus immediate-pattern corners) against a golden model
// formulated directly as the RV64I encoding whitelist from the ISA
// manual, independent of the RTL's case structure. Checks the full
// control struct and the selected immediate. Exits 0 on pass.
#include "Vsigil_decoder.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>

namespace {
enum AluOp { ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, COPY_B };

struct Ctrl {
  bool valid = false, reg_write = false, mem_read = false, mem_write = false;
  bool alu_src_imm = false, alu_a_pc = false, word_op = false, muldiv = false;
  bool csr = false, csr_imm = false, mret = false, sret = false;
  bool wfi = false, sfence = false;
  bool hlv = false, hlvx = false, hfence = false, hfence_gvma = false;
  bool vec = false, vec_rd = false, vset = false;
  int funct3 = 0;
  bool amo = false, lr = false, sc = false;
  int amo_op = 0;
  bool bext = false;
  int bext_op = 0;
  bool fp = false, fp_rs1 = false, fp_rs2 = false, fp_rd = false;
  bool fp_rm = false, fp_op = false, fmt_d = false;
  int fpu_op = 0, fpu_aux = 0;
  int alu_op = ADD;
  bool branch = false, jal = false, jalr = false, ecall = false, ebreak = false;
  uint64_t imm = 0;
};

int AluFor(int funct3, bool alt) {
  switch (funct3) {
    case 0: return alt ? SUB : ADD;
    case 1: return SLL;
    case 2: return SLT;
    case 3: return SLTU;
    case 4: return XOR;
    case 5: return alt ? SRA : SRL;
    case 6: return OR;
    default: return AND;
  }
}

uint64_t Sext(uint64_t v, int bits) {
  const uint64_t m = 1ull << (bits - 1);
  return (v ^ m) - m;
}

Ctrl Golden(uint32_t insn) {
  Ctrl c;
  const uint32_t op = insn & 0x7f;
  const uint32_t f3 = (insn >> 12) & 7;
  const uint32_t f7 = (insn >> 25) & 0x7f;
  const uint64_t imm_i = Sext(insn >> 20, 12);
  const uint64_t imm_s = Sext(((insn >> 25) << 5) | ((insn >> 7) & 0x1f), 12);
  const uint64_t imm_b = Sext((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) |
                              (((insn >> 25) & 0x3f) << 5) | (((insn >> 8) & 0xf) << 1), 13);
  const uint64_t imm_u = Sext(insn >> 12, 20) << 12;
  const uint64_t imm_j = Sext((((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xff) << 12) |
                              (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3ff) << 1), 21);
  c.imm = imm_i;
  c.funct3 = static_cast<int>(f3);
  const bool alt = ((insn >> 30) & 1) != 0;
  switch (op) {
    case 0x37:  // LUI
      c.valid = c.reg_write = c.alu_src_imm = true;
      c.alu_op = COPY_B; c.imm = imm_u; break;
    case 0x17:  // AUIPC
      c.valid = c.reg_write = c.alu_src_imm = c.alu_a_pc = true;
      c.alu_op = ADD; c.imm = imm_u; break;
    case 0x6f:  // JAL
      c.valid = c.reg_write = c.jal = true; c.imm = imm_j; break;
    case 0x67:  // JALR
      if (f3 == 0) { c.valid = c.reg_write = c.jalr = true; c.imm = imm_i; }
      break;
    case 0x63:  // branches: funct3 2,3 reserved
      if (f3 != 2 && f3 != 3) { c.valid = c.branch = true; c.imm = imm_b; }
      break;
    case 0x03:  // loads: funct3 7 reserved
      if (f3 != 7) {
        c.valid = c.reg_write = c.mem_read = c.alu_src_imm = true; c.imm = imm_i;
      }
      break;
    case 0x23:  // stores: funct3 0..3
      if (f3 <= 3) { c.valid = c.mem_write = c.alu_src_imm = true; c.imm = imm_s; }
      break;
    case 0x2f: {  // AMO / LR / SC: funct3 2=.W 3=.D, funct5 selects
      if (f3 == 2 || f3 == 3) {
        const uint32_t f5 = insn >> 27;
        const uint32_t rs2 = (insn >> 20) & 31u;
        c.alu_src_imm = true;
        c.imm = 0;
        c.amo_op = static_cast<int>(f5);
        if (f5 == 0x02) {
          if (rs2 == 0) c.valid = c.reg_write = c.mem_read = c.lr = true;
        } else if (f5 == 0x03) {
          c.valid = c.reg_write = c.mem_read = c.mem_write = c.sc = true;
        } else if (f5 == 0x00 || f5 == 0x01 || f5 == 0x04 || f5 == 0x08 ||
                   f5 == 0x0c || f5 == 0x10 || f5 == 0x14 || f5 == 0x18 ||
                   f5 == 0x1c) {
          c.valid = c.reg_write = c.mem_read = c.mem_write = c.amo = true;
        }
      }
      break;
    }
    case 0x07: case 0x27: {  // FL*/FS* and vector loads/stores
      const bool is_store = (op == 0x27);
      const uint32_t nf = (insn >> 29) & 7, mop = (insn >> 26) & 3;
      const uint32_t lumop = (insn >> 20) & 31;
      bool vec_ls = false;
      int vclass = 100;
      if ((f3 == 0 || f3 == 5 || f3 == 6 || f3 == 7) &&
          ((insn >> 28) & 1) == 0) {
        if (mop == 0) {
          if (lumop == 0) { vec_ls = true; vclass = 100; }
          else if (lumop == 8) {
            vec_ls = nf == 0 || nf == 1 || nf == 3 || nf == 7;
            vclass = 103;
          } else if (!is_store && lumop == 16) {
            vec_ls = true; vclass = 104;
          } else if (lumop == 11 && f3 == 0) {
            vec_ls = nf == 0; vclass = 105;
          }
        } else {
          vec_ls = true;
          vclass = mop == 2 ? 101 : 102;
        }
      }
      if (vec_ls) {
        c.valid = c.alu_src_imm = c.vec = true;
        c.mem_read = !is_store;
        c.mem_write = is_store;
        c.vec_rd = !is_store;
        c.bext_op = vclass;
        c.imm = 0;
      } else if (f3 == 2 || f3 == 3) {
        c.valid = c.alu_src_imm = c.fp = true;
        c.mem_read = !is_store;
        c.mem_write = is_store;
        c.fp_rd = !is_store;
        c.fp_rs2 = is_store;
        c.fmt_d = (f3 == 3);
        c.imm = is_store ? imm_s : imm_i;
      }
      break;
    }
    case 0x43: case 0x47: case 0x4b: case 0x4f: {  // FMA group
      const uint32_t fmt = (insn >> 25) & 3;
      if (fmt <= 1 && (f3 <= 4 || f3 == 7)) {
        c.valid = c.fp = c.fp_op = c.fp_rm = c.fp_rd = true;
        c.fp_rs1 = c.fp_rs2 = true;
        c.fmt_d = (fmt == 1);
        c.fpu_op = 12 + static_cast<int>((op >> 2) & 3);
      }
      break;
    }
    case 0x53: {  // OP-FP
      const uint32_t fmt = (insn >> 25) & 3;
      const uint32_t f5 = insn >> 27;
      const uint32_t rs2 = (insn >> 20) & 31u;
      const bool rm_ok = (f3 <= 4 || f3 == 7);
      if (fmt <= 1) {
        c.fp = c.fp_op = true;
        c.fmt_d = (fmt == 1);
        switch (f5) {
          case 0x00: case 0x01: case 0x02: case 0x03:
            if (rm_ok) { c.valid = c.fp_rd = c.fp_rs1 = c.fp_rs2 =
                         c.fp_rm = true;
                         c.fpu_op = static_cast<int>(f5); }
            break;
          case 0x0b:
            if (rs2 == 0 && rm_ok) { c.valid = c.fp_rd = c.fp_rs1 =
                                     c.fp_rm = true; c.fpu_op = 4; }
            break;
          case 0x04:
            if (f3 <= 2) { c.valid = c.fp_rd = c.fp_rs1 = c.fp_rs2 = true;
                           c.fpu_op = 5;
                           c.fpu_aux = static_cast<int>(f3); }
            break;
          case 0x05:
            if (f3 <= 1) { c.valid = c.fp_rd = c.fp_rs1 = c.fp_rs2 = true;
                           c.fpu_op = 6;
                           c.fpu_aux = static_cast<int>(f3); }
            break;
          case 0x08:
            if (rs2 <= 1 && ((rs2 & 1) != fmt) && rm_ok) {
              c.valid = c.fp_rd = c.fp_rs1 = c.fp_rm = true;
              c.fpu_op = 11;
            }
            break;
          case 0x18:
            if (rs2 <= 3 && rm_ok) { c.valid = c.reg_write = c.fp_rs1 =
                                     c.fp_rm = true;
                                     c.fpu_op = 9;
                                     c.fpu_aux = static_cast<int>(rs2); }
            break;
          case 0x1a:
            if (rs2 <= 3 && rm_ok) { c.valid = c.fp_rd = c.fp_rm = true;
                                     c.fpu_op = 10;
                                     c.fpu_aux = static_cast<int>(rs2); }
            break;
          case 0x1c:
            if (rs2 == 0 && f3 <= 1) {
              c.valid = c.reg_write = c.fp_rs1 = true;
              c.fpu_op = (f3 == 1) ? 8 : 17;
            }
            break;
          case 0x1e:
            if (rs2 == 0 && f3 == 0) { c.valid = c.fp_rd = true;
                                       c.fpu_op = 16; }
            break;
          case 0x14:
            if (f3 <= 2) { c.valid = c.reg_write = c.fp_rs1 = c.fp_rs2 =
                           true; c.fpu_op = 7;
                           c.fpu_aux = static_cast<int>(f3); }
            break;
          default: break;
        }
        if (!c.valid) { c.fp = c.fp_op = false; c.fmt_d = (fmt == 1); }
      }
      break;
    }
    case 0x13: {  // OP-IMM; ADDI never becomes SUB
      const uint32_t imm12 = insn >> 20;
      const uint32_t rs2f = (insn >> 20) & 31u;
      auto bext_imm = [&](int bop, bool src_imm) {
        c.valid = c.reg_write = c.bext = true;
        c.bext_op = bop;
        c.alu_src_imm = src_imm;
        c.imm = imm_i;
      };
      if (f3 == 1 && (imm12 >> 5) == 0x30) {
        // clz/ctz/cpop/sext.b/sext.h
        if (rs2f == 0) bext_imm(11, false);
        else if (rs2f == 1) bext_imm(13, false);
        else if (rs2f == 2) bext_imm(15, false);
        else if (rs2f == 4) bext_imm(21, false);
        else if (rs2f == 5) bext_imm(22, false);
        break;
      }
      if (f3 == 1 && (imm12 >> 5) == 0x18) {
        if (rs2f == 0) bext_imm(48, false);              // aes64im
        else if ((rs2f & 16) && (rs2f & 15) <= 10)
          bext_imm(49, true);                            // aes64ks1i
        break;
      }
      if (f3 == 1 && (imm12 >> 5) == 0x08) {
        static const int kSha[8] = {53, 54, 51, 52, 57, 58, 55, 56};
        if (rs2f < 8) bext_imm(kSha[rs2f], false);
        break;
      }
      if (f3 == 1 && (imm12 >> 6) == 0x12) { bext_imm(32, true); break; }
      if (f3 == 1 && (imm12 >> 6) == 0x1A) { bext_imm(34, true); break; }
      if (f3 == 1 && (imm12 >> 6) == 0x0A) { bext_imm(35, true); break; }
      if (f3 == 5 && (imm12 >> 6) == 0x18) { bext_imm(25, true); break; }
      if (f3 == 5 && (imm12 >> 6) == 0x12) { bext_imm(33, true); break; }
      if (f3 == 5 && imm12 == 0x287) { bext_imm(27, false); break; }
      if (f3 == 5 && imm12 == 0x687) { bext_imm(41, false); break; }
      if (f3 == 5 && imm12 == 0x6B8) { bext_imm(28, false); break; }
      c.valid = c.reg_write = c.alu_src_imm = true;
      c.alu_op = AluFor(static_cast<int>(f3), f3 == 5 ? alt : false);
      c.imm = imm_i;
      const uint32_t top = insn >> 26;
      if (f3 == 1 && top != 0) c.valid = false;
      if (f3 == 5 && top != 0 && top != 0x10) c.valid = false;
      break;
    }
    case 0x33:  // OP, plus M under funct7=1 (all funct3 defined)
      if (f7 == 0 || (f7 == 0x20 && (f3 == 0 || f3 == 5))) {
        c.valid = c.reg_write = true;
        c.alu_op = AluFor(static_cast<int>(f3), alt);
      } else if (f7 == 1) {
        c.valid = c.reg_write = c.muldiv = true;
      } else {
        int bop = -1;
        switch (f7) {
          case 0x04: bop = f3 == 4 ? 38 : f3 == 7 ? 39 : -1; break;
          case 0x05: bop = f3 == 1 ? 29 : f3 == 2 ? 31 : f3 == 3 ? 30 :
                           f3 == 4 ? 19 : f3 == 5 ? 20 : f3 == 6 ? 17 :
                           f3 == 7 ? 18 : -1; break;
          case 0x07: bop = f3 == 5 ? 36 : f3 == 7 ? 37 : -1; break;
          case 0x10: bop = f3 == 2 ? 1 : f3 == 4 ? 2 : f3 == 6 ? 3 : -1; break;
          case 0x14: bop = f3 == 1 ? 35 : f3 == 2 ? 42 : f3 == 4 ? 43 : -1; break;
          case 0x20: bop = f3 == 4 ? 10 : f3 == 6 ? 9 : f3 == 7 ? 8 : -1; break;
          case 0x24: bop = f3 == 1 ? 32 : f3 == 5 ? 33 : -1; break;
          case 0x30: bop = f3 == 1 ? 23 : f3 == 5 ? 25 : -1; break;
          case 0x34: bop = f3 == 1 ? 34 : -1; break;
          case 0x19: bop = f3 == 0 ? 44 : -1; break;
          case 0x1B: bop = f3 == 0 ? 45 : -1; break;
          case 0x1D: bop = f3 == 0 ? 46 : -1; break;
          case 0x1F: bop = f3 == 0 ? 47 : -1; break;
          case 0x3F: bop = f3 == 0 ? 50 : -1; break;
          default: break;
        }
        if (bop >= 0) {
          c.valid = c.reg_write = c.bext = true;
          c.bext_op = bop;
        }
      }
      break;
    case 0x1b: {  // OP-IMM-32: ADDIW (0), SLLIW (1), SRLIW/SRAIW (5)
      const uint32_t imm12w = insn >> 20;
      const uint32_t rs2fw = (insn >> 20) & 31u;
      if (f3 == 1 && (imm12w >> 5) == 0x30 &&
          (rs2fw == 0 || rs2fw == 1 || rs2fw == 2)) {
        c.valid = c.reg_write = c.bext = true;
        c.bext_op = rs2fw == 0 ? 12 : rs2fw == 1 ? 14 : 16;
        c.imm = imm_i;
        break;
      }
      if (f3 == 1 && (imm12w >> 6) == 0x02) {
        c.valid = c.reg_write = c.bext = c.alu_src_imm = true;
        c.bext_op = 7;
        c.imm = imm_i;
        break;
      }
      if (f3 == 5 && (imm12w >> 5) == 0x30) {
        c.valid = c.reg_write = c.bext = c.alu_src_imm = true;
        c.bext_op = 26;
        c.imm = imm_i;
        break;
      }
      c.word_op = true;
      c.alu_op = AluFor(static_cast<int>(f3), f3 == 5 ? alt : false);
      c.imm = imm_i;
      if (f3 == 0 || f3 == 1 || f3 == 5) {
        c.valid = c.reg_write = c.alu_src_imm = true;
        if (f3 == 1 && f7 != 0) c.valid = false;
        if (f3 == 5 && f7 != 0 && f7 != 0x20) c.valid = false;
      }
      break;
    }
    case 0x3b:  // OP-32 + M W-variants: MULW, DIV[U]W, REM[U]W only
      c.word_op = true;
      c.alu_op = AluFor(static_cast<int>(f3), alt);
      if ((f7 == 0 && (f3 == 0 || f3 == 1 || f3 == 5)) ||
          (f7 == 0x20 && (f3 == 0 || f3 == 5))) {
        c.valid = c.reg_write = true;
      } else if (f7 == 1 && (f3 == 0 || f3 >= 4)) {
        c.valid = c.reg_write = c.muldiv = true;
      } else {
        int bop = -1;
        if (f7 == 0x04 && f3 == 0) bop = 0;
        if (f7 == 0x04 && f3 == 4) bop = 40;
        if (f7 == 0x10 && f3 == 2) bop = 4;
        if (f7 == 0x10 && f3 == 4) bop = 5;
        if (f7 == 0x10 && f3 == 6) bop = 6;
        if (f7 == 0x30 && f3 == 1) bop = 24;
        if (f7 == 0x30 && f3 == 5) bop = 26;
        if (bop >= 0) {
          c.valid = c.reg_write = c.bext = true;
          c.bext_op = bop;
        }
      }
      break;
    case 0x0f:  // FENCE / FENCE.I
      c.valid = true;
      break;
    case 0x57: {  // OP-V (RVV 1.0 integer classes)
      c.imm = static_cast<uint64_t>(
          static_cast<int64_t>(static_cast<int32_t>(insn << 12) >> 27));
      const uint32_t f6 = insn >> 26;
      const bool vm = (insn >> 25) & 1;
      const uint32_t vs2f = (insn >> 20) & 31, vs1f = (insn >> 15) & 31;
      if (f3 == 7) {
        if ((insn >> 31) == 0) {
          c.valid = c.vec = c.vset = c.reg_write = true;
          c.fpu_aux = 0;
        } else if (((insn >> 30) & 3) == 3) {
          c.valid = c.vec = c.vset = c.reg_write = true;
          c.fpu_aux = 1;
        } else if (((insn >> 25) & 0x7f) == 0x40) {
          c.valid = c.vec = c.vset = c.reg_write = true;
          c.fpu_aux = 2;
        }
        break;
      }
      const bool opm = (f3 == 2 || f3 == 6);
      const bool vf = (f3 == 5);
      const int form = (f3 == 0 || f3 == 2 || f3 == 1) ? 0
                       : (f3 == 4 || f3 == 6 || f3 == 5) ? 1 : 2;
      int vop = -1;
      bool ok = true;
      if (f3 == 1 || f3 == 5) {
        // OPFVV/OPFVF (stage 9): FPU op in imm[4:0], aux in
        // imm[6:5], swap/wide/madd in imm[7].
        c.imm = 0;
        switch (f6) {
          case 0: vop = 88; c.imm = 0; break;
          case 2: vop = 88; c.imm = 1; break;
          case 39: vop = 88; c.imm = (1 << 7) | 1; ok = vf; break;
          case 4: vop = 88; c.imm = 6; break;
          case 6: vop = 88; c.imm = (1 << 5) | 6; break;
          case 8: case 9: case 10:
            vop = 88; c.imm = (((insn >> 26) & 3) << 5) | 5; break;
          case 32: vop = 88; c.imm = 3; break;
          case 33: vop = 88; c.imm = (1 << 7) | 3; ok = vf; break;
          case 36: vop = 88; c.imm = 2; break;
          case 40: case 41: case 42: case 43:
            vop = 90; c.imm = (1 << 7) | (((insn >> 26) & 3) << 5);
            break;
          case 44: case 45: case 46: case 47:
            vop = 90; c.imm = ((insn >> 26) & 3) << 5; break;
          case 48: vop = 89; c.imm = 0; break;
          case 50: vop = 89; c.imm = 1; break;
          case 52: vop = 89; c.imm = (1 << 7) | 0; break;
          case 54: vop = 89; c.imm = (1 << 7) | 1; break;
          case 56: vop = 89; c.imm = 2; break;
          case 60: case 61: case 62: case 63:
            vop = 91; c.imm = ((insn >> 26) & 3) << 5; break;
          case 24: vop = 92; c.imm = 0; break;
          case 28: vop = 92; c.imm = 1; break;
          case 27: vop = 92; c.imm = 2; break;
          case 25: vop = 92; c.imm = 3; break;
          case 29: vop = 92; c.imm = 4; ok = vf; break;
          case 31: vop = 92; c.imm = 5; ok = vf; break;
          case 18:
            vop = 94; c.imm = vs1f;
            ok = !vf && vs1f < 24 &&
                 ((vs1f & 7) != 5 || vs1f == 21) &&
                 ((vs1f & 7) != 4 || vs1f >= 8);
            break;
          case 19:
            vop = 93;
            ok = !vf && (vs1f == 0 || vs1f == 4 || vs1f == 5 ||
                         vs1f == 16);
            c.imm = vs1f == 16 ? 1 : vs1f == 4 ? 2 : vs1f == 5 ? 3 : 0;
            break;
          case 1: case 3: case 5: case 7:
            vop = 95; c.imm = (insn >> 27) & 3; ok = !vf; break;
          case 49: case 51:
            vop = 96; c.imm = (insn >> 27) & 1; ok = !vf; break;
          case 23:
            ok = vf;
            if (!vm) vop = 32;
            else { vop = 9; ok = vf && vs2f == 0; }
            break;
          case 16:
            if (vf) { vop = 10; ok = vs2f == 0; }
            else { vop = 97; ok = vs1f == 0; }
            break;
          case 14: vop = 76; ok = vf; break;
          case 15: vop = 77; ok = vf; break;
          default: ok = false; break;
        }
      } else if (!opm) {
        switch (f6) {
          case 0: vop = 0; break;
          case 2: vop = 1; break;
          case 3: vop = 2; ok = f3 != 0; break;
          case 4: vop = 13; break;
          case 5: vop = 12; break;
          case 6: vop = 15; break;
          case 7: vop = 14; break;
          case 9: vop = 3; break;
          case 10: vop = 4; break;
          case 11: vop = 5; break;
          case 12: vop = 78; break;
          case 14: vop = f3 == 0 ? 79 : 74; break;
          case 15: vop = 75; ok = f3 != 0; break;
          case 16: vop = 28; ok = !vm; break;
          case 17: vop = 29; break;
          case 18: vop = 30; ok = !vm; break;
          case 19: vop = 31; break;
          case 23:
            if (!vm) vop = 32;
            else { vop = 9; ok = vs2f == 0; }
            break;
          case 24: vop = 33; break;
          case 25: vop = 34; break;
          case 26: vop = 35; break;
          case 27: vop = 36; ok = f3 != 3; break;
          case 28: vop = 37; break;
          case 29: vop = 38; break;
          case 30: vop = 39; ok = f3 != 0; break;
          case 31: vop = 40; ok = f3 != 0; break;
          case 32: vop = 45; break;
          case 33: vop = 44; break;
          case 34: vop = 47; ok = f3 != 3; break;
          case 35: vop = 46; ok = f3 != 3; break;
          case 37: vop = 6; break;
          case 39:
            if (f3 == 3) {
              vop = 86;
              ok = vs1f == 0 || vs1f == 1 || vs1f == 3 || vs1f == 7;
            } else vop = 52;
            break;
          case 40: vop = 7; break;
          case 41: vop = 8; break;
          case 42: vop = 53; break;
          case 43: vop = 54; break;
          case 48: vop = 87; ok = f3 == 0; c.imm = 0; break;
          case 49: vop = 87; ok = f3 == 0; c.imm = 1; break;
          case 44: vop = 70; break;
          case 45: vop = 71; break;
          case 46: vop = 73; break;
          case 47: vop = 72; break;
          default: ok = false; break;
        }
      } else {
        switch (f6) {
          case 0: case 1: case 2: case 3:
          case 4: case 5: case 6: case 7:
            vop = 42; ok = f3 == 2; c.imm = (insn >> 26) & 7; break;
          case 8: vop = 49; break;
          case 9: vop = 48; break;
          case 10: vop = 51; break;
          case 11: vop = 50; break;
          case 14: vop = 76; ok = f3 == 6; break;
          case 15: vop = 77; ok = f3 == 6; break;
          case 16:
            if (f3 == 6) { vop = 10; ok = vs2f == 0; }
            else if (vs1f == 0) vop = 11;
            else if (vs1f == 16) vop = 84;
            else if (vs1f == 17) vop = 85;
            else ok = false;
            break;
          case 18:
            vop = 43;
            ok = f3 == 2 && ((insn >> 18) & 3) == 0 && ((insn >> 15) & 7) >= 2;
            c.imm = (insn >> 15) & 7;
            break;
          case 20:
            ok = f3 == 2;
            if (vs1f == 16) vop = 82;
            else if (vs1f == 17 && vs2f == 0) vop = 83;
            else if (vs1f >= 1 && vs1f <= 3) {
              vop = 81; c.imm = (insn >> 15) & 3;
            } else ok = false;
            break;
          case 23: vop = 80; ok = f3 == 2 && vm; break;
          case 24: case 25: case 26: case 27:
          case 28: case 29: case 30: case 31:
            vop = 41; ok = f3 == 2 && vm; c.imm = (insn >> 26) & 7; break;
          case 32: vop = 25; break;
          case 33: vop = 24; break;
          case 34: vop = 27; break;
          case 35: vop = 26; break;
          case 36: vop = 18; break;
          case 37: vop = 16; break;
          case 38: vop = 19; break;
          case 39: vop = 17; break;
          case 41: vop = 21; break;
          case 43: vop = 23; break;
          case 45: vop = 20; break;
          case 47: vop = 22; break;
          case 48: vop = 57; break;
          case 49: vop = 55; break;
          case 50: vop = 61; break;
          case 51: vop = 59; break;
          case 52: vop = 58; break;
          case 53: vop = 56; break;
          case 54: vop = 62; break;
          case 55: vop = 60; break;
          case 56: vop = 64; break;
          case 58: vop = 65; break;
          case 59: vop = 63; break;
          case 60: vop = 67; break;
          case 61: vop = 66; break;
          case 62: vop = 69; ok = f3 == 6; break;
          case 63: vop = 68; break;
          default: ok = false; break;
        }
      }
      if (ok && vop >= 0) {
        c.valid = c.vec = true;
        c.bext_op = vop;
        c.fpu_aux = form;
        if (vf) c.fp_rs1 = true;
        if (vop == 11 || vop == 84 || vop == 85) c.reg_write = true;
        else if (vop == 97) c.fp_rd = true;
        else c.vec_rd = true;
      }
      break;
    }
    case 0x73:  // SYSTEM
      if (f3 == 0) {
        const uint32_t imm12 = insn >> 20;
        if (imm12 == 0) { c.valid = c.ecall = true; }
        else if (imm12 == 1) { c.valid = c.ebreak = true; }
        else if (imm12 == 0x302) { c.valid = c.mret = true; }
        else if (imm12 == 0x102) { c.valid = c.sret = true; }
        else if (imm12 == 0x105) { c.valid = c.wfi = true; }
        else if (((insn >> 25) & 0x7f) == 0x09) { c.valid = c.sfence = true; }
        else if (((insn >> 25) & 0x7f) == 0x11) { c.valid = c.hfence = true; }
        else if (((insn >> 25) & 0x7f) == 0x31) {
          c.valid = c.hfence = c.hfence_gvma = true;
        }
      } else if (f3 == 4) {
        if (((insn >> 28) & 0xf) == 0x6) {
          const uint32_t size = (insn >> 26) & 3;
          const uint32_t var = (insn >> 20) & 31;
          if (!((insn >> 25) & 1)) {
            if (var == 0 || (var == 1 && size != 3) ||
                (var == 3 && (size == 1 || size == 2))) {
              c.valid = c.reg_write = c.mem_read = c.alu_src_imm = true;
              c.hlv = true;
              c.hlvx = (var == 3);
              c.imm = 0;
              c.funct3 = static_cast<int>(
                  size + ((var != 0 && size != 3) ? 4 : 0));
            }
          } else if (((insn >> 7) & 31) == 0) {
            c.valid = c.mem_write = c.alu_src_imm = c.hlv = true;
            c.imm = 0;
            c.funct3 = static_cast<int>(size);
          }
        }
      } else {
        c.valid = c.reg_write = c.csr = true;
        c.csr_imm = ((f3 >> 2) & 1) != 0;
        c.imm = imm_i;
      }
      break;
    default:
      break;
  }
  return c;
}
}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vsigil_decoder> dut{new Vsigil_decoder{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;

  auto run_one = [&](uint32_t insn) -> bool {
    dut->instr_i = insn;
    dut->eval();
    ++checks;
    const Ctrl g = Golden(insn);
    // ctrl_t bit layout must match sigil_pkg.sv declaration order.
    const uint64_t c = dut->ctrl_o;
    auto bit = [&](int i) { return ((c >> i) & 1u) != 0; };
    // funct3 occupies the low 3 bits (last struct member), then the
    // flags in reverse declaration order; check them structurally.
    struct Field { const char* name; bool got; bool want; };
    // Decode the packed struct per the SV declaration (MSB first):
    // valid, reg_write, mem_read, mem_write, alu_src_imm, alu_a_pc,
    // word_op, alu_op[3:0], branch, jal, jalr, ecall, ebreak, funct3
    const int kFunct3 = 0, kEbreak = 3, kEcall = 4, kJalr = 5, kJal = 6,
              kBranch = 7, kAluOp = 8, kWordOp = 12, kAluAPc = 13,
              kAluSrcImm = 14, kMemWrite = 15, kMemRead = 16,
              kRegWrite = 17, kValid = 18, kMuldiv = 19, kCsr = 20,
              kCsrImm = 21, kMret = 22, kSret = 23, kWfi = 24, kSfence = 25,
              kHfenceGvma = 26, kHfence = 27, kHlvx = 28, kHlv = 29,
              kAmo = 30, kLr = 31, kSc = 32, kAmoOp = 33,
              kFp = 38, kFpRs2 = 39, kFpRs1 = 40, kFpRd = 41,
              kFpRm = 42, kFpOp = 43, kFmtD = 44, kFpuAux = 45,
              kFpuOp = 47, kBext = 52, kBextOp = 53,
              kVset = 60, kVecRd = 61, kVec = 62;
    const Field fields[] = {
        {"valid", bit(kValid), g.valid},
        {"reg_write", bit(kRegWrite), g.reg_write && g.valid},
        {"mem_read", bit(kMemRead), g.mem_read && g.valid},
        {"mem_write", bit(kMemWrite), g.mem_write && g.valid},
        {"branch", bit(kBranch), g.branch && g.valid},
        {"jal", bit(kJal), g.jal && g.valid},
        {"jalr", bit(kJalr), g.jalr && g.valid},
        {"muldiv", bit(kMuldiv), g.muldiv && g.valid},
        {"csr", bit(kCsr), g.csr && g.valid},
        {"csr_imm", bit(kCsrImm), g.csr_imm && g.valid},
        {"mret", bit(kMret), g.mret && g.valid},
        {"sret", bit(kSret), g.sret && g.valid},
        {"wfi", bit(kWfi), g.wfi && g.valid},
        {"sfence", bit(kSfence), g.sfence && g.valid},
        {"hfence", bit(kHfence), g.hfence && g.valid},
        {"hfence_gvma", bit(kHfenceGvma), g.hfence_gvma && g.valid},
        {"hlv", bit(kHlv), g.hlv && g.valid},
        {"hlvx", bit(kHlvx), g.hlvx && g.valid},
        {"amo", bit(kAmo), g.amo && g.valid},
        {"lr", bit(kLr), g.lr && g.valid},
        {"sc", bit(kSc), g.sc && g.valid},
        {"fp", bit(kFp), g.fp && g.valid},
        {"fp_rs1", bit(kFpRs1), g.fp_rs1 && g.valid},
        {"fp_rs2", bit(kFpRs2), g.fp_rs2 && g.valid},
        {"fp_rd", bit(kFpRd), g.fp_rd && g.valid},
        {"fp_rm", bit(kFpRm), g.fp_rm && g.valid},
        {"fp_op", bit(kFpOp), g.fp_op && g.valid},
        {"fmt_d", bit(kFmtD), g.fmt_d && g.valid},
        {"bext", bit(kBext), g.bext && g.valid},
        {"vec", bit(kVec), g.vec && g.valid},
        {"vec_rd", bit(kVecRd), g.vec_rd && g.valid},
        {"vset", bit(kVset), g.vset && g.valid},
        {"ecall", bit(kEcall), g.ecall && g.valid},
        {"ebreak", bit(kEbreak), g.ebreak && g.valid},
    };
    for (const Field& fd : fields) {
      if (fd.got != fd.want) {
        std::printf("FAIL insn=0x%08x field %s got=%d want=%d ctrl=0x%llx\n", insn,
                    fd.name, fd.got ? 1 : 0, fd.want ? 1 : 0,
                    static_cast<unsigned long long>(c));
        return false;
      }
    }
    if (g.valid) {
      if (bit(kAluSrcImm) != g.alu_src_imm || bit(kAluAPc) != g.alu_a_pc ||
          bit(kWordOp) != g.word_op ||
          static_cast<int>((c >> kAluOp) & 0xf) != g.alu_op) {
        std::printf("FAIL insn=0x%08x alu fields ctrl=0x%llx want op=%d src_imm=%d a_pc=%d word=%d\n",
                    insn, static_cast<unsigned long long>(c), g.alu_op, g.alu_src_imm ? 1 : 0, g.alu_a_pc ? 1 : 0,
                    g.word_op ? 1 : 0);
        return false;
      }
      if (static_cast<int>((c >> kBextOp) & 0x7f) != g.bext_op) {
        std::printf("FAIL insn=0x%08x bext_op got=%d want=%d\n",
                    insn, static_cast<int>((c >> kBextOp) & 0x7f),
                    g.bext_op);
        return false;
      }
      if (static_cast<int>((c >> kFpuOp) & 0x1f) != g.fpu_op ||
          static_cast<int>((c >> kFpuAux) & 3u) != g.fpu_aux) {
        std::printf("FAIL insn=0x%08x fpu_op/aux got=%d/%d want=%d/%d\n",
                    insn, static_cast<int>((c >> kFpuOp) & 0x1f),
                    static_cast<int>((c >> kFpuAux) & 3u),
                    g.fpu_op, g.fpu_aux);
        return false;
      }
      if (static_cast<int>((c >> kAmoOp) & 0x1f) != g.amo_op) {
        std::printf("FAIL insn=0x%08x amo_op got=%d want=%d\n", insn,
                    static_cast<int>((c >> kAmoOp) & 0x1f), g.amo_op);
        return false;
      }
      if (dut->imm_o != g.imm) {
        std::printf("FAIL insn=0x%08x imm got=0x%016lx want=0x%016lx\n", insn,
                    static_cast<unsigned long>(dut->imm_o),
                    static_cast<unsigned long>(g.imm));
        return false;
      }
    }
    if (dut->rs1_o != ((insn >> 15) & 31) || dut->rs2_o != ((insn >> 20) & 31) ||
        dut->rd_o != ((insn >> 7) & 31) ||
        static_cast<int>((c >> kFunct3) & 7u) != g.funct3) {
      std::printf("FAIL insn=0x%08x register/funct3 extraction\n", insn);
      return false;
    }
    return true;
  };

  // Sweep: every opcode x funct3 x funct7 sample, two immediate
  // patterns (one with sign bits set, one clear).
  const uint32_t f7s[] = {0x00, 0x20, 0x01, 0x7f, 0x10, 0x09};
  for (uint32_t op = 0; op < 128; ++op) {
    for (uint32_t f3 = 0; f3 < 8; ++f3) {
      for (uint32_t f7 : f7s) {
        const uint32_t base = (f7 << 25) | (17u << 20) | (9u << 15) |
                              (f3 << 12) | (13u << 7) | op;
        if (!run_one(base)) return 1;
        if (!run_one(base | 0x80000000u)) return 1;  // sign-bit variant
      }
    }
  }
  // SYSTEM immediate sweep (ECALL=0, EBREAK=1, everything else illegal).
  for (uint32_t imm12 = 0; imm12 < 4096; imm12 += 257) {
    if (!run_one((imm12 << 20) | 0x73u)) return 1;
  }
  if (!run_one(0x00000073u)) return 1;  // ECALL
  if (!run_one(0x00100073u)) return 1;  // EBREAK
  if (!run_one(0x30200073u)) return 1;  // MRET
  if (!run_one(0x10200073u)) return 1;  // SRET
  if (!run_one(0x10500073u)) return 1;  // WFI
  if (!run_one(0x12000073u)) return 1;  // SFENCE.VMA x0, x0
  // Hypervisor encodings (assembler-generated, a0/a1 forms).
  if (!run_one(0x6005c573u)) return 1;  // HLV.B
  if (!run_one(0x6015c573u)) return 1;  // HLV.BU
  if (!run_one(0x6405c573u)) return 1;  // HLV.H
  if (!run_one(0x6415c573u)) return 1;  // HLV.HU
  if (!run_one(0x6805c573u)) return 1;  // HLV.W
  if (!run_one(0x6815c573u)) return 1;  // HLV.WU
  if (!run_one(0x6c05c573u)) return 1;  // HLV.D
  if (!run_one(0x6435c573u)) return 1;  // HLVX.HU
  if (!run_one(0x6835c573u)) return 1;  // HLVX.WU
  if (!run_one(0x62a5c073u)) return 1;  // HSV.B
  if (!run_one(0x66a5c073u)) return 1;  // HSV.H
  if (!run_one(0x6aa5c073u)) return 1;  // HSV.W
  if (!run_one(0x6ea5c073u)) return 1;  // HSV.D
  if (!run_one(0x22c58073u)) return 1;  // HFENCE.VVMA
  if (!run_one(0x62c58073u)) return 1;  // HFENCE.GVMA
  // Vector encodings (assembler-generated).
  if (!run_one(0x0db5f557u)) return 1;  // VSETVLI
  if (!run_one(0xc113f557u)) return 1;  // VSETIVLI
  if (!run_one(0x80c5f557u)) return 1;  // VSETVL
  if (!run_one(0x02430157u)) return 1;  // VADD.VV
  if (!run_one(0x0245c157u)) return 1;  // VADD.VX
  if (!run_one(0x0241b157u)) return 1;  // VADD.VI
  if (!run_one(0x0e45c157u)) return 1;  // VRSUB.VX
  if (!run_one(0x5e05c157u)) return 1;  // VMV.V.X
  if (!run_one(0x5e020157u)) return 1;  // VMV.V.V
  if (!run_one(0x4205e157u)) return 1;  // VMV.S.X
  if (!run_one(0x42202557u)) return 1;  // VMV.X.S
  if (!run_one(0x300010f3u)) return 1;  // CSRRW x2, mstatus, x0-ish fields
  // A extension: LR.W x13,(x9) / SC.W x13,x17,(x9) / AMOADD.D /
  // AMOMAXU.W with aq+rl / illegal funct5 / LR with rs2 != x0.
  if (!run_one((0x02u << 27) | (9u << 15) | (2u << 12) | (13u << 7) | 0x2fu)) return 1;
  if (!run_one((0x03u << 27) | (17u << 20) | (9u << 15) | (2u << 12) | (13u << 7) | 0x2fu)) return 1;
  if (!run_one((0x00u << 27) | (17u << 20) | (9u << 15) | (3u << 12) | (13u << 7) | 0x2fu)) return 1;
  if (!run_one((0x1cu << 27) | (3u << 25) | (17u << 20) | (9u << 15) | (2u << 12) | (13u << 7) | 0x2fu)) return 1;
  if (!run_one((0x05u << 27) | (17u << 20) | (9u << 15) | (2u << 12) | (13u << 7) | 0x2fu)) return 1;
  if (!run_one((0x02u << 27) | (17u << 20) | (9u << 15) | (3u << 12) | (13u << 7) | 0x2fu)) return 1;

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("DECODER TB PASS (%llu checks)\n", static_cast<unsigned long long>(checks));
  return 0;
}
