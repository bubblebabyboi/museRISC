// Vector unit testbench (issue #23, element-serial rework).
//
// DUT: tb/sv/muserisc_vec_harness.sv = muserisc_vec + the banked
// muserisc_vregfile, driven like the core drives them. The whole
// 32x512-bit VRF is loaded through a backdoor before every
// operation and dumped and compared after it, so stray writes,
// tail/prestart/mask-undisturbed behavior and register-group
// overlap are all checked, not only the destination elements.
//
// Golden model: an independent C++ implementation of the RVV
// 1.0 element semantics over a byte-array register file (written
// from the spec, not by mirroring the RTL), covering every
// integer class across SEW, LMUL (incl. fractional), vl, vstart,
// v0 masking, and vta/vma (agnostic = undisturbed in this
// implementation, which the spec allows). Allowed source/
// destination overlaps (identical groups, widening high half,
// narrowing low half, mask-destination low register) are
// exercised to cover the element pipeline's read-ahead hazards.
// FP classes keep host-IEEE directed checks (ACT Vf32/Vf64 run
// the full FP vector suites on the core).
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>

#include "Vmuserisc_vec_harness.h"
#include "verilated.h"
#include "verilated_cov.h"

static long checks = 0;
static long failures = 0;
#define CHECK(cond)                                       \
  do {                                                    \
    ++checks;                                             \
    if (!(cond)) {                                        \
      if (failures < 20)                                  \
        std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, \
                    #cond);                               \
      ++failures;                                         \
    }                                                     \
  } while (0)

