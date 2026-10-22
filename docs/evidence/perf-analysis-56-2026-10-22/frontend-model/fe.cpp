// fe.cpp: trace-driven front-end study for the Sigil #56 baseline.
// Reads a Spike --log-commits trace on stdin, the program ELF (argv[1]),
// cuts it into the SIGIL_PERF marker regions (csrw 0x33f), and per region:
//   * instruction / control-flow statistics (cross-check with the RTL counters)
//   * branch direction predictor, BTB and RAS accuracy
//   * a cycle model of the eeaa332 pipeline (front end exact to the RTL rules)
//     and of front-end variants (fetch width, prefetch, branch prediction).
// Output: one block of key=value lines per region on stdout.
#include <bits/stdc++.h>
using namespace std;
typedef uint64_t u64;
typedef int64_t i64;

// ----------------------------------------------------------------- ELF image
struct Image {
  vector<pair<u64, vector<uint8_t>>> segs;
  bool rd16(u64 a, uint16_t& v) const {
    for (auto& s : segs)
      if (a >= s.first && a + 2 <= s.first + s.second.size()) {
        v = s.second[a - s.first] | (s.second[a - s.first + 1] << 8);
        return true;
      }
    return false;
  }
  void load(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) { perror(path); exit(1); }
    vector<uint8_t> b;
    uint8_t buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) b.insert(b.end(), buf, buf + n);
    fclose(f);
    auto r16 = [&](size_t o) { return (u64)b[o] | ((u64)b[o + 1] << 8); };
    auto r32 = [&](size_t o) { return r16(o) | (r16(o + 2) << 16); };
    auto r64 = [&](size_t o) { return r32(o) | (r32(o + 4) << 32); };
    u64 phoff = r64(32);
    u64 phentsize = r16(54), phnum = r16(56);
    for (u64 i = 0; i < phnum; i++) {
      size_t p = phoff + i * phentsize;
      if (r32(p) != 1) continue;  // PT_LOAD
      u64 off = r64(p + 8), vaddr = r64(p + 16), filesz = r64(p + 32);
      if (!(r32(p + 4) & 1)) continue;  // executable segments only
      segs.push_back({vaddr, vector<uint8_t>(b.begin() + off, b.begin() + off + filesz)});
    }
  }
};
static Image img;

// ----------------------------------------------------------------- decode
enum Cls : uint8_t { C_ALU, C_LOAD, C_STORE, C_BR, C_JAL, C_JALR, C_MUL, C_DIV, C_FP,
                     C_VEC, C_VLS, C_CSR, C_FENCE, C_SYS, C_AMO };
struct Dec {
  uint8_t len = 4, cls = C_ALU;
  uint8_t rd = 0;       // destination (int or fp per rd_fp)
  bool rd_fp = false;
  uint8_t rs1 = 0, rs2 = 0, rs3 = 0;
  bool u1 = false, u2 = false;          // reads int rs1/rs2 (RTL id_uses_rs1/2 rule)
  bool f1 = false, f2 = false, f3 = false;  // reads fp rs1/rs2/rs3
  i64 imm = 0;          // branch/jal offset
  int fplat = 0;        // FPU hold cycles
  bool w = false;       // 32-bit op (divw)
  bool is_div_sign = false;
};
static inline i64 sx(u64 v, int bits) { return (i64)(v << (64 - bits)) >> (64 - bits); }

// RTL rule for uses_rs1/uses_rs2 on the (expanded) 32-bit opcode.
static void rtl_uses(Dec& d, uint32_t op) {
  d.u1 = !(op == 0x37 || op == 0x17 || op == 0x6f);
  d.u2 = (op == 0x33 || op == 0x3b || op == 0x23 || op == 0x63 || op == 0x2f);
}

static Dec decode32(uint32_t x) {
  Dec d;
  d.len = 4;
  uint32_t op = x & 0x7f, f3 = (x >> 12) & 7, f7 = x >> 25;
  d.rd = (x >> 7) & 31;
  d.rs1 = (x >> 15) & 31;
  d.rs2 = (x >> 20) & 31;
  d.rs3 = x >> 27;
  rtl_uses(d, op);
  switch (op) {
    case 0x63: d.cls = C_BR; d.rd = 0;
      d.imm = sx(((x >> 31) & 1) << 12 | ((x >> 7) & 1) << 11 | ((x >> 25) & 0x3f) << 5 | ((x >> 8) & 0xf) << 1, 13);
      break;
    case 0x6f: d.cls = C_JAL;
      d.imm = sx(((x >> 31) & 1) << 20 | ((x >> 12) & 0xff) << 12 | ((x >> 20) & 1) << 11 | ((x >> 21) & 0x3ff) << 1, 21);
      break;
    case 0x67: d.cls = C_JALR; d.imm = sx(x >> 20, 12); break;
    case 0x03: d.cls = C_LOAD; break;
    case 0x23: d.cls = C_STORE; d.rd = 0; break;
    case 0x07:
      if (f3 == 1 || f3 == 2 || f3 == 3 || f3 == 4) { d.cls = C_LOAD; d.rd_fp = true; }
      else { d.cls = C_VLS; d.rd = 0; }
      break;
    case 0x27:
      if (f3 == 1 || f3 == 2 || f3 == 3 || f3 == 4) { d.cls = C_STORE; d.rd = 0; d.f2 = true; }
      else { d.cls = C_VLS; d.rd = 0; }
      break;
    case 0x2f: d.cls = C_AMO; break;
    case 0x33: case 0x3b:
      if (f7 == 1) { d.cls = (f3 < 4) ? C_MUL : C_DIV; d.w = (op == 0x3b); d.is_div_sign = !(f3 & 1); }
      else d.cls = C_ALU;
      break;
    case 0x73: d.cls = (f3 == 0) ? C_SYS : C_CSR; break;
    case 0x0f: d.cls = C_FENCE; d.rd = 0; break;
    case 0x43: case 0x47: case 0x4b: case 0x4f:
      d.cls = C_FP; d.rd_fp = true; d.f1 = d.f2 = d.f3 = true; d.u1 = d.u2 = false; d.fplat = 6; break;
    case 0x53: {
      d.cls = C_FP; d.u2 = false;
      uint32_t f5 = x >> 27;
      bool to_int = (f5 == 0x14 /*cmp*/ || f5 == 0x18 /*fcvt.int*/ || f5 == 0x1c /*fmv.x/fclass*/);
      bool from_int = (f5 == 0x1a /*fcvt.from int*/ || f5 == 0x1e /*fmv.from x*/);
      d.rd_fp = !to_int;
      d.f1 = !from_int; d.u1 = from_int;
      d.f2 = (f5 <= 0x05 || f5 == 0x14);
      if (f5 == 0x03) d.fplat = (x >> 25 & 1) ? 31 : 16;          // fdiv d/s
      else if (f5 == 0x0b) d.fplat = (x >> 25 & 1) ? 31 : 16;     // fsqrt
      else if (f5 <= 0x02) d.fplat = 4;                           // fadd/fsub/fmul
      else d.fplat = 2;                                            // other (estimate)
      break;
    }
    case 0x57: d.cls = C_VEC; d.rd = (f3 == 7) ? d.rd : 0; break;
    default: d.cls = C_ALU; break;
  }
  if (!(d.cls == C_LOAD || d.cls == C_ALU || d.cls == C_JAL || d.cls == C_JALR || d.cls == C_MUL ||
        d.cls == C_DIV || d.cls == C_CSR || d.cls == C_AMO || d.cls == C_FP || d.cls == C_VEC))
    d.rd = 0;
  return d;
}

