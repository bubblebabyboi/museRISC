// museRISC in-house core: FPU unit testbench (C++/Verilator).
//
// DUT: the multi-cycle muserisc_fpu behind its EX handshake
// (req/done/ack/kill). Golden model: Berkeley SoftFloat 3 (the
// RISC-V reference), tininess after rounding, NaN results
// canonicalized; binary32 operands go through the NaN-box check
// before reaching the oracle.
//
// Coverage of the handshake: every operation is issued with
// randomly delayed acks (exercising the HOLD state: the result
// must not change while parked), inputs scrambled while the unit
// is busy (operands must have been latched at issue), random
// idle gaps and back-to-back issue, mid-operation kills and
// request drops (the next operation must be unaffected), and a
// per-op latency check against the documented table.
//
// Stimulus: a random sweep over every op x 5 IEEE rounding
// modes x both formats, biased random/special/boundary operand
// pools (zeros, infinities, quiet/signalling NaNs with payloads,
// min/max subnormal and normal, overflow/underflow edges,
// integer-conversion boundaries, improperly boxed binary32),
// constructed corner families (FMA cancellation, exact
// quotients and squares, tininess boundaries), round-to-odd and
// the non-architectural rm codes 6/7 (=RTZ), and undefined op
// codes. Optional TestFloat vector files (see --testfloat).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <random>
#include <string>
#include <vector>

extern "C" {
#include "softfloat.h"
}

#include "Vmuserisc_fpu.h"
#include "verilated.h"
#include "verilated_cov.h"