namespace {

// VOP_* codes (rtl/core/muserisc_pkg.sv).
enum Op {
  ADD = 0, SUB, RSUB, AND, OR, XOR, SLL, SRL, SRA, MV, MVSX, MVXS,
  MIN, MINU, MAX, MAXU, MUL, MULH, MULHU, MULHSU, MACC, MADD, NMSAC,
  NMSUB, DIV, DIVU, REM, REMU, ADC, MADC, SBC, MSBC, MERGE, CMPEQ,
  CMPNE, CMPLTU, CMPLT, CMPLEU, CMPLE, CMPGTU, CMPGT, MLOG, RED, EXT,
  SADD, SADDU, SSUB, SSUBU, AADD, AADDU, ASUB, ASUBU, SMUL, SSRL, SSRA,
  WADD, WADDW, WADDU, WADDUW, WSUB, WSUBW, WSUBU, WSUBUW, WMUL, WMULU,
  WMULSU, WMACC, WMACCU, WMACCSU, WMACCUS, NSRL, NSRA, NCLIP, NCLIPU,
  SLIDEUP, SLIDEDOWN, SLIDE1UP, SLIDE1DOWN, GATHER, GATHEREI16,
  COMPRESS, MSBIT, IOTA, ID, CPOP, FIRST, MVR, WRED,
  FBIN = 88, FBINW, FMACC, FMACCW, FCMP, FUNARY, FCVT, FRED, FWRED, FMVFS
};
enum Form { VV = 0, VX = 1, VI = 2 };

struct VRF {
  uint8_t b[32][64];
};

uint64_t Ones(int bits) { return bits >= 64 ? ~0ull : ((1ull << bits) - 1); }
int64_t Sx(uint64_t v, int bits) {
  if (bits >= 64) return static_cast<int64_t>(v);
  const uint64_t m = Ones(bits), s = 1ull << (bits - 1);
  return static_cast<int64_t>(((v & m) ^ s) - s);
}
// Element idx of eb bytes in the group based at register r.
uint64_t Get(const VRF& f, int r, int idx, int eb) {
  const int byte = idx * eb;
  uint64_t v = 0;
  for (int k = 0; k < eb; ++k) {
    const int bb = byte + k;
    v |= static_cast<uint64_t>(f.b[(r + bb / 64) & 31][bb % 64]) << (8 * k);
  }
  return v;
}
void Put(VRF& f, int r, int idx, int eb, uint64_t v) {
  const int byte = idx * eb;
  for (int k = 0; k < eb; ++k) {
    const int bb = byte + k;
    f.b[(r + bb / 64) & 31][bb % 64] = static_cast<uint8_t>(v >> (8 * k));
  }
}
bool Bit(const VRF& f, int r, int i) { return (f.b[r][i / 8] >> (i % 8)) & 1; }
void SetBit(VRF& f, int r, int i, bool v) {
  if (v) f.b[r][i / 8] |= static_cast<uint8_t>(1u << (i % 8));
  else f.b[r][i / 8] &= static_cast<uint8_t>(~(1u << (i % 8)));
}

// Fixed-point rounding increment for v >> d (spec 3.8 vxrm).
unsigned __int128 RoundShift(__int128 v, int d, int vxrm, bool arith) {
  if (d == 0) return static_cast<unsigned __int128>(v);
  const unsigned __int128 u = static_cast<unsigned __int128>(v);
  const bool bd1 = (u >> (d - 1)) & 1;
  const bool rest = d >= 2 ? ((u & ((static_cast<unsigned __int128>(1) << (d - 1)) - 1)) != 0) : false;
  const bool bd = (u >> d) & 1;
  unsigned __int128 q = arith ? static_cast<unsigned __int128>(v >> d) : (u >> d);
  int r = 0;
  switch (vxrm) {
    case 0: r = bd1; break;                       // rnu
    case 1: r = bd1 && (rest || bd); break;       // rne
    case 2: r = 0; break;                         // rdn
    default: if (!bd && (bd1 || rest)) q |= 1; break;  // rod
  }
  return q + r;
}

struct Cfg {
  int op = 0, form = 0, sewc = 0, lmulc = 0;  // lmulc: log2 LMUL (-3..3)
  uint64_t vl = 0, vstart = 0;
  bool vm = true, vta = false, vma = false;
  int vs2 = 0, vs1 = 0, vd = 0, nreg = 1;
  uint64_t scalar = 0, imm = 0;
  int vxrm = 0;
};
int Vlmax(const Cfg& c) {
  // LMUL*VLEN/SEW
  const int sew = 8 << c.sewc;
  return c.lmulc >= 0 ? (512 << c.lmulc) / sew : (512 >> -c.lmulc) / sew;
}

struct Out {
  VRF f;
  uint64_t scalar = 0;
  bool sat = false;
};

// ---- Golden model ----
Out Golden(const Cfg& c, const VRF& in) {
  Out o;
  o.f = in;
  VRF& f = o.f;
  const int sew = 8 << c.sewc, eb = sew / 8;
  const uint64_t m = Ones(sew);
  const int vlmax = Vlmax(c);
  const int vl = static_cast<int>(c.vl);
  const uint64_t vstart = c.vstart;
  auto mask = [&](int i) { return Bit(in, 0, i); };
  auto active = [&](int i) { return c.vm || mask(i); };
  auto bop = [&](int i, int beb) -> uint64_t {  // vs1/rs1/imm operand
    if (c.form == VV) return Get(in, c.vs1, i, beb);
    if (c.form == VX) return c.scalar;
    return c.imm;
  };
  const int op = c.op;
  const int shmask = sew - 1;
  auto shamt = [&](uint64_t b, int msk) {
    return static_cast<int>((c.form == VI ? (b & 31) : b) & msk);
  };

  switch (op) {
    case MVR:
      // EEW = SEW, EMUL = nreg: elements [vstart, nreg*VLEN/SEW).
      for (int byte = static_cast<int>(vstart * eb); byte < c.nreg * 64; ++byte) {
        f.b[(c.vd + byte / 64) & 31][byte % 64] = in.b[(c.vs2 + byte / 64) & 31][byte % 64];
      }
      return o;
    case MVXS:
      o.scalar = static_cast<uint64_t>(Sx(Get(in, c.vs2, 0, eb), sew));
      return o;
    case MVSX:
      if (vstart == 0 && vl > 0 && active(0)) Put(f, c.vd, 0, eb, c.scalar);
      return o;
    case CPOP: case FIRST: {
      int64_t first = -1; uint64_t cnt = 0;
      for (int i = static_cast<int>(vstart); i < vl; ++i)
        if (active(i) && Bit(in, c.vs2, i)) { ++cnt; if (first < 0) first = i; }
      o.scalar = op == CPOP ? cnt : static_cast<uint64_t>(first);
      return o;
    }
    default: break;
  }

  // Mask-destination classes.
  if (op == MADC || op == MSBC || (op >= CMPEQ && op <= CMPGT) || op == MLOG || op == MSBIT) {
    bool seen = false;
    for (int i = static_cast<int>(vstart); i < vl; ++i) {
      bool bit = false, wr = active(i);
      if (op == MLOG) {
        const bool x = Bit(in, c.vs2, i), y = Bit(in, c.vs1, i);
        switch (c.imm & 7) {
          case 0: bit = x && !y; break; case 1: bit = x && y; break;
          case 2: bit = x || y; break;  case 3: bit = x != y; break;
          case 4: bit = x || !y; break; case 5: bit = !(x && y); break;
          case 6: bit = !(x || y); break; default: bit = x == y; break;
        }
        wr = true;
      } else if (op == MSBIT) {
        const bool x = active(i) && Bit(in, c.vs2, i);
        if ((c.imm & 3) == 1) bit = !seen && !x;        // sbf
        else if ((c.imm & 3) == 2) bit = !seen && x;    // sof
        else bit = !seen;                               // sif
        if (x) seen = true;
      } else {
        const uint64_t a = Get(in, c.vs2, i, eb), b = bop(i, eb) & m;
        const int64_t as = Sx(a, sew), bs = Sx(b, sew);
        switch (op) {
          case CMPEQ: bit = a == b; break;   case CMPNE: bit = a != b; break;
          case CMPLTU: bit = a < b; break;   case CMPLT: bit = as < bs; break;
          case CMPLEU: bit = a <= b; break;  case CMPLE: bit = as <= bs; break;
          case CMPGTU: bit = a > b; break;   case CMPGT: bit = as > bs; break;
          case MADC: {
            const unsigned __int128 s = static_cast<unsigned __int128>(a) + b + (c.vm ? 0 : mask(i));
            bit = (s >> sew) & 1; wr = true; break;
          }
          case MSBC: {
            const __int128 s = static_cast<__int128>(a) - b - (c.vm ? 0 : mask(i));
            bit = s < 0; wr = true; break;
          }
        }
      }
      if (wr) SetBit(f, c.vd, i, bit);
    }
    return o;
  }

  // Reductions.
  if (op == RED || op == WRED) {
    const int dsew = op == WRED ? 2 * sew : sew;
    uint64_t acc = Get(in, c.vs1, 0, dsew / 8);
    for (int i = static_cast<int>(vstart); i < vl; ++i) {
      if (!active(i)) continue;
      const uint64_t a = Get(in, c.vs2, i, eb);
      if (op == WRED) {
        acc += (c.imm & 1) ? static_cast<uint64_t>(Sx(a, sew)) : a;
        continue;
      }
      const int64_t as = Sx(a, sew), cs = Sx(acc, sew);
      switch (c.imm & 7) {
        case 0: acc = acc + a; break; case 1: acc &= a; break;
        case 2: acc |= a; break;      case 3: acc ^= a; break;
        case 4: acc = (acc & m) < a ? acc : a; break;
        case 5: acc = cs < as ? acc : a; break;
        case 6: acc = (acc & m) > a ? acc : a; break;
        default: acc = cs > as ? acc : a; break;
      }
    }
    if (vl > 0) Put(f, c.vd, 0, dsew / 8, acc);
    return o;
  }

  if (op == COMPRESS) {
    int wp = static_cast<int>(vstart);
    for (int i = static_cast<int>(vstart); i < vl; ++i) {
      if (Bit(in, c.vs1, i)) {
        if (wp < 512 / sew * 8) Put(f, c.vd, wp, eb, Get(in, c.vs2, i, eb));
        ++wp;
      }
    }
    return o;
  }

  // Element-wise classes.
  const bool wide = (op >= WADD && op <= WMACCUS);
  const bool narrow = (op >= NSRL && op <= NCLIPU);
  const int dsew = wide ? 2 * sew : sew;
  const uint64_t dm = Ones(dsew);
  int asew = sew;
  if (narrow || op == WADDW || op == WADDUW || op == WSUBW || op == WSUBUW) asew = 2 * sew;
  if (op == EXT) asew = sew >> (4 - ((c.imm >> 1) & 3));
  const uint64_t am = Ones(asew);
  const uint64_t off = c.form == VX ? c.scalar : (c.imm & 31);
  uint64_t iota = 0;
  for (int i = static_cast<int>(vstart); i < vl; ++i) {
    bool act = active(i) || op == ADC || op == SBC || op == MERGE;
    const uint64_t a = Get(in, c.vs2, i, asew / 8);
    const int64_t as = Sx(a, asew);
    const uint64_t b = bop(i, eb), bm = b & m;
    const int64_t bs = Sx(b, sew);
    const uint64_t old = Get(in, c.vd, i, dsew / 8);
    uint64_t r = 0;
    bool sat = false;
    auto ssat = [&](__int128 v) -> uint64_t {
      const __int128 hi = (static_cast<__int128>(1) << (sew - 1)) - 1, lo = -hi - 1;
      if (v > hi) { sat = true; return static_cast<uint64_t>(hi); }
      if (v < lo) { sat = true; return static_cast<uint64_t>(lo); }
      return static_cast<uint64_t>(v);
    };
    auto usat = [&](unsigned __int128 v) -> uint64_t {
      if (v > m) { sat = true; return m; }
      return static_cast<uint64_t>(v);
    };
    switch (op) {
      case ADD: r = a + b; break;
      case SUB: r = a - b; break;
      case RSUB: r = b - a; break;
      case AND: r = a & b; break;
      case OR: r = a | b; break;
      case XOR: r = a ^ b; break;
      case SLL: r = a << shamt(b, shmask); break;
      case SRL: r = a >> shamt(b, shmask); break;
      case SRA: r = static_cast<uint64_t>(as >> shamt(b, shmask)); break;
      case MV: r = b; break;
      case MIN: r = as < bs ? a : b; break;
      case MINU: r = a < bm ? a : b; break;
      case MAX: r = as > bs ? a : b; break;
      case MAXU: r = a > bm ? a : b; break;
      case MUL: r = a * b; break;
      case MULH: r = static_cast<uint64_t>((static_cast<__int128>(as) * bs) >> sew); break;
      case MULHU: r = static_cast<uint64_t>((static_cast<unsigned __int128>(a) * bm) >> sew); break;
      case MULHSU: r = static_cast<uint64_t>((static_cast<__int128>(as) * static_cast<__int128>(bm)) >> sew); break;
      case MACC: r = old + a * b; break;
      case MADD: r = b * old + a; break;
      case NMSAC: r = old - a * b; break;
      case NMSUB: r = a - b * old; break;
      case DIVU: r = bm == 0 ? m : a / bm; break;
      case REMU: r = bm == 0 ? a : a % bm; break;
      case DIV:
        if (bm == 0) r = m;
        else if (as == Sx(1ull << (sew - 1), sew) && bs == -1) r = a;
        else r = static_cast<uint64_t>(as / bs);
        break;
      case REM:
        if (bm == 0) r = a;
        else if (as == Sx(1ull << (sew - 1), sew) && bs == -1) r = 0;
        else r = static_cast<uint64_t>(as % bs);
        break;
      case ADC: r = a + b + mask(i); break;
      case SBC: r = a - b - mask(i); break;
      case MERGE: r = mask(i) ? b : a; break;
      case SADD: r = ssat(static_cast<__int128>(as) + bs); break;
      case SADDU: r = usat(static_cast<unsigned __int128>(a) + bm); break;
      case SSUB: r = ssat(static_cast<__int128>(as) - bs); break;
      case SSUBU: if (a < bm) { sat = true; r = 0; } else r = a - bm; break;
      case AADD: r = static_cast<uint64_t>(RoundShift(static_cast<__int128>(as) + bs, 1, c.vxrm, true)); break;
      case AADDU: r = static_cast<uint64_t>(RoundShift(static_cast<__int128>(a) + bm, 1, c.vxrm, false)); break;
      case ASUB: r = static_cast<uint64_t>(RoundShift(static_cast<__int128>(as) - bs, 1, c.vxrm, true)); break;
      case ASUBU: r = static_cast<uint64_t>(RoundShift(static_cast<__int128>(a) - static_cast<__int128>(bm), 1, c.vxrm, true)); break;
      case SMUL: {
        const __int128 p = static_cast<__int128>(as) * bs;
        r = ssat(static_cast<__int128>(RoundShift(p, sew - 1, c.vxrm, true)));
        break;
      }
      case SSRL: r = static_cast<uint64_t>(RoundShift(a, shamt(b, shmask), c.vxrm, false)); break;
      case SSRA: r = static_cast<uint64_t>(RoundShift(as, shamt(b, shmask), c.vxrm, true)); break;
      case WADD: case WADDW: r = static_cast<uint64_t>(as + bs); break;
      case WSUB: case WSUBW: r = static_cast<uint64_t>(as - bs); break;
      case WADDU: case WADDUW: r = a + bm; break;
      case WSUBU: case WSUBUW: r = a - bm; break;
      case WMUL: r = static_cast<uint64_t>(as * bs); break;
      case WMULU: r = a * bm; break;
      case WMULSU: r = static_cast<uint64_t>(as * static_cast<int64_t>(bm)); break;
      case WMACC: r = old + static_cast<uint64_t>(as * bs); break;
      case WMACCU: r = old + a * bm; break;
      case WMACCSU: r = old + static_cast<uint64_t>(bs * static_cast<int64_t>(a)); break;
      case WMACCUS: r = old + static_cast<uint64_t>(as * static_cast<int64_t>(bm)); break;
      case NSRL: r = a >> shamt(b, 2 * sew - 1); break;
      case NSRA: r = static_cast<uint64_t>(as >> shamt(b, 2 * sew - 1)); break;
      case NCLIP: r = ssat(static_cast<__int128>(RoundShift(as, shamt(b, 2 * sew - 1), c.vxrm, true))); break;
      case NCLIPU: r = usat(RoundShift(a, shamt(b, 2 * sew - 1), c.vxrm, false)); break;
      case EXT: r = (c.imm & 1) ? static_cast<uint64_t>(as) : (a & am); break;
      case ID: r = static_cast<uint64_t>(i); break;
      case IOTA: r = iota; break;
      case GATHER: case GATHEREI16: {
        const uint64_t idx = op == GATHEREI16 ? Get(in, c.vs1, i, 2)
                             : c.form == VV ? bm : (c.form == VX ? c.scalar : (c.imm & 31));
        r = idx < static_cast<uint64_t>(vlmax) ? Get(in, c.vs2, static_cast<int>(idx), eb) : 0;
        break;
      }
      case SLIDEUP:
        if (static_cast<uint64_t>(i) < off) act = false;
        else r = Get(in, c.vs2, i - static_cast<int>(off), eb);
        break;
      case SLIDEDOWN: {
        const bool ok = off < static_cast<uint64_t>(vlmax) && i + off < static_cast<uint64_t>(vlmax);
        r = ok ? Get(in, c.vs2, i + static_cast<int>(off), eb) : 0;
        break;
      }
      case SLIDE1UP: r = i == 0 ? c.scalar : Get(in, c.vs2, i - 1, eb); break;
      case SLIDE1DOWN: r = i + 1 >= vl ? c.scalar : Get(in, c.vs2, i + 1, eb); break;
      default: std::printf("golden: unhandled op %d\n", op); std::abort();
    }
    if (op == IOTA && active(i) && Bit(in, c.vs2, i)) ++iota;
    if (act) {
      Put(f, c.vd, i, dsew / 8, r & dm);
      if (sat) o.sat = true;
    }
  }
  return o;
}

// ---- DUT driver ----
struct Dut {
  Vmuserisc_vec_harness* d;
  uint64_t cycles = 0;
  void Tick() {
    d->clk_i = 0; d->eval();
    d->clk_i = 1; d->eval();
    ++cycles;
  }
  void Load(const VRF& f) {
    d->tb_we_i = 1;
    for (int w = 0; w < 256; ++w) {
      uint64_t v = 0;
      std::memcpy(&v, &f.b[w >> 3][(w & 7) * 8], 8);
      d->tb_waddr_i = w;
      d->tb_wdata_i = v;
      Tick();
    }
    d->tb_we_i = 0;
  }
  VRF Dump() {
    VRF f;
    d->tb_re_i = 1;
    for (int w = 0; w < 256; ++w) {
      d->tb_raddr_i = w;
      Tick();
      const uint64_t v = d->tb_rdata_o;
      std::memcpy(&f.b[w >> 3][(w & 7) * 8], &v, 8);
    }
    d->tb_re_i = 0;
    return f;
  }
  // Returns cycles from start to done (inclusive of start).
  int Run(const Cfg& c, uint64_t frs = 0, int frm = 0, int ack_delay = 0) {
    d->op_i = c.op; d->form_i = c.form; d->sew_i = c.sewc;
    d->vl_i = c.vl; d->vstart_i = c.vstart; d->vlmax_i = Vlmax(c);
    d->vta_i = c.vta; d->vma_i = c.vma; d->vm_i = c.vm;
    d->vs2_i = c.vs2; d->vs1_i = c.vs1; d->vd_i = c.vd; d->nreg_i = c.nreg;
    d->scalar_i = frs ? frs : c.scalar; d->imm_i = c.imm;
    d->vxrm_i = c.vxrm; d->frm_i = frm;
    d->start_i = 1;
    Tick();
    d->start_i = 0;
    // Inputs may change while busy (the core's EX does not);
    // scramble them to prove the unit latched everything.
    d->op_i = 0; d->vl_i = 0; d->vs2_i = 31; d->scalar_i = 0xdead;
    int n = 1;
    while (!d->done_o) {
      Tick();
      if (++n > 100000) { std::printf("TIMEOUT op %d\n", c.op); ++failures; return n; }
    }
    for (int k = 0; k < ack_delay; ++k) {
      Tick();
      CHECK(d->done_o && d->busy_o);
      CHECK(!d->we_o);
    }
    d->ack_i = 1;
    d->eval();
    return n;
  }
  void Ack() {
    Tick();
    d->ack_i = 0;
    CHECK(!d->busy_o);
  }
};

const char* kOpName[] = {
  "add","sub","rsub","and","or","xor","sll","srl","sra","mv","mv.s.x","mv.x.s",
  "min","minu","max","maxu","mul","mulh","mulhu","mulhsu","macc","madd","nmsac",
  "nmsub","div","divu","rem","remu","adc","madc","sbc","msbc","merge","cmpeq",
  "cmpne","cmpltu","cmplt","cmpleu","cmple","cmpgtu","cmpgt","mlog","red","ext",
  "sadd","saddu","ssub","ssubu","aadd","aaddu","asub","asubu","smul","ssrl","ssra",
  "wadd","waddw","waddu","wadduw","wsub","wsubw","wsubu","wsubuw","wmul","wmulu",
  "wmulsu","wmacc","wmaccu","wmaccsu","wmaccus","nsrl","nsra","nclip","nclipu",
  "slideup","slidedown","slide1up","slide1down","gather","gatherei16",
  "compress","msbit","iota","id","cpop","first","mvr","wred"};

bool IsMaskDest(int op) {
  return op == MADC || op == MSBC || (op >= CMPEQ && op <= CMPGT) || op == MLOG || op == MSBIT;
}

// Pick a random legal configuration for op; returns false if
// the op has no legal configuration at this SEW/LMUL draw.
bool Configure(Cfg& c, std::mt19937_64& rng) {
  const int op = c.op;
  c.sewc = rng() % 4;
  c.lmulc = static_cast<int>(rng() % 7) - 3;
  const int sew = 8 << c.sewc;
  // Fractional LMUL needs SEW <= LMUL*ELEN.
  if (c.lmulc < 0 && sew > (64 >> -c.lmulc)) c.lmulc = 0;
  const bool wide = (op >= WADD && op <= WMACCUS) || op == WRED;
  const bool narrow = (op >= NSRL && op <= NCLIPU);
  if ((wide || narrow) && (c.sewc == 3)) c.sewc = static_cast<int>(rng() % 3);
  if ((wide || narrow) && c.lmulc == 3) c.lmulc = 2;
  if (op == EXT) {
    const int ratio_log = 1 + static_cast<int>(rng() % 3);  // 2,4,8
    if (c.sewc < ratio_log) c.sewc = ratio_log;
    c.imm = static_cast<uint64_t>(((4 - ratio_log) << 1) | (rng() & 1));
    // source EMUL = LMUL/ratio >= 1/8 and SEW/ratio <= EMUL*64.
    if (c.lmulc - ratio_log < -3) c.lmulc = ratio_log - 3;
    const int ssew = (8 << c.sewc) >> ratio_log;
    while (c.lmulc - ratio_log < 0 && ssew > (64 >> (ratio_log - c.lmulc))) ++c.lmulc;
  }
  if (op == GATHEREI16) {
    // vs1 EMUL = 16/SEW*LMUL must be within [1/8, 8].
    const int e = 1 - c.sewc + c.lmulc;
    if (e > 3) c.lmulc -= (e - 3);
    if (1 - c.sewc + c.lmulc < -3) c.lmulc = c.sewc - 4;
  }
  const int vlmax = Vlmax(c);
  if (vlmax <= 0) return false;
  // vl: mostly full/near-full, sometimes small or zero.
  switch (rng() % 6) {
    case 0: c.vl = 0; break;
    case 1: c.vl = 1 + rng() % 4; break;
    case 2: c.vl = vlmax; break;
    default: c.vl = rng() % (vlmax + 1); break;
  }
  if (c.vl > static_cast<uint64_t>(vlmax)) c.vl = vlmax;
  const bool vstart_zero = op == RED || op == WRED || op == COMPRESS || op == IOTA ||
                           op == MSBIT || op == CPOP || op == FIRST || op == MVSX;
  c.vstart = (!vstart_zero && rng() % 4 == 0) ? rng() % (vlmax + 2) : 0;
  c.vm = (rng() % 3) != 0;
  if (op == MLOG || op == COMPRESS || op == MVR || op == ADC || op == SBC || op == MERGE) {
    c.vm = (op == ADC || op == SBC || op == MERGE) ? false : true;
  }
  if (op == MADC || op == MSBC) c.vm = rng() & 1;  // vm=0: carry-in from v0
  c.vta = rng() & 1;
  c.vma = rng() & 1;
  c.vxrm = rng() % 4;
  c.scalar = rng();
  if (rng() % 4 == 0) c.scalar = rng() % 70;  // small offsets / indices
  c.imm = (op == MLOG || op == RED || op == EXT || op == MSBIT || op == WRED) ? c.imm
          : static_cast<uint64_t>(static_cast<int64_t>(static_cast<int>(rng() % 32) - 16));
  if (op == MLOG || op == RED) c.imm = rng() % 8;
  if (op == MSBIT) c.imm = 1 + rng() % 3;
  if (op == WRED) c.imm = rng() & 1;

  // Register groups (aligned to their EMUL).
  auto regs_of = [&](int emul_log) { return emul_log <= 0 ? 1 : (1 << emul_log); };
  auto pick = [&](int emul_log) {
    const int n = regs_of(emul_log);
    return static_cast<int>((rng() % (32 / n)) * n);
  };
  int d_log = c.lmulc, s2_log = c.lmulc, s1_log = c.lmulc;
  if (wide) d_log = c.lmulc + 1;
  if (op == WADDW || op == WADDUW || op == WSUBW || op == WSUBUW) s2_log = c.lmulc + 1;
  if (narrow) s2_log = c.lmulc + 1;
  if (op == EXT) s2_log = c.lmulc - (4 - static_cast<int>((c.imm >> 1) & 3));
  if (op == GATHEREI16) s1_log = 1 - c.sewc + c.lmulc;
  const bool mdest = IsMaskDest(op);
  const bool msrc2 = op == MLOG || op == MSBIT || op == IOTA || op == CPOP || op == FIRST;
  if (mdest || op == RED || op == WRED) d_log = 0;
  if (msrc2) s2_log = 0;
  if (op == MLOG || op == COMPRESS) s1_log = 0;
  if (op == RED || op == WRED) s1_log = 0;
  if (op == MVR) {
    const int l = static_cast<int>(rng() % 4);
    c.nreg = 1 << l;
    d_log = s2_log = l;
  }
  auto overlap = [&](int a, int al, int b, int bl) {
    const int an = regs_of(al), bn = regs_of(bl);
    return a < b + bn && b < a + an;
  };
  for (int tries = 0; tries < 200; ++tries) {
    c.vs2 = pick(s2_log);
    c.vs1 = pick(s1_log);
    c.vd = pick(d_log);
    // Allowed-overlap cases, exercised deliberately.
    const int k = static_cast<int>(rng() % 8);
    const bool same_eew = !wide && !narrow && op != EXT && !mdest && !msrc2 &&
        op != RED && op != WRED && op != COMPRESS && op != GATHER && op != GATHEREI16 &&
        op != SLIDEUP && op != SLIDE1UP && op != IOTA && op != MVR;
    if (k == 0 && same_eew) c.vd = c.vs2;
    if (k == 1 && same_eew && op != SLIDEDOWN && op != SLIDE1DOWN) c.vd = c.vs1;
    if (k == 2 && (narrow || (mdest && op != MSBIT))) c.vd = c.vs2;  // low part
    if (k == 3 && wide && s2_log == c.lmulc && c.lmulc >= 0) {
      c.vs2 = c.vd + regs_of(c.lmulc);  // high half of the wide dest
    }
    if (k == 4 && mdest && op != MSBIT && c.form == VV && s1_log == c.lmulc) c.vd = c.vs1;
    // Reject illegal overlaps (anything else).
    bool bad = false;
    const bool uses_vs1 = (c.form == VV) || op == MLOG || op == COMPRESS || op == RED || op == WRED;
    auto ok_overlap = [&](int src, int sl, bool is_vs1) {
      if (!overlap(c.vd, d_log, src, sl)) return true;
      if (op == RED || op == WRED || op == MVR) return true;  // scalar dest / whole copy
      if (c.vd == src && d_log == sl && same_eew) return true;
      if (op == MLOG) return true;
      if (mdest && op != MSBIT && c.vd == src) return true;  // lowest register
      if (narrow && !is_vs1 && c.vd == src) return true;
      if (wide && !is_vs1 && sl == c.lmulc && c.lmulc >= 0 && src == c.vd + regs_of(c.lmulc)) return true;
      if (wide && is_vs1 && sl == c.lmulc && c.lmulc >= 0 && src == c.vd + regs_of(c.lmulc)) return true;
      return false;
    };
    if (!ok_overlap(c.vs2, s2_log, false)) bad = true;
    if (uses_vs1 && !ok_overlap(c.vs1, s1_log, true)) bad = true;
    if (op == SLIDEDOWN || op == SLIDE1DOWN) {
      // vd may overlap vs2 only when identical (same EEW).
      if (overlap(c.vd, d_log, c.vs2, s2_log) && c.vd != c.vs2) bad = true;
    }
    // Masked ops may not write v0 (mask-dest/reductions may).
    if (!c.vm && !mdest && op != RED && op != WRED && c.vd == 0) bad = true;
    if ((op == ADC || op == SBC || op == MERGE) && c.vd == 0) bad = true;
    if (!bad) return true;
  }
  return false;
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Dut dut;
  dut.d = new Vmuserisc_vec_harness;
  auto* d = dut.d;
  // Seed: VEC_TB_SEED env (decimal or 0x hex), default 0x5eed8a.
  const uint64_t seed = getenv("VEC_TB_SEED")
      ? std::strtoull(getenv("VEC_TB_SEED"), nullptr, 0) : 0x5eed8aull;
  std::mt19937_64 rng(seed);
  long trials = 0;
  long op_trials[98] = {};
  long op_cycles[98] = {};
  long op_elems[98] = {};
  const long kPerOp = argc > 1 && std::atol(argv[1]) > 0 ? std::atol(argv[1]) : 260;

  d->rst_ni = 0; d->clk_i = 0; d->start_i = 0; d->ack_i = 0; d->kill_i = 0;
  d->tb_we_i = 0; d->tb_re_i = 0;
  dut.Tick(); dut.Tick();
  d->rst_ni = 1;
  dut.Tick();

  // ---- Randomized integer classes vs the golden model ----
  std::vector<int> ops;
  for (int op = 0; op <= WRED; ++op) {
    if (op == MVXS) { ops.push_back(op); continue; }
    ops.push_back(op);
  }
  VRF st;
  for (auto& r : st.b) for (auto& x : r) x = static_cast<uint8_t>(rng());
  for (long rep = 0; rep < kPerOp; ++rep) {
    for (int op : ops) {
      Cfg c;
      c.op = op;
      // Forms per class.
      if (op == MVSX || op == SLIDE1UP || op == SLIDE1DOWN) c.form = VX;
      else if (op == MVXS || op == CPOP || op == FIRST || op == ID || op == IOTA ||
               op == MSBIT || op == MLOG || op == RED || op == WRED || op == EXT ||
               op == COMPRESS || op == GATHEREI16 || op == MVR ||
               (op >= MUL && op <= NMSUB) || op == RSUB || op == SMUL ||
               (op >= WMUL && op <= WMACCUS) || op == MSBC || op == SBC)
        c.form = (op == RSUB) ? (rng() % 2 ? VX : VI)
                 : ((op >= MUL && op <= NMSUB) || op == SMUL || (op >= WMUL && op <= WMACCUS) ||
                    op == MSBC || op == SBC) ? (rng() % 2 ? VV : VX) : VV;
      else c.form = static_cast<int>(rng() % 3);
      if (op == WMACCUS) c.form = VX;
      if (!Configure(c, rng)) continue;
      // Fresh random state with structured corner values.
      for (int r = 0; r < 32; ++r)
        for (int k = 0; k < 64; ++k) st.b[r][k] = static_cast<uint8_t>(rng());
      if (rng() % 3 == 0) {
        const int sew = 8 << c.sewc, eb = sew / 8;
        const uint64_t corner[] = {0, 1, Ones(sew), 1ull << (sew - 1), Ones(sew - 1), 2, Ones(sew) - 1};
        for (int r = 0; r < 32; ++r)
          for (int i = 0; i < 64 / eb; ++i)
            if (rng() % 2) Put(st, r, i, eb, corner[rng() % 7]);
      }
      if (rng() % 4 == 0) {  // sparse/dense masks
        const uint8_t fill = rng() % 2 ? 0x00 : 0xff;
        for (int k = 0; k < 64; ++k) if (rng() % 8) st.b[0][k] = fill;
      }
      const Out want = Golden(c, st);
      dut.Load(st);
      const int n = dut.Run(c, 0, 0, static_cast<int>(rng() % 3 == 0 ? rng() % 3 : 0));
      const uint64_t scal = d->scalar_o;
      const bool sat = d->sat_o;
      dut.Ack();
      const VRF got = dut.Dump();
      ++trials;
      ++op_trials[op];
      op_cycles[op] += n;
      op_elems[op] += static_cast<long>(c.vl);
      bool ok = std::memcmp(&got, &want.f, sizeof(VRF)) == 0;
      if (op == MVXS || op == CPOP || op == FIRST) ok = ok && scal == want.scalar;
      if (op >= SADD && op <= SSUBU) ok = ok && sat == want.sat;
      if ((op == SMUL) || (op == NCLIP) || (op == NCLIPU)) ok = ok && sat == want.sat;
      CHECK(ok);
      if (!ok && failures <= 12) {
        std::printf("MISMATCH %s form=%d sew=%d lmul=%d vl=%llu vstart=%llu vm=%d vs2=%d vs1=%d vd=%d "
                    "scalar=0x%llx imm=0x%llx vxrm=%d nreg=%d\n",
                    kOpName[op], c.form, 8 << c.sewc, c.lmulc, (unsigned long long)c.vl,
                    (unsigned long long)c.vstart, c.vm, c.vs2, c.vs1, c.vd,
                    (unsigned long long)c.scalar, (unsigned long long)c.imm, c.vxrm, c.nreg);
        std::printf("  scalar got=0x%llx want=0x%llx sat got=%d want=%d\n",
                    (unsigned long long)scal, (unsigned long long)want.scalar, sat, want.sat);
        int shown = 0;
        for (int r = 0; r < 32 && shown < 6; ++r)
          for (int k = 0; k < 64 && shown < 6; k += 8) {
            uint64_t g, w;
            std::memcpy(&g, &got.b[r][k], 8);
            std::memcpy(&w, &want.f.b[r][k], 8);
            if (g != w) {
              std::printf("  v%d word%d got=%016llx want=%016llx\n", r, k / 8,
                          (unsigned long long)g, (unsigned long long)w);
              ++shown;
            }
          }
      }
    }
  }

  // ---- Directed: kill mid-operation, then a clean op ----
  {
    Cfg c;
    c.op = DIV; c.form = VV; c.sewc = 3; c.lmulc = 3; c.vl = 64; c.vs2 = 8; c.vs1 = 16; c.vd = 24;
    dut.Load(st);
    d->op_i = c.op; d->form_i = c.form; d->sew_i = c.sewc; d->vl_i = c.vl; d->vstart_i = 0;
    d->vlmax_i = 64; d->vm_i = 1; d->vs2_i = 8; d->vs1_i = 16; d->vd_i = 24; d->nreg_i = 1;
    d->start_i = 1; dut.Tick(); d->start_i = 0;
    for (int k = 0; k < 50; ++k) dut.Tick();
    CHECK(d->busy_o && !d->done_o);
    d->kill_i = 1; dut.Tick(); d->kill_i = 0;
    CHECK(!d->busy_o);
    c.op = ADD;
    const Out want = Golden(c, st);
    dut.Load(st);
    dut.Run(c);
    dut.Ack();
    const VRF after = dut.Dump();
    CHECK(std::memcmp(&after, &want.f, sizeof(VRF)) == 0);
  }

  // ---- FP vector directed checks (stage 9, issue #29) ----
  // Host IEEE float/double is the oracle at RNE for value
  // checks; special values use explicit expected constants.
  {
    auto fbits = [](float f) { uint32_t u; std::memcpy(&u, &f, 4); return u; };
    auto dbits = [](double f) { uint64_t u; std::memcpy(&u, &f, 8); return u; };
    auto asf = [](uint32_t u) { float f; std::memcpy(&f, &u, 4); return f; };
    auto asd = [](uint64_t u) { double f; std::memcpy(&f, &u, 8); return f; };
    int flast = 0;
    // Registers: vs2 = v8, vs1 = v16, vd = v24, mask v0.
    struct G { uint64_t w[64] = {}; };
    auto SetEl = [](G& g, int i, int sew, uint64_t v) {
      const int base = i * sew, word = base / 64, o = base % 64;
      const uint64_t mm = Ones(sew);
      g.w[word] = (g.w[word] & ~(mm << o)) | ((v & mm) << o);
    };
    auto GetEl = [](const G& g, int i, int sew) {
      const int base = i * sew;
      return (g.w[base / 64] >> (base % 64)) & Ones(sew);
    };
    auto frun = [&](int vop, int form, int sew_code, uint64_t vl, uint64_t vstart, bool vm,
                    uint64_t imm, uint64_t scalar, const G& vs2, const G& vs1, const G& old,
                    const G& maskg, int frm = 0) {
      VRF s;
      std::memset(&s, 0, sizeof(s));
      for (int r = 0; r < 8; ++r) {
        std::memcpy(s.b[8 + r], &vs2.w[r * 8], 64);
        std::memcpy(s.b[16 + r], &vs1.w[r * 8], 64);
        std::memcpy(s.b[24 + r], &old.w[r * 8], 64);
      }
      std::memcpy(s.b[0], &maskg.w[0], 64);
      dut.Load(s);
      Cfg c;
      c.op = vop; c.form = form; c.sewc = sew_code; c.lmulc = 0; c.vl = vl; c.vstart = vstart;
      c.vm = vm; c.imm = imm; c.scalar = scalar; c.vs2 = 8; c.vs1 = 16; c.vd = 24;
      dut.Run(c, 0, frm);
      flast = d->fflags_o;
      dut.Ack();
      const VRF o = dut.Dump();
      G g;
      for (int r = 0; r < 8; ++r) std::memcpy(&g.w[r * 8], o.b[24 + r], 64);
      return g;
    };
    const int S32 = 2, D64 = 3;
    for (int fop = 0; fop <= 3; ++fop) {
      G a, b, old, mk;
      const float av[8] = {1.5f, -2.25f, 0.5f, 100.0f, -0.0f, 3.25f, 1e10f, 7.0f};
      const float bv[8] = {0.25f, 2.0f, -4.0f, 0.5f, 1.0f, -3.25f, 3.0f, 0.0f};
      for (int i = 0; i < 8; ++i) {
        SetEl(a, i, 32, fbits(av[i])); SetEl(b, i, 32, fbits(bv[i]));
        SetEl(old, i, 32, 0xeeee0000u + i);
      }
      mk.w[0] = 0b11010110;
      G got = frun(FBIN, VV, S32, 7, 1, false, fop, 0, a, b, old, mk);
      for (int i = 0; i < 8; ++i) {
        const bool act = i >= 1 && i < 7 && ((mk.w[0] >> i) & 1);
        float want = 0;
        if (fop == 0) want = av[i] + bv[i];
        if (fop == 1) want = av[i] - bv[i];
        if (fop == 2) want = av[i] * bv[i];
        if (fop == 3) want = av[i] / bv[i];
        CHECK(GetEl(got, i, 32) == (act ? fbits(want) : 0xeeee0000u + i));
      }
    }
    // Kill while the shared FPU is in the middle of a vfdiv
    // element, then rerun: the FPU and the FP sub-step state
    // must restart cleanly.
    for (int when = 3; when <= 40; when += 37) {
      G a, b, old, mk;
      const float av[4] = {1.5f, -2.25f, 9.0f, 100.0f};
      const float bv[4] = {0.25f, 3.0f, -4.0f, 7.0f};
      for (int i = 0; i < 4; ++i) {
        SetEl(a, i, 32, fbits(av[i])); SetEl(b, i, 32, fbits(bv[i]));
      }
      VRF s;
      std::memset(&s, 0, sizeof(s));
      for (int r = 0; r < 8; ++r) {
        std::memcpy(s.b[8 + r], &a.w[r * 8], 64);
        std::memcpy(s.b[16 + r], &b.w[r * 8], 64);
      }
      dut.Load(s);
      d->op_i = FBIN; d->form_i = VV; d->sew_i = S32; d->vl_i = 4; d->vstart_i = 0;
      d->vlmax_i = 16; d->vm_i = 1; d->vs2_i = 8; d->vs1_i = 16; d->vd_i = 24;
      d->nreg_i = 1; d->imm_i = 3; d->frm_i = 0;
      d->start_i = 1; dut.Tick(); d->start_i = 0;
      for (int k = 0; k < when; ++k) dut.Tick();
      CHECK(d->busy_o && !d->done_o);
      d->kill_i = 1; dut.Tick(); d->kill_i = 0;
      CHECK(!d->busy_o);
      G got = frun(FBIN, VV, S32, 4, 0, true, 3, 0, a, b, old, mk);
      for (int i = 0; i < 4; ++i) CHECK(GetEl(got, i, 32) == fbits(av[i] / bv[i]));
      CHECK(flast == 0x01);  // NX only (1.5/0.25 etc. include inexact quotients)
    }
    {
      G a, b, old, mk;
      const double av[4] = {1.0, 0.0, -5.0, 2.5};
      const double bv[4] = {0.0, 0.0, 2.0, 0.5};
      for (int i = 0; i < 4; ++i) { SetEl(a, i, 64, dbits(av[i])); SetEl(b, i, 64, dbits(bv[i])); }
      mk.w[0] = 0xf;
      G got = frun(FBIN, VV, D64, 4, 0, true, 3, 0, a, b, old, mk);
      CHECK(GetEl(got, 0, 64) == 0x7ff0000000000000ull);
      CHECK(GetEl(got, 1, 64) == 0x7ff8000000000000ull);
      CHECK(GetEl(got, 2, 64) == dbits(-2.5));
      CHECK(GetEl(got, 3, 64) == dbits(5.0));
      CHECK((flast & 0x10) != 0);
      CHECK((flast & 0x08) != 0);
    }
    {
      G a, b, old, mk;
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, fbits(0.5f * i));
      mk.w[0] = 0xff;
      G got = frun(FBIN, VX, S32, 8, 0, true, 2, (0xffffffffull << 32) | fbits(4.0f), a, b, old, mk);
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == fbits(0.5f * i * 4.0f));
      // vfrsub.vf (imm[7] swaps): rs - vs2
      got = frun(FBIN, VX, S32, 8, 0, true, (1 << 7) | 1, (0xffffffffull << 32) | fbits(4.0f), a, b, old, mk);
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == fbits(4.0f - 0.5f * i));
    }
    {
      G a, b, cc, mk;
      for (int i = 0; i < 8; ++i) {
        SetEl(a, i, 32, fbits(1.0f + 0.25f * i));
        SetEl(b, i, 32, fbits(2.0f - 0.5f * i));
        SetEl(cc, i, 32, fbits(0.125f * i));
      }
      mk.w[0] = 0xff;
      G got = frun(FMACC, VV, S32, 8, 0, true, 0, 0, a, b, cc, mk);
      for (int i = 0; i < 8; ++i)
        CHECK(GetEl(got, i, 32) == fbits(std::fma(asf(fbits(1.0f + 0.25f * i)),
                                                 asf(fbits(2.0f - 0.5f * i)),
                                                 asf(fbits(0.125f * i)))));
      // vfmadd (imm[7]): vd = vs1*vd + vs2.
      got = frun(FMACC, VV, S32, 8, 0, true, 1 << 7, 0, a, b, cc, mk);
      for (int i = 0; i < 8; ++i)
        CHECK(GetEl(got, i, 32) == fbits(std::fma(asf(fbits(2.0f - 0.5f * i)),
                                                 asf(fbits(0.125f * i)),
                                                 asf(fbits(1.0f + 0.25f * i)))));
      G a2, c2;
      for (int i = 0; i < 4; ++i) { SetEl(a2, i, 64, dbits(1.5 + i)); SetEl(c2, i, 64, dbits(10.0 - i)); }
      got = frun(FMACC, VX, D64, 4, 0, true, (3 << 5), dbits(0.5), a2, b, c2, mk);
      for (int i = 0; i < 4; ++i)
        CHECK(GetEl(got, i, 64) == dbits(std::fma(-asd(dbits(1.5 + i)), 0.5, asd(dbits(10.0 - i)))));
      got = frun(FMACC, VX, D64, 4, 0, true, (1 << 5), dbits(0.5), a2, b, c2, mk);
      for (int i = 0; i < 4; ++i)
        CHECK(GetEl(got, i, 64) == dbits(std::fma(-asd(dbits(1.5 + i)), 0.5, -asd(dbits(10.0 - i)))));
      got = frun(FMACC, VX, D64, 4, 0, true, (2 << 5), dbits(0.5), a2, b, c2, mk);
      for (int i = 0; i < 4; ++i)
        CHECK(GetEl(got, i, 64) == dbits(std::fma(asd(dbits(1.5 + i)), 0.5, -asd(dbits(10.0 - i)))));
    }
    {
      G a, b, old, mk;
      const float av[8] = {1, 2, 3, 4, 5, 6, 7, 8};
      for (int i = 0; i < 8; ++i) { SetEl(a, i, 32, fbits(av[i])); SetEl(b, i, 32, fbits(4.5f)); }
      SetEl(a, 6, 32, 0x7fc00000u);
      mk.w[0] = 0xff;
      G got = frun(FCMP, VV, S32, 8, 0, true, 2, 0, a, b, old, mk);
      CHECK((got.w[0] & 0xff) == 0b00001111);
      CHECK((flast & 0x10) != 0);
      got = frun(FCMP, VX, S32, 8, 0, true, 0, (0xffffffffull << 32) | fbits(4.0f), a, b, old, mk);
      CHECK((got.w[0] & 0xff) == 0b00001000);
      CHECK((flast & 0x10) == 0);
      // vmfne / vmfgt (swap) / vmfge, masked: bit 1 keeps old.
      mk.w[0] = 0xfd;
      old.w[0] = 0x2;
      got = frun(FCMP, VX, S32, 8, 0, false, 1, (0xffffffffull << 32) | fbits(4.0f), a, b, old, mk);
      CHECK((got.w[0] & 0xff) == 0b11110111);
      got = frun(FCMP, VX, S32, 8, 0, false, 4, (0xffffffffull << 32) | fbits(4.0f), a, b, old, mk);
      CHECK((got.w[0] & 0xff) == 0b10110010);
      got = frun(FCMP, VX, S32, 8, 0, false, 5, (0xffffffffull << 32) | fbits(4.0f), a, b, old, mk);
      CHECK((got.w[0] & 0xff) == 0b10111010);
    }
    {
      G a, b, old, mk;
      const float av[8] = {4.0f, 2.0f, -1.0f, 0.0f, 1.0f / 0.0f, -0.0f, 1e-42f, 9.0f};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, fbits(av[i]));
      mk.w[0] = 0xff;
      G got = frun(FUNARY, VV, S32, 8, 0, true, 0, 0, a, b, old, mk);
      CHECK(GetEl(got, 0, 32) == fbits(2.0f));
      CHECK(GetEl(got, 1, 32) == fbits(std::sqrt(2.0f)));
      CHECK(GetEl(got, 2, 32) == 0x7fc00000u);
      CHECK((flast & 0x10) != 0);
      got = frun(FUNARY, VV, S32, 8, 0, true, 1, 0, a, b, old, mk);
      const uint32_t cls[8] = {1u << 6, 1u << 6, 1u << 1, 1u << 4, 1u << 7, 1u << 3, 1u << 5, 1u << 6};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == cls[i]);
    }
    {
      G a, b, old, mk;
      const float av[4] = {0.1f, 1.5f, -2.5f, 100.0f};
      const float bv[4] = {0.2f, 0.5f, 2.5f, 0.25f};
      for (int i = 0; i < 4; ++i) { SetEl(a, i, 32, fbits(av[i])); SetEl(b, i, 32, fbits(bv[i])); }
      mk.w[0] = 0xf;
      G got = frun(FBINW, VV, S32, 4, 0, true, 0, 0, a, b, old, mk);
      for (int i = 0; i < 4; ++i)
        CHECK(GetEl(got, i, 64) == dbits(static_cast<double>(av[i]) + static_cast<double>(bv[i])));
      G aw;
      const double ad[4] = {1.25, -0.5, 3.0, 7.5};
      for (int i = 0; i < 4; ++i) SetEl(aw, i, 64, dbits(ad[i]));
      got = frun(FBINW, VV, S32, 4, 0, true, (1 << 7) | 1, 0, aw, b, old, mk);
      for (int i = 0; i < 4; ++i) CHECK(GetEl(got, i, 64) == dbits(ad[i] - static_cast<double>(bv[i])));
      G cc;
      for (int i = 0; i < 4; ++i) SetEl(cc, i, 64, dbits(1.0 * i));
      got = frun(FMACCW, VX, S32, 4, 0, true, 0, (0xffffffffull << 32) | fbits(2.0f), a, b, cc, mk);
      for (int i = 0; i < 4; ++i)
        CHECK(GetEl(got, i, 64) == dbits(std::fma(static_cast<double>(av[i]), 2.0, 1.0 * i)));
      // vfwmacc.vv masked (element 2 off keeps old).
      mk.w[0] = 0xb;
      got = frun(FMACCW, VV, S32, 4, 0, false, 0, 0, a, b, cc, mk);
      for (int i = 0; i < 4; ++i)
        CHECK(GetEl(got, i, 64) == (i == 2 ? dbits(2.0)
              : dbits(std::fma(static_cast<double>(av[i]), static_cast<double>(bv[i]), 1.0 * i))));
    }
    // Every rounding mode reaches the FPU: 1 +/- 2^-24 is a tie
    // at e32 (RNE/RTZ keep 1, RDN/RUP/RMM split by sign).
    {
      G a, b, old, mk;
      SetEl(a, 0, 32, fbits(1.0f)); SetEl(b, 0, 32, 0x33800000u);   // +2^-24
      SetEl(a, 1, 32, fbits(-1.0f)); SetEl(b, 1, 32, 0xb3800000u);  // -2^-24
      const uint32_t want[5][2] = {{0x3f800000u, 0xbf800000u},   // RNE
                                   {0x3f800000u, 0xbf800000u},   // RTZ
                                   {0x3f800000u, 0xbf800001u},   // RDN
                                   {0x3f800001u, 0xbf800000u},   // RUP
                                   {0x3f800001u, 0xbf800001u}};  // RMM
      for (int rm = 0; rm <= 4; ++rm) {
        G got = frun(FBIN, VV, S32, 2, 0, true, 0, 0, a, b, old, mk, rm);
        CHECK(GetEl(got, 0, 32) == want[rm][0]);
        CHECK(GetEl(got, 1, 32) == want[rm][1]);
        CHECK(flast == 0x01);
        // Widening: the same operands are exact in binary64.
        got = frun(FBINW, VV, S32, 2, 0, true, 0, 0, a, b, old, mk, rm);
        CHECK(GetEl(got, 0, 64) == dbits(1.0 + std::ldexp(1.0, -24)));
        CHECK(flast == 0x00);
      }
    }
    // Widening-op fflags include the source-conversion step: an
    // sNaN source raises NV only in its conversion (the operation
    // then sees a quiet NaN); inexact comes from the operation.
    {
      const uint32_t snan = 0x7f800001u;
      const uint64_t dnan = 0x7ff8000000000000ull;
      G a, b, old, mk;
      SetEl(a, 0, 32, snan); SetEl(b, 0, 32, fbits(1.0f));
      SetEl(a, 1, 32, fbits(1.0f)); SetEl(b, 1, 32, 0x33800000u);
      G got = frun(FBINW, VV, S32, 2, 0, true, 0, 0, a, b, old, mk);   // vfwadd.vv
      CHECK(GetEl(got, 0, 64) == dnan);
      CHECK(GetEl(got, 1, 64) == dbits(1.0 + std::ldexp(1.0, -24)));
      CHECK(flast == 0x10);
      G aw, bs;
      SetEl(aw, 0, 64, dbits(2.0)); SetEl(bs, 0, 32, snan);
      got = frun(FBINW, VV, S32, 1, 0, true, 1 << 7, 0, aw, bs, old, mk);  // vfwadd.wv
      CHECK(GetEl(got, 0, 64) == dnan);
      CHECK(flast == 0x10);
      // vfwmacc.vv: element 0 inexact in the FMA, element 1 NV
      // from converting vs2.
      G ma, mb, cc;
      SetEl(ma, 0, 32, 0x3f800001u); SetEl(mb, 0, 32, 0x3f800001u);
      SetEl(cc, 0, 64, dbits(std::ldexp(1.0, -60)));
      SetEl(ma, 1, 32, snan); SetEl(mb, 1, 32, fbits(1.0f));
      SetEl(cc, 1, 64, dbits(0.0));
      got = frun(FMACCW, VV, S32, 2, 0, true, 0, 0, ma, mb, cc, mk);
      CHECK(GetEl(got, 0, 64) == 0x3ff0000040000040ull);
      CHECK(GetEl(got, 1, 64) == dnan);
      CHECK(flast == 0x11);
      got = frun(FMACCW, VV, S32, 1, 0, true, 0, 0, ma, mb, cc, mk);
      CHECK(flast == 0x01);
      // vfwcvt.f.f.v (single-step widening conversion).
      G ca;
      SetEl(ca, 0, 32, snan); SetEl(ca, 1, 32, fbits(1.5f));
      got = frun(FCVT, VV, S32, 2, 0, true, 12, 0, ca, b, old, mk);
      CHECK(GetEl(got, 0, 64) == dnan);
      CHECK(GetEl(got, 1, 64) == dbits(1.5));
      CHECK(flast == 0x10);
      // vfwredusum: NV from converting an element.
      G ra, seed;
      SetEl(ra, 0, 32, fbits(1.0f)); SetEl(ra, 1, 32, snan);
      SetEl(seed, 0, 64, dbits(0.5));
      got = frun(FWRED, VV, S32, 2, 0, true, 0, 0, ra, seed, old, mk);
      CHECK(GetEl(got, 0, 64) == dnan);
      CHECK(flast == 0x10);
    }
    {
      G a, b, old, mk;
      const uint32_t iv[8] = {0, 1, 7, 100000, 0x80000000u, 3, 17, 0xfffffff0u};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, iv[i]);
      mk.w[0] = 0xff;
      G got = frun(FCVT, VV, S32, 8, 0, true, 2, 0, a, b, old, mk);
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == fbits(static_cast<float>(iv[i])));
      const float fv[8] = {1.5f, -1.5f, 2.5f, -2.5f, 0.5f, 100.75f, -0.25f, 3.5f};
      G fa;
      for (int i = 0; i < 8; ++i) SetEl(fa, i, 32, fbits(fv[i]));
      got = frun(FCVT, VV, S32, 8, 0, true, 1, 0, fa, b, old, mk);
      const int32_t xwant[8] = {2, -2, 2, -2, 0, 101, 0, 4};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == static_cast<uint32_t>(xwant[i]));
      got = frun(FCVT, VV, S32, 8, 0, true, 7, 0, fa, b, old, mk);
      const int32_t zwant[8] = {1, -1, 2, -2, 0, 100, 0, 3};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == static_cast<uint32_t>(zwant[i]));
      G da;
      const double dv[4] = {0.1, -3.75, 1e300, 2.5};
      for (int i = 0; i < 4; ++i) SetEl(da, i, 64, dbits(dv[i]));
      got = frun(FCVT, VV, S32, 4, 0, true, 20, 0, da, b, old, mk);
      for (int i = 0; i < 4; ++i) CHECK(GetEl(got, i, 32) == fbits(static_cast<float>(dv[i])));
      got = frun(FCVT, VV, S32, 4, 0, true, 17, 0, da, b, old, mk);
      const int32_t nwant[4] = {0, -4, INT32_MAX, 2};
      for (int i = 0; i < 4; ++i) CHECK(GetEl(got, i, 32) == static_cast<uint32_t>(nwant[i]));
      // vfwcvt.f.f.v (widen) and vfwcvt.f.x.v.
      got = frun(FCVT, VV, S32, 4, 0, true, 12, 0, fa, b, old, mk);
      for (int i = 0; i < 4; ++i) CHECK(GetEl(got, i, 64) == dbits(static_cast<double>(fv[i])));
      got = frun(FCVT, VV, S32, 4, 0, true, 11, 0, a, b, old, mk);
      for (int i = 0; i < 4; ++i) CHECK(GetEl(got, i, 64) == dbits(static_cast<double>(static_cast<int32_t>(iv[i]))));
    }
    {
      G a, seed, old, mk;
      const float av[8] = {1, 2, 4, 8, 16, 32, 64, 128};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, fbits(av[i]));
      SetEl(seed, 0, 32, fbits(0.5f));
      mk.w[0] = 0b01111101;
      G got = frun(FRED, VV, S32, 8, 0, false, 0, 0, a, seed, old, mk);
      CHECK(GetEl(got, 0, 32) == fbits(0.5f + 1 + 4 + 8 + 16 + 32 + 64));
      got = frun(FRED, VV, S32, 8, 0, false, 3, 0, a, seed, old, mk);
      CHECK(GetEl(got, 0, 32) == fbits(64.0f));
      got = frun(FRED, VV, S32, 8, 0, false, 2, 0, a, seed, old, mk);
      CHECK(GetEl(got, 0, 32) == fbits(0.5f));
      G dseed;
      SetEl(dseed, 0, 64, dbits(0.25));
      got = frun(FWRED, VV, S32, 8, 0, true, 0, 0, a, dseed, old, mk);
      CHECK(GetEl(got, 0, 64) == dbits(255.25));
      // vl = 0: no write.
      old.w[0] = 0x1234;
      got = frun(FRED, VV, S32, 0, 0, true, 0, 0, a, seed, old, mk);
      CHECK(got.w[0] == 0x1234);
    }
    {
      G a, b, old, mk;
      const uint32_t in[8] = {0x3f800000, 0x40000000, 0x00000001, 0x7f800000,
                              0x00000000, 0x80000000, 0x7fc00000, 0xbf800000};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, in[i]);
      mk.w[0] = 0xff;
      G got = frun(FUNARY, VV, S32, 8, 0, true, 3, 0, a, b, old, mk);
      const uint32_t recw[8] = {0x3f7f0000, 0x3eff0000, 0x7f800000, 0x00000000,
                                0x7f800000, 0xff800000, 0x7fc00000, 0xbf7f0000};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == recw[i]);
      CHECK((flast & 0x0d) == 0x0d);
      got = frun(FUNARY, VV, S32, 8, 0, true, 2, 0, a, b, old, mk);
      const uint32_t rsqw[8] = {0x3f7f0000, 0x3f340000, 0x64b40000, 0x00000000,
                                0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == rsqw[i]);
      CHECK((flast & 0x18) == 0x18);
      G da;
      const double dv[4] = {1.0 + 0x1p-30, 1.5, 1e300, -1e300};
      for (int i = 0; i < 4; ++i) SetEl(da, i, 64, dbits(dv[i]));
      got = frun(FCVT, VV, S32, 4, 0, true, 21, 0, da, b, old, mk);
      CHECK(GetEl(got, 0, 32) == 0x3f800001u);
      CHECK(GetEl(got, 1, 32) == fbits(1.5f));
      CHECK(GetEl(got, 2, 32) == 0x7f7fffffu);
      CHECK(GetEl(got, 3, 32) == 0xff7fffffu);
    }
    {
      G a, b, old, mk;
      SetEl(a, 0, 32, 0x80000000u);
      frun(FMVFS, VV, S32, 4, 0, true, 0, 0, a, b, old, mk);
      // scalar_o was sampled before Ack inside frun; rerun to read it.
      VRF s; std::memset(&s, 0, sizeof(s)); s.b[8][3] = 0x80;
      dut.Load(s);
      Cfg c; c.op = FMVFS; c.sewc = S32; c.vl = 4; c.vs2 = 8;
      dut.Run(c);
      CHECK(d->scalar_o == 0xffffffff80000000ull);
      dut.Ack();
      c.sewc = D64; dut.Load(s); dut.Run(c);
      CHECK(d->scalar_o == 0x0000000080000000ull);
      dut.Ack();
    }
  }

  // ---- Cycle-count report (documented in docs/CORE.md) ----
  {
    struct P { int op, form, sewc, lmulc; uint64_t vl; const char* name; };
    const P probes[] = {
      {ADD, VV, 0, 3, 512, "vadd.vv e8 m8 vl=512"},
      {ADD, VV, 3, 0, 8, "vadd.vv e64 m1 vl=8"},
      {MUL, VV, 0, 0, 64, "vmul.vv e8 m1 vl=64"},
      {MUL, VV, 3, 0, 8, "vmul.vv e64 m1 vl=8"},
      {DIV, VV, 0, 0, 64, "vdiv.vv e8 m1 vl=64"},
      {DIV, VV, 3, 0, 8, "vdiv.vv e64 m1 vl=8"},
      {CMPLT, VV, 0, 3, 512, "vmslt.vv e8 m8 vl=512"},
      {RED, VV, 2, 0, 16, "vredsum.vs e32 m1 vl=16"},
      {GATHER, VV, 2, 0, 16, "vrgather.vv e32 m1 vl=16"},
      {MVR, VV, 0, 0, 0, "vmv8r.v"},
      {MVXS, VV, 3, 0, 1, "vmv.x.s"},
    };
    for (const P& p : probes) {
      Cfg c; c.op = p.op; c.form = p.form; c.sewc = p.sewc; c.lmulc = p.lmulc; c.vl = p.vl;
      c.vs2 = 8; c.vs1 = 16; c.vd = 24; c.nreg = 8; c.vm = true;
      if (p.op == MVR) { c.vs2 = 8; c.vd = 16; }
      VRF s; for (auto& r : s.b) for (auto& x : r) x = static_cast<uint8_t>(rng() | 1);
      dut.Load(s);
      const int n = dut.Run(c);
      dut.Ack();
      std::printf("CYCLES %-28s %5d (start..done)\n", p.name, n);
    }
    for (int op = 0; op <= WRED; ++op) {
      if (op_trials[op] == 0) continue;
      std::printf("OPSTAT %-11s trials=%4ld avg_vl=%6.1f avg_cycles=%7.1f\n", kOpName[op],
                  op_trials[op], double(op_elems[op]) / op_trials[op],
                  double(op_cycles[op]) / op_trials[op]);
    }
  }

  d->final();
  VerilatedCov::write(getenv("COV_FILE") ? getenv("COV_FILE") : "cov_vec.dat");
  delete d;
  if (failures == 0) {
    std::printf("VEC TB PASS (%ld checks, %ld random trials, %llu cycles, seed 0x%llx)\n", checks,
                trials, (unsigned long long)dut.cycles, (unsigned long long)seed);
    return 0;
  }
  std::printf("VEC TB FAIL (%ld failures, seed 0x%llx)\n", failures, (unsigned long long)seed);
  return 1;
}