static Dec decode16(uint16_t x) {
  Dec d;
  d.len = 2;
  uint32_t q = x & 3, f3 = (x >> 13) & 7;
  uint8_t rdp = 8 + ((x >> 2) & 7), rs1p = 8 + ((x >> 7) & 7);
  uint8_t r117 = (x >> 7) & 31, r62 = (x >> 2) & 31;
  auto alu = [&](uint8_t rd, uint8_t rs1, bool use2, uint8_t rs2) {
    d.cls = C_ALU; d.rd = rd; d.rs1 = rs1; d.u1 = true; d.rs2 = rs2; d.u2 = use2;
  };
  if (q == 0) {
    switch (f3) {
      case 0: alu(rdp, 2, false, 0); break;                             // c.addi4spn
      case 1: d.cls = C_LOAD; d.rd = rdp; d.rd_fp = true; d.rs1 = rs1p; d.u1 = true; break;  // c.fld
      case 2: case 3: d.cls = C_LOAD; d.rd = rdp; d.rs1 = rs1p; d.u1 = true; break;      // c.lw/c.ld
      case 4: {  // Zcb
        uint32_t f = (x >> 10) & 7;
        if (f == 0 || f == 1) { d.cls = C_LOAD; d.rd = rdp; d.rs1 = rs1p; d.u1 = true; }
        else { d.cls = C_STORE; d.rs1 = rs1p; d.rs2 = rdp; d.u1 = d.u2 = true; }
        break;
      }
      case 5: d.cls = C_STORE; d.rs1 = rs1p; d.u1 = true; d.rs2 = rdp; d.f2 = true; break;  // c.fsd
      default: d.cls = C_STORE; d.rs1 = rs1p; d.rs2 = rdp; d.u1 = d.u2 = true; break;      // c.sw/c.sd
    }
  } else if (q == 1) {
    switch (f3) {
      case 0: case 1: alu(r117, r117, false, 0); break;                  // c.addi / c.addiw
      case 2: alu(r117, 0, false, 0); break;                             // c.li
      case 3:
        if (r117 == 2) alu(2, 2, false, 0);                              // c.addi16sp
        else { d.cls = C_ALU; d.rd = r117; d.u1 = false; }               // c.lui
        break;
      case 4: {
        uint32_t f2 = (x >> 10) & 3;
        if (f2 < 3) alu(rs1p, rs1p, false, 0);                           // srli/srai/andi
        else {
          uint32_t b12 = (x >> 12) & 1, f65 = (x >> 5) & 3;
          if (b12 && f65 == 2) { d.cls = C_MUL; d.rd = rs1p; d.rs1 = rs1p; d.rs2 = rdp; d.u1 = d.u2 = true; }  // c.mul
          else if (b12 && f65 == 3) {                                    // Zcb unary
            uint32_t s = (x >> 2) & 7;
            alu(rs1p, rs1p, (s == 2 || s == 4), 0);                      // zext.h / zext.w use OP-32 (rs2=x0)
          } else alu(rs1p, rs1p, true, rdp);                             // sub/xor/or/and/subw/addw
        }
        break;
      }
      case 5: d.cls = C_JAL; d.rd = 0; d.u1 = false;                     // c.j
        d.imm = sx(((x >> 12) & 1) << 11 | ((x >> 11) & 1) << 4 | ((x >> 9) & 3) << 8 | ((x >> 8) & 1) << 10 |
                   ((x >> 7) & 1) << 6 | ((x >> 6) & 1) << 7 | ((x >> 3) & 7) << 1 | ((x >> 2) & 1) << 5, 12);
        break;
      default: d.cls = C_BR; d.rs1 = rs1p; d.u1 = true; d.rs2 = 0; d.u2 = true;  // c.beqz/bnez
        d.imm = sx(((x >> 12) & 1) << 8 | ((x >> 10) & 3) << 3 | ((x >> 5) & 3) << 6 | ((x >> 3) & 3) << 1 |
                   ((x >> 2) & 1) << 5, 9);
        break;
    }
  } else {  // q == 2
    switch (f3) {
      case 0: alu(r117, r117, false, 0); break;                          // c.slli
      case 1: d.cls = C_LOAD; d.rd = r117; d.rd_fp = true; d.rs1 = 2; d.u1 = true; break;  // c.fldsp
      case 2: case 3: d.cls = C_LOAD; d.rd = r117; d.rs1 = 2; d.u1 = true; break;           // c.lwsp/ldsp
      case 4: {
        uint32_t b12 = (x >> 12) & 1;
        if (!b12) {
          if (r62 == 0) { d.cls = C_JALR; d.rd = 0; d.rs1 = r117; d.u1 = true; }           // c.jr
          else alu(r117, 0, true, r62);                                                     // c.mv (add rd,x0,rs2)
        } else {
          if (r117 == 0 && r62 == 0) { d.cls = C_SYS; }                                     // c.ebreak
          else if (r62 == 0) { d.cls = C_JALR; d.rd = 1; d.rs1 = r117; d.u1 = true; }      // c.jalr
          else alu(r117, r117, true, r62);                                                  // c.add
        }
        break;
      }
      case 5: d.cls = C_STORE; d.rs1 = 2; d.u1 = true; d.rs2 = r62; d.f2 = true; break;     // c.fsdsp
      default: d.cls = C_STORE; d.rs1 = 2; d.rs2 = r62; d.u1 = d.u2 = true; break;          // c.swsp/sdsp
    }
  }
  if (d.cls == C_LOAD && !d.rd_fp && d.rd == 0) {}
  return d;
}
static Dec decode(uint32_t insn) { return ((insn & 3) == 3) ? decode32(insn) : decode16((uint16_t)insn); }