namespace {

Vmuserisc_fpu* dut;
long checks = 0, fails = 0;
std::mt19937_64 rng(0xF00D);
std::map<std::string, long> cat_fails, cat_checks;
std::map<std::string, std::map<int, long>> lat_hist;

enum {
  OP_ADD = 0, OP_SUB, OP_MUL, OP_DIV, OP_SQRT, OP_SGNJ, OP_MINMAX,
  OP_CMP, OP_CLASS, OP_F2I, OP_I2F, OP_F2F, OP_FMA, OP_FMS, OP_FNMS,
  OP_FNMA, OP_MVXF, OP_MVFX
};
const char* kOpName[] = {"add", "sub", "mul", "div", "sqrt", "sgnj",
                         "minmax", "cmp", "class", "f2i", "i2f", "f2f",
                         "fmadd", "fmsub", "fnmsub", "fnmadd", "mvxf",
                         "mvfx"};

struct Res {
  uint64_t v;
  uint8_t f;
};

// ------------------------------------------------------------------
// Format helpers
// ------------------------------------------------------------------
uint64_t to_reg(bool d, uint64_t bits) {
  return d ? bits : (0xFFFFFFFF00000000ULL | (uint32_t)bits);
}
uint64_t boxchk(bool d, uint64_t v) {
  return (!d && (v >> 32) != 0xFFFFFFFFULL) ? 0xFFFFFFFF7FC00000ULL : v;
}
bool is_nan32(uint32_t x) {
  return ((x >> 23) & 0xFF) == 0xFF && (x & 0x7FFFFF) != 0;
}
bool is_nan64(uint64_t x) {
  return ((x >> 52) & 0x7FF) == 0x7FF && (x & 0xFFFFFFFFFFFFFULL) != 0;
}
bool is_snan(bool d, uint64_t v) {
  if (d) return is_nan64(v) && !((v >> 51) & 1);
  return is_nan32((uint32_t)v) && !((v >> 22) & 1);
}
bool is_nan(bool d, uint64_t v) {
  return d ? is_nan64(v) : is_nan32((uint32_t)v);
}
bool is_inf(bool d, uint64_t v) {
  return d ? ((v & 0x7FFFFFFFFFFFFFFFULL) == 0x7FF0000000000000ULL)
           : (((uint32_t)v & 0x7FFFFFFFU) == 0x7F800000U);
}
bool is_zero(bool d, uint64_t v) {
  return d ? ((v & 0x7FFFFFFFFFFFFFFFULL) == 0)
           : (((uint32_t)v & 0x7FFFFFFFU) == 0);
}
bool sign_of(bool d, uint64_t v) {
  return d ? (v >> 63) : (((uint32_t)v >> 31) & 1);
}
uint64_t canon_d(uint64_t bits) {
  return is_nan64(bits) ? 0x7FF8000000000000ULL : bits;
}
uint64_t canon_s(uint32_t f) {
  return to_reg(0, is_nan32(f) ? 0x7FC00000U : f);
}

void clear_flags() { softfloat_exceptionFlags = 0; }
uint8_t read_flags() {
  uint_fast8_t f = softfloat_exceptionFlags;
  uint8_t o = 0;
  if (f & softfloat_flag_invalid) o |= 16;
  if (f & softfloat_flag_infinite) o |= 8;
  if (f & softfloat_flag_overflow) o |= 4;
  if (f & softfloat_flag_underflow) o |= 2;
  if (f & softfloat_flag_inexact) o |= 1;
  return o;
}

// RISC-V rm -> SoftFloat mode. 5 is round-to-odd (vfncvt.rod
// shares this path); 6/7 never reach the FPU from the core and
// are defined to behave as RTZ.
uint8_t sf_rm(int rm) {
  switch (rm) {
    case 0: return softfloat_round_near_even;
    case 2: return softfloat_round_min;
    case 3: return softfloat_round_max;
    case 4: return softfloat_round_near_maxMag;
    case 5: return softfloat_round_odd;
    default: return softfloat_round_minMag;
  }
}

uint64_t classify(bool d, uint64_t v) {
  bool s = sign_of(d, v);
  bool sub = d ? (((v >> 52) & 0x7FF) == 0 && (v & 0xFFFFFFFFFFFFFULL))
               : ((((uint32_t)v >> 23) & 0xFF) == 0 &&
                  ((uint32_t)v & 0x7FFFFF));
  if (is_inf(d, v)) return 1ULL << (s ? 0 : 7);
  if (is_nan(d, v)) return 1ULL << (is_snan(d, v) ? 8 : 9);
  if (is_zero(d, v)) return 1ULL << (s ? 3 : 4);
  if (sub) return 1ULL << (s ? 2 : 5);
  return 1ULL << (s ? 1 : 6);
}

// IEEE minNum/maxNum golden (RISC-V 2019 semantics).
uint64_t minmax_golden(bool d, int is_max, uint64_t av, uint64_t bv) {
  bool na = is_nan(d, av), nb = is_nan(d, bv);
  if (is_snan(d, av) || is_snan(d, bv))
    softfloat_exceptionFlags |= softfloat_flag_invalid;
  if (na && nb) return d ? 0x7FF8000000000000ULL : 0xFFFFFFFF7FC00000ULL;
  if (na) return to_reg(d, bv);
  if (nb) return to_reg(d, av);
  if (is_zero(d, av) && is_zero(d, bv)) {
    bool sa = sign_of(d, av), sb = sign_of(d, bv);
    bool sign = is_max ? (sa && sb) : (sa || sb);
    return to_reg(d, sign ? (d ? (1ULL << 63) : (1ULL << 31)) : 0);
  }
  bool lt;
  if (d) {
    float64_t x{av}, y{bv};
    lt = f64_lt(x, y);
  } else {
    float32_t x{(uint32_t)av}, y{(uint32_t)bv};
    lt = f32_lt(x, y);
  }
  return to_reg(d, (is_max ? !lt : lt) ? av : bv);
}

// ------------------------------------------------------------------
// SoftFloat oracle for one FPU operation (register-level operands).
// ------------------------------------------------------------------
Res golden(int op, bool d, int rm, uint64_t a, uint64_t b, uint64_t c,
           int aux) {
  softfloat_roundingMode = sf_rm(rm);
  clear_flags();
  uint64_t ea = boxchk(d, a), eb = boxchk(d, b), ec = boxchk(d, c);
  float64_t fa{ea}, fb{eb}, fc{ec};
  float32_t sa{(uint32_t)ea}, sb{(uint32_t)eb}, sc{(uint32_t)ec};
  uint64_t v = 0;
  switch (op) {
    case OP_ADD: case OP_SUB: case OP_MUL: case OP_DIV:
      if (d) {
        float64_t r = op == OP_ADD ? f64_add(fa, fb)
                    : op == OP_SUB ? f64_sub(fa, fb)
                    : op == OP_MUL ? f64_mul(fa, fb) : f64_div(fa, fb);
        v = canon_d(r.v);
      } else {
        float32_t r = op == OP_ADD ? f32_add(sa, sb)
                    : op == OP_SUB ? f32_sub(sa, sb)
                    : op == OP_MUL ? f32_mul(sa, sb) : f32_div(sa, sb);
        v = canon_s(r.v);
      }
      break;
    case OP_SQRT:
      v = d ? canon_d(f64_sqrt(fa).v) : canon_s(f32_sqrt(sa).v);
      break;
    case OP_FMA: case OP_FMS: case OP_FNMS: case OP_FNMA: {
      bool na = (op == OP_FNMS || op == OP_FNMA);
      bool nc = (op == OP_FMS || op == OP_FNMA);
      if (d) {
        float64_t x{ea ^ (na ? (1ULL << 63) : 0)};
        float64_t z{ec ^ (nc ? (1ULL << 63) : 0)};
        v = canon_d(f64_mulAdd(x, fb, z).v);
      } else {
        float32_t x{(uint32_t)(ea ^ (na ? (1U << 31) : 0))};
        float32_t z{(uint32_t)(ec ^ (nc ? (1U << 31) : 0))};
        v = canon_s(f32_mulAdd(x, sb, z).v);
      }
      break;
    }
    case OP_SGNJ: {
      bool s1 = sign_of(d, ea), s2 = sign_of(d, eb);
      bool s = aux == 0 ? s2 : aux == 1 ? !s2 : (s1 ^ s2);
      v = d ? ((ea & ~(1ULL << 63)) | ((uint64_t)s << 63))
            : to_reg(0, ((uint32_t)ea & 0x7FFFFFFFU) | ((uint32_t)s << 31));
      break;
    }
    case OP_MINMAX:
      v = minmax_golden(d, aux & 1, d ? ea : (uint32_t)ea,
                        d ? eb : (uint32_t)eb);
      break;
    case OP_CMP: {
      bool r;
      if (aux == 2) r = d ? f64_eq(fa, fb) : f32_eq(sa, sb);
      else if (aux == 1) r = d ? f64_lt(fa, fb) : f32_lt(sa, sb);
      else r = d ? f64_le(fa, fb) : f32_le(sa, sb);
      v = r;
      break;
    }
    case OP_CLASS:
      v = classify(d, ea);
      break;
    case OP_F2I: {
      uint8_t m = sf_rm(rm == 5 ? 1 : rm);
      if (d) {
        switch (aux) {
          case 0: v = (uint64_t)(int64_t)f64_to_i32(fa, m, true); break;
          case 1: v = (uint64_t)(int64_t)(int32_t)f64_to_ui32(fa, m, true); break;
          case 2: v = (uint64_t)f64_to_i64(fa, m, true); break;
          default: v = f64_to_ui64(fa, m, true); break;
        }
      } else {
        switch (aux) {
          case 0: v = (uint64_t)(int64_t)f32_to_i32(sa, m, true); break;
          case 1: v = (uint64_t)(int64_t)(int32_t)f32_to_ui32(sa, m, true); break;
          case 2: v = (uint64_t)f32_to_i64(sa, m, true); break;
          default: v = f32_to_ui64(sa, m, true); break;
        }
      }
      break;
    }
    case OP_I2F:
      if (d) {
        float64_t r = aux == 0 ? i32_to_f64((int32_t)a)
                    : aux == 1 ? ui32_to_f64((uint32_t)a)
                    : aux == 2 ? i64_to_f64((int64_t)a) : ui64_to_f64(a);
        v = r.v;
      } else {
        float32_t r = aux == 0 ? i32_to_f32((int32_t)a)
                    : aux == 1 ? ui32_to_f32((uint32_t)a)
                    : aux == 2 ? i64_to_f32((int64_t)a) : ui64_to_f32(a);
        v = to_reg(0, r.v);
      }
      break;
    case OP_F2F: {
      uint64_t src = boxchk(!d, a);  // source is the other format
      if (d) {
        float32_t s{(uint32_t)src};
        v = canon_d(f32_to_f64(s).v);
      } else {
        float64_t s{src};
        v = canon_s(f64_to_f32(s).v);
      }
      break;
    }
    case OP_MVXF:
      v = d ? a : to_reg(0, (uint32_t)a);
      break;
    case OP_MVFX:
      v = d ? a : (uint64_t)(int64_t)(int32_t)(uint32_t)a;
      break;
    default:  // undefined op codes: zero, no flags
      v = 0;
      clear_flags();
      break;
  }
  return Res{v, read_flags()};
}

// Divide/sqrt latency: IDLE + EX1 + ITER x ceil-to-steps(p+2)/BITS
// + DSFIN + ROUND. FPU_DS_BITS must match the RTL build
// (+define+MUSERISC_FPU_DS_BITS; see `make -C sim fpu-ds1`).
#ifndef FPU_DS_BITS
#define FPU_DS_BITS 2
#endif
constexpr int kStepsD = ((55 + FPU_DS_BITS - 1) / FPU_DS_BITS);
constexpr int kStepsS = ((26 + FPU_DS_BITS - 1) / FPU_DS_BITS);
constexpr int kDivLatD = 4 + kStepsD;
constexpr int kDivLatS = 4 + kStepsS;

// Expected FPU latency (cycles the op occupies EX).
int expected_latency(int op, bool d, uint64_t a, uint64_t b, uint64_t c) {
  uint64_t ea = boxchk(d, a), eb = boxchk(d, b), ec = boxchk(d, c);
  bool nan_a = is_nan(d, ea), nan_b = is_nan(d, eb), nan_c = is_nan(d, ec);
  bool inf_a = is_inf(d, ea), inf_b = is_inf(d, eb), inf_c = is_inf(d, ec);
  bool z_a = is_zero(d, ea), z_b = is_zero(d, eb);
  switch (op) {
    case OP_SGNJ: case OP_MVXF: case OP_MVFX: return 1;
    case OP_MINMAX: case OP_CMP: case OP_CLASS: return 2;
    case OP_F2I: case OP_I2F: return 3;
    case OP_F2F: {
      uint64_t src = boxchk(!d, a);
      return (is_nan(!d, src) || is_inf(!d, src)) ? 2 : 3;
    }
    case OP_ADD: case OP_SUB: case OP_MUL:
      return (nan_a || nan_b || inf_a || inf_b) ? 2 : 5;
    case OP_DIV:
      return (nan_a || nan_b || inf_a || inf_b || z_a || z_b) ? 2
             : (d ? kDivLatD : kDivLatS);
    case OP_SQRT:
      return (nan_a || inf_a || z_a || sign_of(d, ea)) ? 2 : (d ? kDivLatD : kDivLatS);
    case OP_FMA: case OP_FMS: case OP_FNMS: case OP_FNMA:
      return (nan_a || nan_b || nan_c || inf_a || inf_b || inf_c) ? 2 : 7;
    default: return 2;  // undefined op codes
  }
}

// ------------------------------------------------------------------
// Handshake driver
// ------------------------------------------------------------------
uint64_t cycles = 0;
void tick() {
  dut->clk_i = 1;
  dut->eval();
  dut->clk_i = 0;
  dut->eval();
  cycles++;
}

void set_inputs(int op, bool d, int rm, uint64_t a, uint64_t b, uint64_t c,
                int aux) {
  dut->op_i = op; dut->fmt_d_i = d; dut->rm_i = rm;
  dut->a_i = a; dut->b_i = b; dut->c_i = c; dut->aux_i = aux;
}

void scramble_inputs() {
  // Anything but a fast op code: a fast op in IDLE would complete
  // combinationally, but the unit is busy here, so it is ignored.
  set_inputs((int)(rng() % 18), rng() & 1, (int)(rng() % 8), rng(), rng(),
             rng(), (int)(rng() & 3));
}

int ack_delay_pct = 25;   // % of ops whose ack is delayed
bool scramble = true;

// Issue one operation and run it to completion. Returns the
// result at ack; checks it is stable while parked in HOLD.
Res issue(int op, bool d, int rm, uint64_t a, uint64_t b, uint64_t c,
          int aux, int* lat) {
  // random idle gap (0 = back-to-back with the previous op)
  int gap = (rng() % 4 == 0) ? (int)(rng() % 3) : 0;
  dut->req_i = 0; dut->ack_i = 0; dut->kill_i = 0;
  for (int i = 0; i < gap; i++) { scramble_inputs(); dut->eval(); tick(); }
  set_inputs(op, d, rm, a, b, c, aux);
  dut->req_i = 1;
  int n = 0;
  int hold = ((int)(rng() % 100) < ack_delay_pct) ? 1 + (int)(rng() % 3) : 0;
  bool seen = false;
  Res first{0, 0};
  while (true) {
    dut->ack_i = 0;
    dut->eval();
    if (dut->done_o) {
      Res now{dut->result_o, (uint8_t)dut->flags_o};
      if (!seen) { seen = true; first = now; *lat = n + 1; }
      else if (now.v != first.v || now.f != first.f) {
        fails++;
        std::printf("FAIL hold-unstable op=%d %016llx -> %016llx\n", op,
                    (unsigned long long)first.v, (unsigned long long)now.v);
      }
      if (hold > 0) {
        hold--;
        tick();
        if (scramble) scramble_inputs();
        continue;
      }
      dut->ack_i = 1;
      dut->eval();
      tick();
      dut->ack_i = 0;
      dut->req_i = 0;
      return first;
    }
    tick();
    n++;
    if (scramble) scramble_inputs();
    if (n > 200) {
      fails++;
      std::printf("FAIL timeout op=%d\n", op);
      dut->kill_i = 1; dut->eval(); tick(); dut->kill_i = 0;
      return Res{~0ULL, 0xFF};
    }
  }
}

void report(const char* what, Res got, Res want, int op, bool d, int rm,
            uint64_t a, uint64_t b, uint64_t c, int aux) {
  checks++;
  cat_checks[what]++;
  if (got.v != want.v || got.f != want.f) {
    cat_fails[what]++;
    if (cat_fails[what] <= 4)
      std::printf("FAIL %s op=%s d=%d rm=%d aux=%d a=%016llx b=%016llx "
                  "c=%016llx got=%016llx/%02x want=%016llx/%02x\n",
                  what, op < 18 ? kOpName[op] : "undef", d, rm, aux,
                  (unsigned long long)a, (unsigned long long)b,
                  (unsigned long long)c, (unsigned long long)got.v, got.f,
                  (unsigned long long)want.v, want.f);
    fails++;
  }
}

void check(const char* what, int op, bool d, int rm, uint64_t a, uint64_t b,
           uint64_t c, int aux) {
  int lat = 0;
  Res got = issue(op, d, rm, a, b, c, aux, &lat);
  Res want = golden(op, d, rm, a, b, c, aux);
  report(what, got, want, op, d, rm, a, b, c, aux);
  int el = expected_latency(op, d, a, b, c);
  std::string key = std::string(op < 18 ? kOpName[op] : "undef") +
                    (d ? ".d" : ".s");
  lat_hist[key][lat]++;
  if (lat != el) {
    fails++;
    cat_fails["latency"]++;
    if (cat_fails["latency"] <= 4)
      std::printf("FAIL latency %s a=%016llx b=%016llx got %d want %d\n",
                  key.c_str(), (unsigned long long)a, (unsigned long long)b,
                  lat, el);
  }
}

// ------------------------------------------------------------------
// Operand pools
// ------------------------------------------------------------------
std::vector<uint64_t> pool_d = {
    0x0000000000000000ULL, 0x8000000000000000ULL,  // +-0
    0x0000000000000001ULL, 0x8000000000000001ULL,  // min subnormal
    0x000FFFFFFFFFFFFFULL, 0x800FFFFFFFFFFFFFULL,  // max subnormal
    0x0008000000000000ULL, 0x0000000080000000ULL,  // mid subnormals
    0x0010000000000000ULL, 0x8010000000000000ULL,  // min normal
    0x0010000000000001ULL, 0x001FFFFFFFFFFFFFULL,
    0x7FEFFFFFFFFFFFFFULL, 0xFFEFFFFFFFFFFFFFULL,  // max normal
    0x7FE0000000000000ULL, 0x7FDFFFFFFFFFFFFFULL,
    0x7FF0000000000000ULL, 0xFFF0000000000000ULL,  // +-inf
    0x7FF8000000000000ULL, 0xFFF8000000000000ULL,  // qNaN
    0x7FF8000000000123ULL, 0x7FF4000000000000ULL,  // qNaN payload, sNaN
    0x7FF0000000000001ULL, 0xFFF7FFFFFFFFFFFFULL,  // sNaN
    0x3FF0000000000000ULL, 0xBFF0000000000000ULL,  // +-1
    0x3FF0000000000001ULL, 0x3FEFFFFFFFFFFFFFULL,  // 1+ulp, 1-ulp
    0x3FF8000000000000ULL, 0x4000000000000000ULL,  // 1.5, 2
    0x3FE0000000000000ULL, 0xBFE0000000000000ULL,  // +-0.5
    0x4008000000000000ULL, 0x3FD0000000000000ULL,  // 3, 0.25
    0x41E0000000000000ULL, 0xC1E0000000000000ULL,  // +-2^31
    0x41EFFFFFFFE00000ULL, 0x41DFFFFFFFC00000ULL,  // 2^32-2, 2^31-1
    0x41F0000000000000ULL, 0xC1E0000000200000ULL,  // 2^32, -(2^31+1)
    0x43E0000000000000ULL, 0xC3E0000000000000ULL,  // +-2^63
    0x43DFFFFFFFFFFFFFULL, 0x43EFFFFFFFFFFFFFULL,  // < 2^63, < 2^64
    0x43F0000000000000ULL, 0xC3F0000000000000ULL,  // +-2^64
    0x4330000000000001ULL, 0x4340000000000001ULL,  // 2^52+1, 2^53+2
    0x3CA0000000000000ULL, 0x0360000000000000ULL,  // 2^-53, 2^-969
    0x3E70000000000000ULL, 0x47EFFFFFE0000000ULL,  // 2^-24, f32 max
    0x47F0000000000000ULL, 0x3810000000000000ULL,  // > f32 max, f32 min normal
    0x380FFFFFFFFFFFFFULL, 0x36A0000000000000ULL,  // < f32 min normal, f32 min sub
    0x3690000000000000ULL, 0x36A8000000000000ULL,  // half f32 min sub, 1.5x
    0x7FE1CCF385EBC8A0ULL, 0x1FF0000000000000ULL};
std::vector<uint64_t> pool_s = {
    0x00000000, 0x80000000, 0x00000001, 0x80000001, 0x007FFFFF, 0x807FFFFF,
    0x00400000, 0x00000100, 0x00800000, 0x80800000, 0x00800001, 0x00FFFFFF,
    0x7F7FFFFF, 0xFF7FFFFF, 0x7F000000, 0x7EFFFFFF, 0x7F800000, 0xFF800000,
    0x7FC00000, 0xFFC00000, 0x7FC00123, 0x7FA00000, 0x7F800001, 0xFFBFFFFF,
    0x3F800000, 0xBF800000, 0x3F800001, 0x3F7FFFFF, 0x3FC00000, 0x40000000,
    0x3F000000, 0xBF000000, 0x40400000, 0x3E800000, 0x4F000000, 0xCF000000,
    0x4F7FFFFF, 0x4EFFFFFF, 0x4F800000, 0xCF000001, 0x5F000000, 0xDF000000,
    0x5EFFFFFF, 0x5F7FFFFF, 0x5F800000, 0xDF800000, 0x4B000001, 0x4B800001,
    0x33800000, 0x0C000000, 0x3E000000, 0x7E800000, 0x34000000, 0x00000003};

uint64_t pick_special(bool d) {
  uint64_t v = d ? pool_d[rng() % pool_d.size()] : pool_s[rng() % pool_s.size()];
  // perturb by a few ulps or flip the sign sometimes
  switch (rng() % 6) {
    case 0: v += (rng() % 5); break;
    case 1: v -= (rng() % 5); break;
    case 2: v ^= d ? (1ULL << 63) : (1ULL << 31); break;
    default: break;
  }
  return to_reg(d, d ? v : (uint32_t)v);
}

uint64_t rnd_operand(bool d) {
  uint64_t v = rng();
  switch (rng() % 8) {
    case 0: case 1:  // exponent near 1.0
      if (d) v = (v & ~(0x7FFULL << 52)) | (((rng() % 80) + 983ULL) << 52);
      else v = (v & ~(0xFFULL << 23)) | (((rng() % 60) + 97ULL) << 23);
      break;
    case 2:  // subnormal / near-underflow
      if (d) v = (v & 0x800FFFFFFFFFFFFFULL) | ((rng() % 3) << 52);
      else v = (v & 0x807FFFFFULL) | ((rng() % 3) << 23);
      break;
    case 3:  // near overflow
      if (d) v = (v & 0x800FFFFFFFFFFFFFULL) | ((0x7FEULL - rng() % 3) << 52);
      else v = (v & 0x807FFFFFULL) | ((0xFEULL - rng() % 3) << 23);
      break;
    case 4:
      return pick_special(d);
    default:
      break;
  }
  if (!d && rng() % 32 == 0) return v;   // improperly NaN-boxed binary32
  return to_reg(d, v);
}

uint64_t rnd_int() {
  switch (rng() % 6) {
    case 0: return rng() % 1000;
    case 1: return (uint64_t)-(int64_t)(rng() % 1000);
    case 2: { int s = rng() % 64; uint64_t v = 1ULL << s;
              return v + (rng() % 3) - 1; }
    case 3: { static const uint64_t k[] = {0, 1, ~0ULL, 0x7FFFFFFFULL,
              0x80000000ULL, 0xFFFFFFFFULL, 0x7FFFFFFFFFFFFFFFULL,
              0x8000000000000000ULL, 0xFFFFFFFF80000000ULL,
              0x00000000FFFFFF80ULL, 0x0020000000000001ULL,
              0x7FFFFFFFFFFFFC00ULL};
              return k[rng() % 12]; }
    case 4: return rng() >> (rng() % 64);
    default: return rng();
  }
}

// value near an integer boundary, for F2I
uint64_t f2i_operand(bool d) {
  softfloat_roundingMode = softfloat_round_near_even;
  int64_t k = (int64_t)rnd_int();
  if (rng() & 1) k = (int64_t)(rng() % 9) - 4;
  float64_t base = i64_to_f64(k);
  float64_t frac{0x3FE0000000000000ULL};  // 0.5
  switch (rng() % 5) {
    case 0: base = f64_add(base, frac); break;
    case 1: base = f64_sub(base, frac); break;
    case 2: base = f64_add(base, float64_t{0x3FD0000000000000ULL}); break;
    case 3: base.v += (rng() % 3); break;
    default: break;
  }
  if (d) return base.v;
  return to_reg(0, f64_to_f32(base).v);
}

const char* cat_for(int op) {
  switch (op) {
    case OP_ADD: case OP_SUB: case OP_MUL: case OP_DIV: return "arith";
    case OP_SQRT: return "sqrt";
    case OP_FMA: case OP_FMS: case OP_FNMS: case OP_FNMA: return "fma";
    case OP_SGNJ: return "sgnj";
    case OP_MINMAX: return "minmax";
    case OP_CMP: return "cmp";
    case OP_CLASS: return "class";
    case OP_F2I: return "f2i";
    case OP_I2F: return "i2f";
    case OP_F2F: return "f2f";
    case OP_MVXF: case OP_MVFX: return "mv";
    default: return "undef";
  }
}

void one_random(int op, bool d, int rm) {
  int aux = (int)(rng() & 3);
  uint64_t a = rnd_operand(d), b = rnd_operand(d), c = rnd_operand(d);
  switch (op) {
    case OP_SGNJ: if (aux == 3) aux = 2; break;
    case OP_MINMAX: aux &= 1; break;
    case OP_CMP: if (aux == 3) aux = 2; break;
    case OP_F2I: if (rng() & 1) a = f2i_operand(d); break;
    case OP_I2F: a = rnd_int(); break;
    case OP_F2F: a = rnd_operand(!d); break;
    case OP_MVXF: a = rng(); break;
    case OP_FMA: case OP_FMS: case OP_FNMS: case OP_FNMA:
      if (rng() % 8 == 0) {
        // massive cancellation: c ~= +-(a*b)
        Res p = golden(OP_MUL, d, (int)(rng() % 5), a, b, 0, 0);
        c = p.v ^ ((op == OP_FMS || op == OP_FMA)
                       ? (d ? (1ULL << 63) : (1ULL << 31)) : 0);
        if (rng() & 1) c += (rng() % 3) - 1;
      }
      break;
    case OP_DIV:
      if (rng() % 8 == 0) {  // exact quotient
        Res p = golden(OP_MUL, d, 1, b, to_reg(d, d ? 0x4014000000000000ULL
                                                        : 0x40A00000ULL), 0, 0);
        a = p.v;
      }
      break;
    case OP_SQRT:
      if (rng() % 8 == 0) a = golden(OP_MUL, d, 1, a, a, 0, 0).v;
      break;
    default: break;
  }
  check(cat_for(op), op, d, rm, a, b, c, aux);
}

// ------------------------------------------------------------------
// Handshake-specific scenarios
// ------------------------------------------------------------------
void kill_scenarios() {
  for (int t = 0; t < 2000; t++) {
    bool d = rng() & 1;
    int op = (int)(rng() % 16);
    if (op == OP_SGNJ) op = OP_DIV;
    uint64_t a = rnd_operand(d), b = rnd_operand(d), c = rnd_operand(d);
    if (op == OP_I2F) a = rnd_int();
    int stop = 1 + (int)(rng() % 30);
    set_inputs(op, d, 0, a, b, c, 0);
    dut->req_i = 1; dut->ack_i = 0; dut->kill_i = 0;
    for (int i = 0; i < stop; i++) {
      dut->eval();
      tick();
      scramble_inputs();
    }
    // either an explicit kill or the request simply dropping
    if (rng() & 1) { dut->kill_i = 1; dut->req_i = rng() & 1; }
    else dut->req_i = 0;
    dut->eval();
    tick();
    dut->kill_i = 0;
    dut->req_i = 0;
    dut->eval();
    // the next op must be clean
    op = (int)(rng() % 18);
    one_random(op, d, (int)(rng() % 5));
  }
}

// ------------------------------------------------------------------
// TestFloat vector files: "<op> <d> <rm> <a> <b> <c> <want> <flags>"
// lines produced by scripts/testfloat_fpu_vectors.sh (testfloat_gen).
// ------------------------------------------------------------------
long run_vectors(const char* path) {
  FILE* f = std::fopen(path, "r");
  if (!f) { std::printf("cannot open %s\n", path); fails++; return 0; }
  char line[512];
  long n = 0;
  ack_delay_pct = 5;
  scramble = false;
  while (std::fgets(line, sizeof line, f)) {
    unsigned op, d, rm, aux, fl;
    unsigned long long a, b, c, want;
    if (std::sscanf(line, "%u %u %u %u %llx %llx %llx %llx %x", &op, &d, &rm,
                    &aux, &a, &b, &c, &want, &fl) != 9)
      continue;
    int lat;
    Res got = issue((int)op, d, (int)rm, a, b, c, (int)aux, &lat);
    report("testfloat", got, Res{want, (uint8_t)fl}, (int)op, d, (int)rm, a,
           b, c, (int)aux);
    n++;
  }
  std::fclose(f);
  return n;
}

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const char* cov_path = std::getenv("COV_FILE");
  dut = new Vmuserisc_fpu{&context};
  softfloat_detectTininess = softfloat_tininess_afterRounding;

