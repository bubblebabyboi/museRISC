/* Berkeley TestFloat level-2 mulAdd cases for the in-house FPU unit TB
 * (tb/cpp/fpu_tb.cpp --testfloat), issue #20.
 *
 * Reproduces the case stream of `testfloat_gen -level 2 -seed SEED
 * -r<mode> f32_mulAdd` (or f64_mulAdd) without running it serially, so
 * the stream can be split into independent chunks and optionally
 * decimated. This file #includes TestFloat's own genCases_f32.c /
 * genCases_f64.c and random.c, so operand pools and the random-operand
 * generators are TestFloat's code; expected results and flags come from
 * SoftFloat 3e (RISCV specialization, tininess after rounding) exactly
 * as in testfloat_gen. Build with -DTF_FMT=32 or -DTF_FMT=64.
 *
 * Level-2 three-operand stream (genCases_fXX_abc_next, level 2): case
 * 2r is the r-th random triple (three fXXRandom() calls), case 2r+1 is
 * grid triple r of (QIn x P2)^3 with the C index fastest:
 *   t = r -> (a, b, c) = (t / N^2, (t / N) % N, t % N),
 *   value(v) = QIn[v / NumP2] | P2[v % NumP2],  N = NumQIn * NumP2,
 * for 2 * N^3 cases in total (f32: N = 1936, 14,512,627,712 cases;
 * f64: N = 4488, 180,795,884,544 cases per rounding mode).
 *
 * rand() is replaced by a lock-free replica of glibc's random() TYPE_3
 * generator (srand/rand semantics) so chunks can start from saved
 * generator states; `raw` mode output is byte-identical to
 * testfloat_gen (checked by scripts/testfloat_fpu_l2.sh validate).
 *
 * Usage:
 *   tf_l2_mulAdd raw  RM SEED LO HI STRIDE [CKPT]      TestFloat lines
 *   tf_l2_mulAdd tb   RM SEED LO HI STRIDE OP [CKPT]   fpu_tb lines
 *   tf_l2_mulAdd ckpt SEED STEP COUNT                  generator states
 *   tf_l2_mulAdd info STRIDE                           pair count
 * RM: 0 RNE, 1 RTZ, 2 RDN, 3 RUP, 4 RMM. Pairs r in [LO, HI) are
 * emitted: random triple r, then grid triple r*STRIDE (STRIDE 1 = the
 * full stream; STRIDE S > 1 keeps every S-th grid triple and the first
 * ceil(N^3/S) random triples). OP: fma | fms | fnms | fnma | rot; the
 * three negated forms flip operand signs so the expected value stays
 * TestFloat's mulAdd result (fmsub(a,b,-c), fnmsub(-a,b,c),
 * fnmadd(-a,b,-c), as SoftFloat/Spike define them); rot cycles the
 * four opcodes over pair index (random triple r: r % 4, grid triple r:
 * (r + 2) % 4), independent of chunking. CKPT: file from `ckpt`; the
 * nearest saved state at or before LO is used instead of walking from 0.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- glibc random() TYPE_3 replica (rand/srand) ---------------------- */
static uint32_t rs[31];
static int rf, rr;

static inline int tf_rand(void) {
  uint32_t v = rs[rf] += rs[rr];
  if (++rf >= 31) {
    rf = 0;
    ++rr;
  } else if (++rr >= 31) {
    rr = 0;
  }
  return (int)(v >> 1);
}

static void tf_srand(unsigned seed) {
  int32_t word;
  if (seed == 0) seed = 1;
  rs[0] = seed;
  word = (int32_t)seed;
  for (int i = 1; i < 31; i++) {
    long hi = word / 127773, lo = word % 127773;
    word = (int32_t)(16807 * lo - 2836 * hi);
    if (word < 0) word += 2147483647;
    rs[i] = (uint32_t)word;
  }
  rf = 3;
  rr = 0;
  for (int i = 0; i < 310; i++) (void)tf_rand();
}

#define rand tf_rand
#include "random.c"
#undef rand

#include "softfloat.h"
#include "genCases.h"
int genCases_level = 2;
uint_fast64_t genCases_total;
bool genCases_done;

#if TF_FMT == 32
#include "genCases_f32.c"
typedef float32_t ft;
#define NQ f32NumQIn
#define NP f32NumP2
#define QIN f32QIn
#define P2 f32P2
#define RANDOM() f32Random()
#define BITS(x) ((uint64_t)(x).v)
#define MULADD(a, b, c) f32_mulAdd(a, b, c)
#define HEXW 8
#define SIGN (1ULL << 31)
#define BOX(v) (0xFFFFFFFF00000000ULL | (v))
#define MK(v) ((float32_t){(uint32_t)(v)})
#elif TF_FMT == 64
#include "genCases_f64.c"
typedef float64_t ft;
#define NQ f64NumQIn
#define NP f64NumP2
#define QIN f64QIn
#define P2 f64P2
#define RANDOM() f64Random()
#define BITS(x) ((uint64_t)(x).v)
#define MULADD(a, b, c) f64_mulAdd(a, b, c)
#define HEXW 16
#define SIGN (1ULL << 63)
#define BOX(v) (v)
#define MK(v) ((float64_t){(uint64_t)(v)})
#else
#error "build with -DTF_FMT=32 or -DTF_FMT=64"
#endif