static bool fetch_insn(u64 pc, uint32_t& insn) {
  uint16_t lo, hi;
  if (!img.rd16(pc, lo)) return false;
  if ((lo & 3) != 3) { insn = lo; return true; }
  if (!img.rd16(pc + 2, hi)) return false;
  insn = lo | ((uint32_t)hi << 16);
  return true;
}

// ----------------------------------------------------------------- trace records
struct Ins {
  u64 pc, npc;       // npc = actual next pc
  u64 maddr;         // memory address (loads/stores), 0 if none
  uint32_t insn;
  Dec d;
  uint8_t hold;      // EX hold cycles (mul/div)
  bool taken() const { return npc != pc + d.len; }
};
static inline bool is_link(int r) { return r == 1 || r == 5; }
static inline bool is_ret(const Ins& i) { return i.d.cls == C_JALR && i.d.rd == 0 && is_link(i.d.rs1); }
static inline bool is_call(const Ins& i) { return (i.d.cls == C_JAL || i.d.cls == C_JALR) && is_link(i.d.rd); }

// ----------------------------------------------------------------- caches (tag only)
struct Cache {
  int sets = 64, ways = 2, line = 64;
  vector<u64> tag;
  vector<uint8_t> valid, dirty;
  int rr = 0;  // global round-robin pointer, as the RTL (rr_q)
  void init(int s, int w, int l) { sets = s; ways = w; line = l; tag.assign(s * w, 0); valid.assign(s * w, 0); dirty.assign(s * w, 0); rr = 0; }
  // returns 0 hit, 1 clean miss, 2 dirty miss
  int access(u64 a, bool write) {
    u64 ln = a / line;
    int s = ln % sets;
    u64 t = ln / sets;
    for (int w = 0; w < ways; w++)
      if (valid[s * ways + w] && tag[s * ways + w] == t) { if (write) dirty[s * ways + w] = 1; return 0; }
    int victim = -1;
    for (int w = ways - 1; w >= 0; w--) if (!valid[s * ways + w]) victim = w;
    if (victim < 0) { victim = rr; rr = (rr + 1) % ways; }
    int r = (valid[s * ways + victim] && dirty[s * ways + victim]) ? 2 : 1;
    valid[s * ways + victim] = 1; tag[s * ways + victim] = t; dirty[s * ways + victim] = write;
    return r;
  }
};

// ----------------------------------------------------------------- predictors
struct Dir {  // direction predictor interface: bimodal / gshare / static
  int kind = 0;  // 0 NT, 1 BTFN, 2 bimodal, 3 gshare, 4 always T
  int bits = 0, hbits = 0;
  vector<uint8_t> t;
  u64 ghr = 0;
  void init(int k, int b = 0, int h = 0) { kind = k; bits = b; hbits = h; t.assign(b ? (1u << b) : 0, 1); ghr = 0; }
  u64 idx(u64 pc) const {
    u64 i = pc >> 1;
    if (kind == 3) i ^= (ghr & ((1ull << hbits) - 1));
    return i & ((1ull << bits) - 1);
  }
  bool pred(u64 pc, i64 imm) const {
    switch (kind) {
      case 0: return false;
      case 1: return imm < 0;
      case 4: return true;
      default: return t[idx(pc)] >= 2;
    }
  }
  void upd(u64 pc, bool tk) {
    if (kind == 2 || kind == 3) {
      uint8_t& c = t[idx(pc)];
      if (tk && c < 3) c++;
      if (!tk && c > 0) c--;
    }
    if (kind == 3) ghr = (ghr << 1) | tk;
  }
};
struct BTB {
  int sets = 0, ways = 1;
  vector<u64> tg, tgt; vector<uint32_t> lru; vector<uint8_t> v;
  uint32_t clk = 0;
  void init(int entries, int w) { ways = w; sets = entries / w; tg.assign(entries, 0); tgt.assign(entries, 0); lru.assign(entries, 0); v.assign(entries, 0); }
  bool look(u64 pc, u64& target) {
    if (!sets) return false;
    u64 i = (pc >> 1) % sets;
    for (int w = 0; w < ways; w++) { int e = i * ways + w; if (v[e] && tg[e] == pc) { target = tgt[e]; lru[e] = ++clk; return true; } }
    return false;
  }
  void ins(u64 pc, u64 target) {
    if (!sets) return;
    u64 i = (pc >> 1) % sets;
    int vic = 0; uint32_t best = UINT32_MAX;
    for (int w = 0; w < ways; w++) {
      int e = i * ways + w;
      if (v[e] && tg[e] == pc) { tgt[e] = target; lru[e] = ++clk; return; }
      uint32_t key = v[e] ? lru[e] : 0;
      if (key < best) { best = key; vic = w; }
    }
    int e = i * ways + vic; v[e] = 1; tg[e] = pc; tgt[e] = target; lru[e] = ++clk;
  }
};
struct RAS {
  int depth = 0; vector<u64> s; int top = 0, n = 0;
  void init(int d) { depth = d; s.assign(max(d, 1), 0); top = 0; n = 0; }
  void push(u64 a) { if (!depth) return; top = (top + 1) % depth; s[top] = a; if (n < depth) n++; }
  bool pop(u64& a) { if (!depth || !n) return false; a = s[top]; top = (top - 1 + depth) % depth; n--; return true; }
};

