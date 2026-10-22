# Berkeley TestFloat flows

Two flows live here. The in-house FPU flows (below) are the ones that
back claims about Sigil's own core; the CVA6 checkers are the
historical characterization of the third-party cvfpu.

## In-house FPU (`rtl/core/sigil_fpu.sv`)

- Level 1, every F/D operation TestFloat covers (36 functions) in all
  five rounding modes: `scripts/testfloat_fpu_vectors.sh` runs
  `testfloat_gen` vectors through the FPU unit TB
  (`tb/cpp/fpu_tb.cpp --testfloat`), comparing result bits and all
  five exception flags (evidence: `docs/evidence/README.md`, "Multi-cycle
  synthesizable FPU", 64,648,560 vectors).
- Level 2, `f32_mulAdd`/`f64_mulAdd` (issue #20):
  `scripts/testfloat_fpu_l2.sh` with the case generator
  `tf_l2_mulAdd.c`, which compiles TestFloat's own `genCases_f32.c`/
  `genCases_f64.c` and `random.c` (with a lock-free replica of glibc
  `rand()`) so the level-2 stream can be cut into independent chunks;
  `validate` checks its output byte-for-byte against `testfloat_gen`.
  The complete level-2 stream is 14,512,627,712 cases per rounding
  mode for f32 and 180,795,884,544 for f64; `STRIDE` keeps every
  S-th grid triple for a bounded f64 run, and `OP=rot` sends cases
  through fmadd/fmsub/fnmsub/fnmadd with sign-flipped operands so the
  expected value is still TestFloat's mulAdd result. Results:
  `docs/evidence/testfloat-l2-muladd-core-2026-10-22.csv`.
- `roundToInt` is not tested: it has no instruction without Zfa,
  which this configuration does not implement.

## CVA6 model checkers (historical)

Bare-metal checkers that execute Berkeley TestFloat level-1 vectors
(generated against SoftFloat with the RISCV specialization) on the
CVA6 FPU (cvfpu) via the Verilator testharness, comparing result
bits (NaN-canonicalized: any NaN matches any NaN) and accrued
exception flags exactly. Each ELF halts via HTIF `tohost` like
`riscv-tests`: pass writes 1; a result mismatch at case `i` writes
`2*(i+2)+1`, a flags mismatch writes `2*(i+1000002)+1`, and any
trap writes 3.

Files:

- `link.ld` — checker linker script (DRAM at `0x80000000`).
- `../../scripts/testfloat_cva6.py` — vector text to checker
  assembly (operations: `f32/f64` add/sub/mul/div/sqrt/mulAdd,
  rounding RNE, tininess-after as generated).
- `../../scripts/build_testfloat.sh` — builds `testfloat_gen`
  if needed, generates vectors and ELFs, stages them under
  `third_party/cva6/testfloat-elfs/`.

Run with the batch runner, for example:

```sh
./scripts/build_testfloat.sh
TIME_OUT=20000000 TEST_TIMEOUT_SEC=420 ELF_SUBDIR=testfloat-elfs \
  TEST_LISTS=testfloat RUN_NAME=tf-all ./scripts/cva6_docker.sh regression
```

Scope: single/double add, sub, mul, div, sqrt, and fused
multiply-add (`TEST_LISTS=testfloat`), plus float<->int and
f32<->f64 conversions and eq/le/lt comparisons
(`TEST_LISTS=testfloat-cvt`) at RNE, plus RTZ/RDN/RUP/RMM
arithmetic and conversions (`TEST_LISTS=testfloat-rm`,
built with `RMODE=<mode> scripts/build_testfloat.sh`).
Float->int checkers
mask the NX flag: TestFloat generates those vectors with
SoftFloat `exact=false` (expected flags never carry NX) while
RISC-V `fcvt` raises NX on inexact conversions. `roundToInt`
(no instruction without Zfa) is not applicable and level-2
density was not run on CVA6 (the in-house FPU flow above covers
level-2 mulAdd). The
upstream `berkeley-softfloat-3`/`berkeley-testfloat-3` trees live
uncommitted under `third_party/` (recorded commits in evidence).