  const char* tf_path = nullptr;
  int N = 2000;
  for (int i = 1; i < argc; i++) {
    if (!std::strcmp(argv[i], "--testfloat") && i + 1 < argc) tf_path = argv[++i];
    else if (!std::strcmp(argv[i], "--n") && i + 1 < argc) N = std::atoi(argv[++i]);
  }

  dut->clk_i = 0; dut->rst_ni = 0; dut->req_i = 0; dut->ack_i = 0;
  dut->kill_i = 0;
  dut->eval();
  tick();
  dut->rst_ni = 1;
  dut->eval();

  if (tf_path) {
    long n = run_vectors(tf_path);
    std::printf("testfloat vectors: %ld\n", n);
  } else {
    // 1. Random sweep: every op x both formats x 5 IEEE modes.
    for (int d = 0; d <= 1; d++)
      for (int rm = 0; rm < 5; rm++)
        for (int i = 0; i < N; i++)
          for (int op = 0; op <= OP_MVFX; op++) one_random(op, d, rm);
    // 2. Round-to-odd (vfncvt.rod path) and rm codes 6/7 (= RTZ).
    for (int d = 0; d <= 1; d++)
      for (int rm = 5; rm < 8; rm++)
        for (int i = 0; i < N / 4; i++)
          for (int op = 0; op <= OP_MVFX; op++) one_random(op, d, rm);
    // 3. All special-pool pairs for the two-operand ops.
    for (int d = 0; d <= 1; d++) {
      const auto& pool = d ? pool_d : pool_s;
      for (uint64_t x : pool)
        for (uint64_t y : pool) {
          uint64_t a = to_reg(d, x), b = to_reg(d, y);
          int rm = (int)(rng() % 5);
          for (int op : {OP_ADD, OP_SUB, OP_MUL, OP_DIV})
            check("pool", op, d, rm, a, b, 0, 0);
          check("pool", OP_MINMAX, d, rm, a, b, 0, (int)(rng() & 1));
          check("pool", OP_CMP, d, rm, a, b, 0, (int)(rng() % 3));
          check("pool", OP_FMA + (int)(rng() % 4), d, rm, a, b,
                pick_special(d), 0);
          check("pool", OP_FMA + (int)(rng() % 4), d, rm, a,
                rnd_operand(d), b, 0);
        }
      for (uint64_t x : pool) {
        uint64_t a = to_reg(d, x);
        for (int rm = 0; rm < 5; rm++) {
          check("pool", OP_SQRT, d, rm, a, 0, 0, 0);
          for (int aux = 0; aux < 4; aux++) check("pool", OP_F2I, d, rm, a, 0, 0, aux);
          check("pool", OP_F2F, !d, rm, a, 0, 0, 0);
        }
        check("pool", OP_CLASS, d, 0, a, 0, 0, 0);
        for (int aux = 0; aux < 3; aux++) check("pool", OP_SGNJ, d, 0, a, rnd_operand(d), 0, aux);
      }
    }
    // 4. I2F boundaries in every mode and width.
    for (int d = 0; d <= 1; d++)
      for (int rm = 0; rm < 5; rm++)
        for (int i = 0; i < 400; i++)
          check("i2f", OP_I2F, d, rm, rnd_int(), 0, 0, (int)(rng() & 3));
    // 5. Tininess-boundary regressions (ACT D-fmadd.d-06): results
    //    just below 2^emin that round up to min-normal.
    check("tininess", OP_FMA, 1, 3, 0x8010000000000000ULL,
          0x91CF4D7110BEE879ULL, 0x000FFFFFFFFFFFFFULL, 0);
    check("tininess", OP_FMA, 1, 3, 0x0010000000000000ULL,
          0x99A6BAAE71EB5A39ULL, 0x0010000000000000ULL, 0);
    check("tininess", OP_FMA, 1, 0, 0x0010000000000000ULL,
          0x99A6BAAE71EB5A39ULL, 0x0010000000000000ULL, 0);
    // FMA exact cancellation: +0, or -0 under RDN.
    check("fma-cancel", OP_FMA, 1, 0, 0x3FF8000000000000ULL,
          0x4000000000000000ULL, 0xC008000000000000ULL, 0);
    check("fma-cancel", OP_FMA, 1, 2, 0x3FF8000000000000ULL,
          0x4000000000000000ULL, 0xC008000000000000ULL, 0);
    // Products of zero with finite addends (datapath, not special).
    for (int d = 0; d <= 1; d++)
      for (int rm = 0; rm < 5; rm++)
        for (int i = 0; i < 50; i++) {
          uint64_t z = to_reg(d, (rng() & 1) ? (d ? (1ULL << 63) : (1ULL << 31)) : 0);
          check("fma-zero", OP_FMA + (int)(rng() % 4), d, rm, z,
                rnd_operand(d), (rng() & 1) ? z : rnd_operand(d), 0);
        }
    // 6. Undefined op codes 18..31: zero result, no flags.
    for (int op = 18; op < 32; op++)
      check("undef", op, rng() & 1, 0, rng(), rng(), rng(), 0);
    // 7. Handshake: kills and request drops mid-operation.
    kill_scenarios();
    // 8. Asynchronous reset while an operation is in flight; the
    //    next operation must be clean.
    for (int t = 0; t < 40; t++) {
      set_inputs(OP_DIV, 1, 0, 0x4000000000000000ULL + rng() % 1000,
                 0x3FF8000000000000ULL, 0, 0);
      dut->req_i = 1; dut->ack_i = 0;
      for (int i = 0; i <= t; i++) { dut->eval(); tick(); }
      dut->req_i = 0; dut->rst_ni = 0; dut->eval(); tick();
      dut->rst_ni = 1; dut->eval();
      one_random((int)(rng() % 18), rng() & 1, (int)(rng() % 5));
    }
  }

  for (auto& kv : cat_checks)
    std::printf("checks[%s] = %ld%s\n", kv.first.c_str(), kv.second,
                cat_fails.count(kv.first) ? " (FAILS)" : "");
  for (auto& kv : cat_fails)
    std::printf("fails[%s] = %ld\n", kv.first.c_str(), kv.second);
  std::printf("latency (cycles in EX) per op:");
  for (auto& kv : lat_hist) {
    std::printf("\n  %-9s", kv.first.c_str());
    for (auto& l : kv.second) std::printf(" %d:%ld", l.first, l.second);
  }
  std::printf("\ncycles simulated: %llu\n", (unsigned long long)cycles);
  dut->final();
  // write coverage before the model (which owns the counters) is freed
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  delete dut;
  if (fails) {
    std::printf("FPU TB FAIL (%ld/%ld)\n", fails, checks);
    return 1;
  }
  std::printf("FPU TB PASS (%ld checks)\n", checks);
  return 0;
}