// ----------------------------------------------------------------- region store
struct Region { int id = -1; vector<Ins> ins; };

// ----------------------------------------------------------------- statistics
static void stats(const Region& R, FILE* o) {
  const auto& v = R.ins;
  u64 n = v.size(), rvc = 0, br = 0, brt = 0, jal = 0, jalr = 0, ret = 0, call = 0, ind = 0, ld = 0, st = 0;
  u64 strad4 = 0, strad8 = 0, mul = 0, div = 0, fp = 0, vec = 0, brback = 0, brbackt = 0, brfwdt = 0;
  for (auto& i : v) {
    if (i.d.len == 2) rvc++;
    else { if ((i.pc & 3) == 2) strad4++; if ((i.pc & 7) == 6) strad8++; }
    switch (i.d.cls) {
      case C_BR: br++; if (i.taken()) brt++; if (i.d.imm < 0) { brback++; if (i.taken()) brbackt++; } else if (i.taken()) brfwdt++; break;
      case C_JAL: jal++; break;
      case C_JALR: jalr++; if (is_ret(i)) ret++; else if (is_call(i)) call++; else ind++; break;
      case C_LOAD: ld++; break;
      case C_STORE: st++; break;
      case C_MUL: mul++; break;
      case C_DIV: div++; break;
      case C_FP: fp++; break;
      case C_VEC: case C_VLS: vec++; break;
      default: break;
    }
  }
  fprintf(o, "instr=%lu rvc=%lu ld=%lu st=%lu br=%lu br_taken=%lu br_back=%lu br_back_taken=%lu br_fwd_taken=%lu jal=%lu jalr=%lu ret=%lu jalr_call=%lu jalr_other=%lu mul=%lu div=%lu fp=%lu vec=%lu strad4=%lu strad8=%lu\n",
          n, rvc, ld, st, br, brt, brback, brbackt, brfwdt, jal, jalr, ret, call, ind, mul, div, fp, vec, strad4, strad8);
  // fetch accesses under alternative fetch organisations (correct path only)
  u64 acc_word = 0, acc_reuse4 = 0, acc_blk8 = 0;
  {
    u64 lastblk4 = ~0ull, lastblk8 = ~0ull; bool seq = false;
    for (auto& i : v) {
      // baseline: one access per instruction, two when 32-bit at pc%4==2
      acc_word += 1 + ((i.d.len == 4 && (i.pc & 3) == 2) ? 1 : 0);
      u64 b4a = i.pc >> 2, b4b = (i.pc + i.d.len - 1) >> 2;
      u64 b8a = i.pc >> 3, b8b = (i.pc + i.d.len - 1) >> 3;
      if (!(seq && b4a == lastblk4)) acc_reuse4++;
      if (b4b != b4a) acc_reuse4++;
      if (!(seq && b8a == lastblk8)) acc_blk8++;
      if (b8b != b8a) acc_blk8++;
      lastblk4 = b4b; lastblk8 = b8b;
      seq = !i.taken();
    }
  }
  fprintf(o, "fetch_acc_word=%lu fetch_acc_reuse4=%lu fetch_acc_blk8=%lu\n", acc_word, acc_reuse4, acc_blk8);
  // direction predictors over conditional branches
  vector<pair<string, Dir>> dps;
  { Dir d; d.init(0); dps.push_back({"NT", d}); }
  { Dir d; d.init(4); dps.push_back({"T", d}); }
  { Dir d; d.init(1); dps.push_back({"BTFN", d}); }
  for (int b : {4, 5, 6, 7, 8, 9, 10, 11, 12}) { Dir d; d.init(2, b); dps.push_back({"bim" + to_string(1 << b), d}); }
  for (auto bh : vector<pair<int, int>>{{6, 4}, {7, 6}, {8, 4}, {8, 8}, {9, 6}, {9, 9}, {10, 8}, {10, 10}, {11, 11}, {12, 12}}) {
    Dir d; d.init(3, bh.first, bh.second); dps.push_back({"gsh" + to_string(1 << bh.first) + "h" + to_string(bh.second), d});
  }
  for (auto& p : dps) {
    u64 miss = 0;
    for (auto& i : v) if (i.d.cls == C_BR) { bool t = i.taken(); if (p.second.pred(i.pc, i.d.imm) != t) miss++; p.second.upd(i.pc, t); }
    fprintf(o, "dir.%s.miss=%lu\n", p.first.c_str(), miss);
  }
  // BTB: fraction of taken CTIs (branches, jal, non-return jalr) whose target the BTB provides
  for (int ways : {1, 2}) for (int e : {4, 8, 16, 32, 64, 128, 256, 512}) {
    if (e < ways) continue;
    BTB b; b.init(e, ways);
    u64 tk = 0, hit = 0, jalr_tk = 0, jalr_hit = 0;
    for (auto& i : v) {
      bool cti = (i.d.cls == C_BR || i.d.cls == C_JAL || (i.d.cls == C_JALR && !is_ret(i)));
      if (!cti || !i.taken()) continue;
      tk++; u64 t;
      bool h = b.look(i.pc, t) && t == i.npc;
      if (h) hit++;
      if (i.d.cls == C_JALR) { jalr_tk++; if (h) jalr_hit++; }
      b.ins(i.pc, i.npc);
    }
    fprintf(o, "btb.%dw%d taken=%lu hit=%lu jalr_taken=%lu jalr_hit=%lu\n", e, ways, tk, hit, jalr_tk, jalr_hit);
  }
  for (int dpt : {1, 2, 4, 8, 16}) {
    RAS r; r.init(dpt);
    u64 rets = 0, ok = 0;
    for (auto& i : v) {
      if (is_ret(i)) { rets++; u64 a; if (r.pop(a) && a == i.npc) ok++; }
      if (is_call(i)) r.push(i.pc + i.d.len);
    }
    fprintf(o, "ras.%d returns=%lu correct=%lu\n", dpt, rets, ok);
  }
}