static const uint64_t kN = (uint64_t)NQ * NP;

static inline uint64_t grid_value(uint64_t v) {
  return (uint64_t)QIN[v / NP] | (uint64_t)P2[v % NP];
}

/* ---- buffered output ------------------------------------------------- */
static char obuf[1 << 20];
static size_t olen;
static void oflush(void) {
  if (olen && fwrite(obuf, 1, olen, stdout) != olen) exit(3);
  olen = 0;
}
static inline void ohex(uint64_t v, int width, bool upper, char sep) {
  static const char lo[] = "0123456789abcdef", up[] = "0123456789ABCDEF";
  const char* d = upper ? up : lo;
  char tmp[16];
  int n = 0;
  if (width > 0) {
    for (int i = width - 1; i >= 0; i--) obuf[olen++] = d[(v >> (4 * i)) & 0xF];
  } else { /* minimal lowercase, as Python's format(v, "x") */
    do { tmp[n++] = d[v & 0xF]; v >>= 4; } while (v);
    while (n) obuf[olen++] = tmp[--n];
  }
  obuf[olen++] = sep;
}
static inline void ouint(unsigned v, char sep) {
  char tmp[12];
  int n = 0;
  do { tmp[n++] = (char)('0' + v % 10); v /= 10; } while (v);
  while (n) obuf[olen++] = tmp[--n];
  obuf[olen++] = sep;
}

static int mode_raw, op_sel, rmode;
static uint64_t emitted;

static void emit(uint64_t gcase, uint64_t a, uint64_t b, uint64_t c) {
  softfloat_exceptionFlags = 0;
  const ft z = MULADD(MK(a), MK(b), MK(c));
  const unsigned fl = softfloat_exceptionFlags;
  if (olen > sizeof obuf - 256) oflush();
  if (mode_raw) {
    ohex(a, HEXW, true, ' ');
    ohex(b, HEXW, true, ' ');
    ohex(c, HEXW, true, ' ');
    ohex(BITS(z), HEXW, true, ' ');
    ohex(fl, 2, true, '\n');
  } else {
    /* fpu_tb opcodes: 12 fmadd, 13 fmsub, 14 fnmsub, 15 fnmadd */
    /* rot: random triple r -> opcode r % 4, grid triple r -> (r + 2) % 4,
     * so both halves of the stream reach all four opcodes */
    const int op = op_sel == 4
                       ? 12 + (int)(((gcase >> 1) + 2 * (gcase & 1)) & 3)
                       : 12 + op_sel;
    uint64_t xa = a, xc = c;
    if (op == 14 || op == 15) xa ^= SIGN; /* fnm*: core negates a */
    if (op == 13 || op == 15) xc ^= SIGN; /* *sub: core negates c */
    ouint((unsigned)op, ' ');
    ouint(TF_FMT == 64, ' ');
    ouint((unsigned)rmode, ' ');
    ouint(0, ' ');
    ohex(BOX(xa), 0, false, ' ');
    ohex(BOX(b), 0, false, ' ');
    ohex(BOX(xc), 0, false, ' ');
    ohex(BOX(BITS(z)), 0, false, ' ');
    ohex(fl, 0, false, '\n');
  }
  emitted++;
}

static inline void random_triple(uint64_t* a, uint64_t* b, uint64_t* c) {
  /* same call order as genCases_fXX_abc_next level 2, subcase 0 */
  ft x = RANDOM();
  ft y = RANDOM();
  ft w = RANDOM();
  *a = BITS(x);
  *b = BITS(y);
  *c = BITS(w);
}

static void skip_random(uint64_t from, uint64_t to) {
  uint64_t a, b, c;
  for (uint64_t r = from; r < to; r++) random_triple(&a, &b, &c);
}

/* Restore the generator state saved for the largest index <= lo. */
static uint64_t load_ckpt(const char* path, unsigned seed, uint64_t lo) {
  FILE* f = fopen(path, "r");
  if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(2); }
  char line[1024];
  uint64_t best = 0;
  bool found = false;
  while (fgets(line, sizeof line, f)) {
    unsigned s;
    unsigned long long idx;
    int n = 0;
    if (sscanf(line, "%u %llu%n", &s, &idx, &n) != 2 || s != seed) continue;
    if (idx > lo || (found && idx < best)) continue;
    const char* p = line + n;
    uint32_t st[31];
    int f_, r_, k = 0;
    for (; k < 31; k++) {
      char* e;
      st[k] = (uint32_t)strtoul(p, &e, 16);
      if (e == p) break;
      p = e;
    }
    if (k != 31 || sscanf(p, "%d %d", &f_, &r_) != 2) continue;
    memcpy(rs, st, sizeof rs);
    rf = f_;
    rr = r_;
    best = idx;
    found = true;
  }
  fclose(f);
  if (!found) {
    tf_srand(seed);
    return 0;
  }
  return best;
}