// ----------------------------------------------------------------- cycle model
struct Cfg {
  string name;
  // front end
  int W = 4;            // fetch block bytes (4 = RTL)
  bool reuse = false;   // keep the block for later parcels (RTL: no)
  int qcap = 1;         // fetch blocks held (RTL: 1, ifw)
  bool prefetch = false;  // request the next sequential block ahead of use
  int ilat = 1;         // I$ hit: response ilat cycles after accept (RTL 1, SRAM_OREG 2)
  bool ib2b = false;    // I$ accepts again the cycle after accept (pipelined)
  int imiss = 12;       // I$ refill penalty
  // back end
  int dlat = 1;         // D$ hit: freeze cycles per access (RTL 1, SRAM_OREG 2)
  int dmiss = 12, dmiss_dirty = 30;
  int dsets = 64, dways = 4, isets = 64, iways = 2;
  // prediction (applied when an instruction is extracted into IF/ID)
  int dir = -1;         // -1 none (predict not taken, RTL); else Dir kind
  int dbits = 0, dh = 0;
  bool jal_pred = false;  // JAL / c.j taken at extraction (predecode)
  int ras = 0;          // RAS depth for returns (0: returns resolved in EX)
  int btb = 0, btbw = 1;  // BTB entries: if >0, branch/jal/jalr targets need a BTB hit (else predecode)
  bool btb_jalr = false;  // non-return JALR predicted from the BTB
  int redirect_extra = 0;  // extra bubbles after a correct predicted-taken redirect (e.g. ID-stage redirect)
  int fe_ext_redirect_lat = 1;  // cycles from extraction redirect to the first target request (1 = next cycle)
  bool oracle = false;  // perfect prediction of every control transfer at extraction
  int buf_lat = 0;      // 0: a fetched block is usable in its arrival cycle (bypass, RTL); 1: next cycle
  bool nostrad = false; // treat 32-bit instructions as never straddling (rv64g code estimate)
};
struct Res { i64 cycles = 0; u64 retired = 0, ic_acc = 0, flush = 0, mispred = 0, ldu = 0, strad = 0, icmiss = 0, dcmiss = 0, pred_taken = 0, memst = 0, hold = 0; };

static Res simulate(const Region& R, const Cfg& c, const Cache& iwarm, const Cache& dwarm) {
  const auto& v = R.ins;
  const i64 N = v.size();
  Res r;
  Cache ic = iwarm, dc = dwarm;
  Dir dir; if (c.dir >= 0 && c.dir < 5) dir.init(c.dir, c.dbits, c.dh);
  BTB btb; if (c.btb) btb.init(c.btb, c.btbw);
  RAS ras; ras.init(c.ras);
  const int W = c.W;
  // fetch unit state
  u64 fpc = v[0].pc;
  i64 fnext = 0; bool onpath = true;
  deque<pair<u64, i64>> q;  // (block address, cycle data valid)
  bool pend = false, pdrop = false; u64 paddr = 0; i64 pready = 0;
  i64 ic_free = 0;
  bool strad = false;   // straddle low parcel captured (RTL straddle_q)
  i64 redirect_hold = 0;  // no target request before this cycle (extraction redirect latency)
  // pipeline slots: index into v, -1 bubble, -2 wrong path
  i64 IFID = -1, IDEX = -1, EXMEM = -1, MEMWB = -1;
  i64 ex_start = -1, ex_hold_until = -1;
  i64 mem_start = -1, mem_done = -1;
  vector<uint8_t> mispred(N, 0);
  i64 t_begin = -1, t_end = -1;
  i64 t = 0;
  auto blk = [&](u64 a) { return a & ~(u64)(W - 1); };
  auto have = [&](u64 a, i64 now) {  // block containing a present in q with data valid
    for (auto& e : q) if (e.first == blk(a) && e.second <= now) return true;
    return false;
  };
  const i64 LIMIT = (i64)N * 80 + 100000;
  while (t < LIMIT) {
    // ---- start-of-cycle registered state for the request decision
    bool pend0 = pend; i64 pready0 = pready;
    size_t qsz0 = q.size();
    u64 fpc0 = fpc; bool strad0 = strad;
    // blocks held or in flight, and the address of the youngest one
    bool live0 = pend && !pdrop;
    size_t cnt0 = q.size() + (live0 ? 1 : 0);
    bool has_tail0 = live0 || !q.empty();
    u64 tail0 = live0 ? paddr : (!q.empty() ? q.back().first : 0);
    // ---- fetch response arrival
    if (pend && pready == t) {
      pend = false;
      if (!pdrop) q.push_back({paddr, t + c.buf_lat});
      pdrop = false;
    }
    // ---- back-end hazards for this cycle
    bool mem_stall = false;
    if (EXMEM >= 0) {
      const Ins& m = v[EXMEM];
      bool memop = (m.d.cls == C_LOAD || m.d.cls == C_STORE || m.d.cls == C_AMO);
      if (memop) {
        if (mem_start < 0) {
          mem_start = t;
          int lat = c.dlat;
          if (m.maddr) {
            int k = dc.access(m.maddr, m.d.cls != C_LOAD);
            if (k) { r.dcmiss++; lat += (k == 2) ? c.dmiss_dirty : c.dmiss; }
          }
          mem_done = t + lat;
        }
        mem_stall = (t < mem_done);
      }
    }
    if (mem_stall) r.memst++;
    bool ex_hold = false;
    if (IDEX >= 0) {
      if (ex_start < 0) { ex_start = t; ex_hold_until = t + v[IDEX].hold; }
      ex_hold = (t < ex_hold_until);
    }
    if (ex_hold) r.hold++;
    bool stall = false;
    if (!ex_hold && IDEX >= 0 && IFID >= 0) {
      const Ins& e = v[IDEX];
      const Ins& d = v[IFID];
      if (e.d.cls == C_LOAD || e.d.cls == C_AMO) {
        if (!e.d.rd_fp) stall = (e.d.rd != 0) && ((d.d.u1 && d.d.rs1 == e.d.rd) || (d.d.u2 && d.d.rs2 == e.d.rd));
        else stall = (d.d.f1 && d.d.rs1 == e.d.rd) || (d.d.f2 && d.d.rs2 == e.d.rd) || (d.d.f3 && d.d.rs3 == e.d.rd);
      }
    }
    bool flush = false; u64 ftarget = 0;
    if (IDEX >= 0 && !ex_hold && mispred[IDEX]) { flush = true; ftarget = v[IDEX].npc; }
    bool upd = !mem_stall;
    // window bookkeeping: marker CSR write commits when it leaves EX
    if (upd && !ex_hold && IDEX == 0 && t_begin < 0) t_begin = t;
    if (upd && !ex_hold && IDEX == N - 1 && t_end < 0) { t_end = t; break; }
    if (upd && MEMWB >= 0 && t_begin >= 0) r.retired++;
    // ---- IF extraction
    bool if_consume = upd && !ex_hold && !stall && !flush;
    i64 deliver = -1;  // -1 bubble
    bool delivered = false, ext_redirect = false;
    if (if_consume) {
      if (strad) {
        if (have(fpc + 2, t)) {
          delivered = true; strad = false;
        }
      } else if (have(fpc, t)) {
        uint32_t insn = 0; bool ok = fetch_insn(fpc, insn);
        int len = (!ok || (insn & 3) == 3) ? 4 : 2;
        bool spans = (len == 4) && (blk(fpc) != blk(fpc + 2)) && !c.nostrad;
        if (!spans) delivered = true;
        else if (have(fpc + 2, t)) delivered = true;
        else if ((int)q.size() >= c.qcap || !c.reuse) {
          // straddle_enter: capture the low parcel, free the buffer
          strad = true; r.strad++;
          q.clear();
        }
      }
      if (delivered) {
        uint32_t insn = 0; fetch_insn(fpc, insn);
        int len = ((insn & 3) == 3) ? 4 : 2;
        u64 pnext = fpc + len;
        if (onpath && fnext < N && v[fnext].pc == fpc) {
          const Ins& in = v[fnext];
          // prediction at extraction
          u64 pred = fpc + len;
          bool predicted = false;
          if (in.d.cls == C_BR && c.dir >= 0 && !c.oracle) {
            bool tk = dir.pred(in.pc, in.d.imm);
            if (tk) {
              u64 tg;
              if (c.btb) { if (btb.look(in.pc, tg)) { pred = tg; predicted = true; } }
              else { pred = in.pc + in.d.imm; predicted = true; }
            }
            dir.upd(in.pc, in.taken());
          } else if (in.d.cls == C_JAL && c.jal_pred) {
            u64 tg;
            if (c.btb) { if (btb.look(in.pc, tg)) { pred = tg; predicted = true; } }
            else { pred = in.pc + in.d.imm; predicted = true; }
          } else if (in.d.cls == C_JALR) {
            u64 a;
            if (is_ret(in) && c.ras) { if (ras.pop(a)) { pred = a; predicted = true; } }
            else if (c.btb_jalr && c.btb) { u64 tg; if (btb.look(in.pc, tg)) { pred = tg; predicted = true; } }
          }
          if (is_call(in) && c.ras) ras.push(in.pc + len);
          if (c.btb && in.taken() && (in.d.cls == C_BR || in.d.cls == C_JAL || (in.d.cls == C_JALR && !is_ret(in))))
            btb.ins(in.pc, in.npc);
          if (c.oracle) { pred = in.npc; predicted = (pred != fpc + len); }
          if (pred != in.npc) { mispred[fnext] = 1; r.mispred++; onpath = false; }
          if (predicted && pred != fpc + len) r.pred_taken++;
          deliver = fnext; fnext++;
          pnext = pred;
        } else {
          deliver = -2;  // wrong path
          onpath = false;
        }
        // advance fetch pc; drop consumed / redirected blocks
        if (pnext != fpc + len) {
          ext_redirect = true;
          q.clear(); strad = false;
          if (pend) pdrop = true;
          redirect_hold = t + c.fe_ext_redirect_lat + c.redirect_extra;
        } else if (!c.reuse) {
          q.clear();
        } else {
          while (!q.empty() && q.front().first + W <= pnext) q.pop_front();
        }
        fpc = pnext;
      }
    }
    // ---- fetch request (decided from start-of-cycle state, like the RTL)
    {
      bool can = (t >= ic_free) && (!pend0 || (c.ib2b && pready0 == t)) && (t >= redirect_hold);
      u64 want = 0; bool need = false;
      if (can) {
        u64 head = strad0 ? blk(fpc0 + 2) : blk(fpc0);
        if (c.prefetch) {
          if (cnt0 < (size_t)c.qcap) { want = has_tail0 ? tail0 + W : head; need = true; }
        } else {
          if (cnt0 == 0) { want = head; need = true; }
          else if (c.reuse && cnt0 < (size_t)c.qcap && !live0) {
            // straddle completion: the instruction at fpc needs the next block
            uint32_t insn = 0;
            if (fetch_insn(fpc0, insn) && (insn & 3) == 3 && blk(fpc0) != blk(fpc0 + 2) && !c.nostrad &&
                tail0 == blk(fpc0)) { want = blk(fpc0 + 2); need = true; }
          }
        }
      }
      // the RTL computes the request from the registered pc; a redirect or
      // consumption this cycle makes it stale (dropped below)
      if (need) {
        pend = true; paddr = want; pdrop = false;
        int lat = c.ilat;
        if (ic.access(want, false)) { r.icmiss++; lat += c.imiss; }
        pready = t + lat;
        ic_free = c.ib2b ? t + 1 : t + lat + 1;
        if (t_begin >= 0) r.ic_acc++;
        // stale if this cycle redirected (EX flush or an extraction redirect)
        if (flush && upd) pdrop = true;
        else if (ext_redirect) pdrop = true;
      }
    }
    // ---- pipeline advance
    if (upd) {
      MEMWB = EXMEM;
      mem_start = -1;
      if (ex_hold) { EXMEM = -1; }
      else {
        EXMEM = (IDEX >= 0) ? IDEX : -1;
        if (stall || flush) IDEX = -1;
        else IDEX = (IFID >= 0) ? IFID : -1;
        ex_start = -1;
      }
      if (flush) {
        IFID = -1;
        r.flush++;
        // redirect
        fpc = ftarget; strad = false; q.clear();
        if (pend) pdrop = true;
        i64 k = EXMEM;  // the redirecting instruction just moved to EX/MEM
        fnext = k + 1; onpath = true;
        redirect_hold = 0;
      } else if (!stall && !ex_hold) {
        IFID = delivered ? deliver : -1;
        if (IFID == -2) IFID = -3;  // wrong-path slot (never executes)
      }
      if (IFID < -1) IFID = -1;  // wrong-path instructions are bubbles for the back end
    }
    t++;
  }
  r.cycles = (t_begin >= 0 && t_end >= 0) ? t_end - t_begin : -1;
  return r;
}