static uint64_t pairs_for(uint64_t stride) {
  const uint64_t n3 = kN * kN * kN;
  return (n3 + stride - 1) / stride;
}

int main(int argc, char** argv) {
  softfloat_detectTininess = softfloat_tininess_afterRounding;
  if (argc >= 3 && !strcmp(argv[1], "info")) {
    const uint64_t stride = strtoull(argv[2], NULL, 0);
    printf("fmt f%d N %llu grid %llu stride %llu pairs %llu cases %llu\n",
           TF_FMT, (unsigned long long)kN,
           (unsigned long long)(kN * kN * kN), (unsigned long long)stride,
           (unsigned long long)pairs_for(stride),
           (unsigned long long)(2 * pairs_for(stride)));
    return 0;
  }
  if (argc >= 5 && !strcmp(argv[1], "ckpt")) {
    const unsigned seed = (unsigned)strtoul(argv[2], NULL, 0);
    const uint64_t step = strtoull(argv[3], NULL, 0);
    const uint64_t count = strtoull(argv[4], NULL, 0);
    tf_srand(seed);
    for (uint64_t k = 0; k < count; k++) {
      if (k) skip_random((k - 1) * step, k * step);
      printf("%u %llu", seed, (unsigned long long)(k * step));
      for (int i = 0; i < 31; i++) printf(" %08x", rs[i]);
      printf(" %d %d\n", rf, rr);
      fflush(stdout);
    }
    return 0;
  }
  const bool is_raw = argc >= 7 && !strcmp(argv[1], "raw");
  const bool is_tb = argc >= 8 && !strcmp(argv[1], "tb");
  if (!is_raw && !is_tb) {
    fprintf(stderr,
            "usage: %s raw RM SEED LO HI STRIDE [CKPT]\n"
            "       %s tb RM SEED LO HI STRIDE fma|fms|fnms|fnma|rot [CKPT]\n"
            "       %s ckpt SEED STEP COUNT | info STRIDE\n",
            argv[0], argv[0], argv[0]);
    return 2;
  }
  mode_raw = is_raw;
  rmode = atoi(argv[2]);
  if (rmode < 0 || rmode > 4) { fprintf(stderr, "bad RM\n"); return 2; }
  const unsigned seed = (unsigned)strtoul(argv[3], NULL, 0);
  uint64_t lo = strtoull(argv[4], NULL, 0);
  uint64_t hi = strtoull(argv[5], NULL, 0);
  const uint64_t stride = strtoull(argv[6], NULL, 0);
  const char* ckpt = NULL;
  if (is_tb) {
    static const char* ops[] = {"fma", "fms", "fnms", "fnma", "rot"};
    op_sel = -1;
    for (int i = 0; i < 5; i++)
      if (!strcmp(argv[7], ops[i])) op_sel = i;
    if (op_sel < 0) { fprintf(stderr, "bad OP\n"); return 2; }
    if (argc >= 9) ckpt = argv[8];
  } else if (argc >= 8) {
    ckpt = argv[7];
  }
  if (stride == 0) { fprintf(stderr, "bad STRIDE\n"); return 2; }
  const uint64_t npairs = pairs_for(stride);
  if (hi > npairs) hi = npairs;
  static const uint8_t mode_map[5] = {
      softfloat_round_near_even, softfloat_round_minMag, softfloat_round_min,
      softfloat_round_max, softfloat_round_near_maxMag};
  softfloat_roundingMode = mode_map[rmode];

  uint64_t at = 0;
  if (ckpt) at = load_ckpt(ckpt, seed, lo);
  else tf_srand(seed);
  skip_random(at, lo);
  for (uint64_t r = lo; r < hi; r++) {
    uint64_t a, b, c;
    random_triple(&a, &b, &c);
    emit(2 * r, a, b, c);
    const uint64_t t = r * stride;
    emit(2 * r + 1, grid_value(t / (kN * kN)), grid_value((t / kN) % kN),
         grid_value(t % kN));
  }
  oflush();
  fflush(stdout);
  fprintf(stderr, "tf_l2_mulAdd f%d rm %d seed %u pairs [%llu,%llu) stride %llu emitted %llu\n",
          TF_FMT, rmode, seed, (unsigned long long)lo, (unsigned long long)hi,
          (unsigned long long)stride, (unsigned long long)emitted);
  return 0;
}