// ----------------------------------------------------------------- main
int main(int argc, char** argv) {
  if (argc < 2) { fprintf(stderr, "usage: fe <elf> [regions-to-model,comma] < spike-commit-log\n"); return 1; }
  img.load(argv[1]);
  set<int> model_regions; bool model_all = true;
  if (argc > 2 && strcmp(argv[2], "all")) {
    model_all = false;
    string s = argv[2]; stringstream ss(s); string tok;
    while (getline(ss, tok, ',')) if (!tok.empty() && isdigit(tok[0])) model_regions.insert(stoi(tok));
  }
  bool sky = (argc > 3 && !strcmp(argv[3], "sky130"));
  u64 xr[32] = {0};
  static char line[1 << 20];
  Region cur; bool in = false;
  Ins prev; bool have_prev = false; bool prev_in = false;
  Cache iwarm, dwarm, isnap, dsnap;
  if (sky) { iwarm.init(64, 1, 64); dwarm.init(64, 1, 64); }
  else { iwarm.init(64, 2, 64); dwarm.init(64, 4, 64); }
  vector<Cfg> cfgs;
  {
    Cfg base; base.name = "F0_rtl";
    if (sky) { base.ilat = 2; base.dlat = 2; base.imiss = 13; base.dmiss = 12; base.dmiss_dirty = 31; base.iways = 1; base.dways = 1; }
    else { base.dmiss = 11; base.dmiss_dirty = 29; }
    auto add = [&](Cfg c) { cfgs.push_back(c); };
    auto bp = [&](Cfg c, const string& p) {  // apply a prediction scheme
      c.jal_pred = true;
      if (p == "jal") { c.jal_pred = true; }
      else if (p == "btfn") { c.dir = 1; c.ras = 4; }
      else if (p.rfind("bim", 0) == 0) { c.dir = 2; c.dbits = __builtin_ctz(stoi(p.substr(3))); c.ras = 4; }
      else if (p.rfind("gsh", 0) == 0) { c.dir = 3; c.dbits = stoi(p.substr(3)); c.dh = c.dbits; c.ras = 4; }
      else if (p == "perfect") { c.dir = 99; }
      return c;
    };
    auto F = [&](const string& f) {
      Cfg c = base;
      if (f == "F0") {}
      else if (f == "F0ns") { c.nostrad = true; }
      else if (f == "F1") { c.reuse = true; }
      else if (f == "F2") { c.W = 8; c.reuse = true; c.qcap = 2; }
      else if (f == "F2s") { c.W = 8; c.reuse = true; c.qcap = 2; c.buf_lat = 1; }
      else if (f == "F3") { c.W = 8; c.reuse = true; c.qcap = 2; c.prefetch = true; }
      else if (f == "F3s") { c.W = 8; c.reuse = true; c.qcap = 2; c.prefetch = true; c.buf_lat = 1; }
      else if (f == "F3w16") { c.W = 16; c.reuse = true; c.qcap = 2; c.prefetch = true; }
      else if (f == "F3w16s") { c.W = 16; c.reuse = true; c.qcap = 2; c.prefetch = true; c.buf_lat = 1; }
      else if (f == "F4") { c.W = 8; c.reuse = true; c.qcap = 3; c.prefetch = true; c.ib2b = true; }
      else if (f == "F4w4") { c.W = 4; c.reuse = true; c.qcap = 3; c.prefetch = true; c.ib2b = true; }
      else if (f == "F3w4") { c.W = 4; c.reuse = true; c.qcap = 2; c.prefetch = true; }
      else if (f == "F3q3") { c.W = 8; c.reuse = true; c.qcap = 3; c.prefetch = true; }
      else if (f == "F5") { c.W = 64; c.reuse = true; c.qcap = 4; c.prefetch = true; c.ib2b = true; }
      c.name = f;
      return c;
    };
    add(base);
    for (string f : {"F0ns", "F1", "F2", "F2s", "F3", "F3s", "F3q3", "F3w16", "F3w16s", "F4", "F4w4", "F5"}) add(F(f));
    for (string f : {"F0", "F1", "F2", "F2s", "F3", "F3s", "F3w4", "F3w16s", "F4", "F4w4", "F5"}) {
      for (string p : {"jal", "btfn", "bim16", "bim32", "bim64", "bim256", "gsh12", "perfect"}) {
        Cfg c = bp(F(f), p); c.name = f + "+" + p; add(c);
        if (p != "perfect" && (f == "F0" || f == "F1" || f == "F2s" || f == "F3" || f == "F3s" || f == "F3w16s" || f == "F4")) {
          Cfg d = c; d.redirect_extra = 1; d.name = c.name + "+r1"; add(d);
        }
      }
    }
    { Cfg c = bp(F("F0"), "bim64"); c.btb = 64; c.name = "F0+bim64+btb64"; add(c); }
    { Cfg c = bp(F("F3s"), "bim64"); c.btb = 64; c.btb_jalr = true; c.name = "F3s+bim64+btb64j"; add(c); }
  }
  auto finish = [&](Region& R) {
    printf("== region %d\n", R.id);
    stats(R, stdout);
    if (model_all || model_regions.count(R.id)) {
      for (auto& c : cfgs) {
        Cfg cc = c;
        Region* RR = &R;
        Region perfect;
        // perfect prediction: mark nothing mispredicted via an oracle direction
        Res res;
        if (cc.dir == 99) { cc.oracle = true; cc.dir = -1; }
        res = simulate(*RR, cc, isnap, dsnap);
        printf("model.%s cycles=%ld retired=%lu ic_acc=%lu flush=%lu mispred=%lu strad=%lu icmiss=%lu dcmiss=%lu pred_taken=%lu memst=%lu hold=%lu\n",
               cc.name.c_str(), res.cycles, res.retired, res.ic_acc, res.flush, res.mispred, res.strad, res.icmiss, res.dcmiss, res.pred_taken, res.memst, res.hold);
        fflush(stdout);
      }
    }
    fflush(stdout);
  };
  u64 nlines = 0;
  auto clz64 = [](u64 x) { return x ? __builtin_clzll(x) : 64; };
  while (fgets(line, sizeof line, stdin)) {
    nlines++;
    char* p = strstr(line, ": ");
    if (strncmp(line, "core", 4) || !p) continue;
    p += 2;
    if (!isdigit(*p)) continue;   // exception lines etc.
    char* q2 = strstr(p, " 0x");
    if (!q2) continue;
    u64 pc = strtoull(q2 + 1, &p, 16);
    char* lp = strchr(p, '(');
    if (!lp) continue;
    uint32_t insn = (uint32_t)strtoull(lp + 1, &p, 16);
    p = strchr(p, ')');
    if (!p) continue;
    p++;
    if (insn == 0x10500073u) break;  // wfi: sigil_halt
    Ins I; I.pc = pc; I.insn = insn; I.npc = 0; I.maddr = 0; I.d = decode(insn); I.hold = 0;
    // operand values before this instruction's own write
    u64 a = xr[(insn >> 15) & 31], b = xr[(insn >> 20) & 31];
    if ((insn & 3) != 3) { a = xr[I.d.rs1]; b = xr[I.d.rs2]; }
    if (I.d.cls == C_MUL) I.hold = 2;
    if (I.d.cls == C_DIV) {
      bool sgn = I.d.is_div_sign;
      u64 A = a, B = b;
      if (I.d.w) { A = sgn ? (u64)(i64)(int32_t)A : (uint32_t)A; B = sgn ? (u64)(i64)(int32_t)B : (uint32_t)B; }
      bool special = (B == 0) || (sgn && ((I.d.w && (i64)A == INT32_MIN) || (!I.d.w && (i64)A == INT64_MIN)) && (i64)B == -1);
      if (special) I.hold = 1;
      else {
        u64 ma = (sgn && (i64)A < 0) ? (u64)(-(i64)A) : A, mb = (sgn && (i64)B < 0) ? (u64)(-(i64)B) : B;
        int dd = clz64(mb) - clz64(ma) + 1;
        int n = dd <= 0 ? 0 : (dd + 1) / 2;
        I.hold = 2 + n;
      }
    }
    if (I.d.cls == C_FP) I.hold = I.d.fplat;
    // write records
    u64 maddr = 0; bool got_mem = false;
    {
      char* s = p;
      while (*s) {
        while (*s == ' ') s++;
        if (!*s || *s == '\n') break;
        char* e = s; while (*e && *e != ' ' && *e != '\n') e++;
        if (s[0] == 'x' && isdigit(s[1]) && e - s <= 3) {
          int r = atoi(s + 1);
          char* vs = e; while (*vs == ' ') vs++;
          u64 val = strtoull(vs, &e, 16);
          if (r > 0 && r < 32) xr[r] = val;
        } else if (e - s == 3 && !strncmp(s, "mem", 3) && !got_mem) {
          char* vs = e; while (*vs == ' ') vs++;
          maddr = strtoull(vs, &e, 16); got_mem = true;
        }
        s = e;
      }
    }
    I.maddr = maddr;
    // complete previous record's npc
    if (have_prev) {
      prev.npc = pc;
      if (prev_in) cur.ins.push_back(prev);
    }
    // marker?
    bool marker = ((insn & 0xfff07fffu) == 0x33f01073u);
    if (marker) {
      u64 val = a;
      if ((val >> 16) == 0x5045) {
        int rid = (val >> 8) & 0xff, kind = val & 0xff;
        if (kind == 1) { cur = Region(); cur.id = rid; in = true; isnap = iwarm; dsnap = dwarm; }
        else if (kind == 2 && in) {
          // the end marker is the last modelled instruction
          I.npc = pc + 4; cur.ins.push_back(I);
          in = false; have_prev = false;
          finish(cur);
          cur = Region();
          continue;
        }
      }
    }
    // functional cache warm-up (whole program; models start from the snapshot at the begin marker)
    iwarm.access(pc, false);
    if (maddr && (I.d.cls == C_LOAD || I.d.cls == C_STORE || I.d.cls == C_AMO)) dwarm.access(maddr, I.d.cls != C_LOAD);
    prev = I; have_prev = true; prev_in = in;
  }
  fprintf(stderr, "lines=%lu\n", nlines);
  return 0;
}
