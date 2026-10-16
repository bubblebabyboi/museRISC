# Evidence

Committed, reproducible evidence for completed gates. A claim in
`docs/COMPLIANCE.md` should point here (or to a GitHub Actions run).

## B1 — CVA6 host smoke (2026-10-12)

- Artifact: [`b1-cva6-2026-10-12.log`](b1-cva6-2026-10-12.log) (extract of the full local Docker log)
- Command: `./scripts/cva6_docker.sh rv64ui-p-add-verilator rv64ui-p-simple-verilator`
- Result: exit 0; both tests report `*** SUCCESS *** (tohost = 0)`
  (`rv64ui-p-add` after 35,837 cycles; `rv64ui-p-simple` after 35,909 cycles)
- Configuration: CVA6 `81245a47fad8fe1a5d562d953ef2662e099def76`,
  Makefile default target `cv64a6_imafdc_sv39`, Verilator 5.008 (CVA6 pin
  with its v5 patch), tandem Spike fork bundled in core-v-verif,
  riscv-tests `eeacd550` physical (`-p-`) tests only
- Caveat: this is a **smoke gate**, not RV64GCV compliance. Full
  regression and ACT4 on the model are tracked by issue #2.

## Spike solo smoke on the B1 ELFs (2026-10-12, B2.1 start)

- Artifact: [`spike-solo-b1-elfs-2026-10-12.log`](spike-solo-b1-elfs-2026-10-12.log)
- Command: `./scripts/spike_solo.sh`
- Result: both B1 ELFs exit 0 on the standalone tandem-Spike binary
  (Spike 1.1.1-dev `b3149ab`)
- Caveat: the first run used Spike defaults (`RV64IMAFDC_zicntr_zihpm`,
  `PMP Regions 0`), **not** a config matched to
  `cv64a6_imafdc_sv39`. It validates the ELFs and the oracle only;
  matched-config solo and `SPIKE_TANDEM` lockstep comparison are
  B2 tasks in issue #2.
- Matched-profile rerun: `spike-solo-matched-b1-elfs-2026-10-12.log`
  (`SPIKE_PROFILE=matched`) — both ELFs exit 0 with ISA
  `RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr_zicntr`, privilege `MSU`,
  and PMP max/writable 64/8. Remaining config gaps are tracked in
  `docs/SPIKE_CONFIG.md`; this is still a two-test smoke, not B2.

## B2 batch regression runner smoke (2026-10-12)

- Artifact: [`b2-batch-runner-smoke-2026-10-12.csv`](b2-batch-runner-smoke-2026-10-12.csv)
- Command: `TESTS="rv64ui-p-add rv64ui-p-simple" RUN_NAME=solo-smoke ./scripts/cva6_docker.sh regression`
- Result: exit 0; CSV records both tests `PASS` in solo mode with
  cycle counts 35,837 / 35,909 — identical to the B1 gate above,
  now produced by the batch matrix runner (`results.csv` +
  `summary.txt` under `build/regression/<RUN_NAME>/`, per-test logs
  alongside). Tandem mode (`SPIKE_TANDEM=1`) uses a separate
  Verilator library (`work-ver-tandem`) so solo evidence is never
  overwritten.
- Caveat: runner validation on two tests only. Full directed lists
  are B2.2; tandem lockstep is B2.3 (issue #2).

## B2.0 config freeze + B2.1 Spike-solo directed baseline (2026-10-12)

- Artifact: [`spike-solo-matched-full-2026-10-12.log`](spike-solo-matched-full-2026-10-12.log)
- Command: `SPIKE_PROFILE=matched ./scripts/spike_solo.sh <174 tests from ci/riscv-{asm,amo,mul}-tests.list>`
  (ELFs built by `TEST_LISTS=asm,amo,mul ./scripts/cva6_docker.sh`;
  the `-v-` virtual-memory variants build via picolibc headers —
  see `C_INCLUDE_PATH` in `scripts/cva6_docker.sh`)
- Result: exit 0, **174/174 PASS** (96 `rv64ui`, 26 `rv64um`,
  38 `rv64ua`, 6 `rv64si`, 7 `rv64mi`, 1 `rv64uc`; 92 `-p-` + 82 `-v-`)
  under ISA `RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr_zicntr_zihpm_zicond_zkn_svnapot`,
  `--priv=MSU`, PMP max/writable 64/8.
- B2.0 freeze: `docs/SPIKE_CONFIG.md` records the source audit —
  tandem struct fields (Zicsr/PMP/modes) are set by
  `cva6pkg_to_core_cntrl_cfg`, `ext_zicntr_supported=0` is
  deliberate, the `64'h0x10000` boot literal resolves to `0x10000`
  under Verilator, and Zicond/ZKN-in-tandem, PMP granularity,
  Svnapot and debug triggers are waived **for these lists only**
  with reasons.
- Caveat: Spike passing says the ELFs and oracle agree with the
  RISC-V spec as Spike models it. It is **not** evidence about
  CVA6. The same lists on the CVA6 model are B2.2 (solo) and
  B2.3 (tandem lockstep), issue #2.

## B2.2 — CVA6 solo directed regression (2026-10-12)

- Artifact: [`b2-cva6-solo-2026-10-12.csv`](b2-cva6-solo-2026-10-12.csv)
  (174-row merged matrix in directed-list order)
- Command (single-run reproduce):
  `TEST_LISTS=asm,amo,mul RUN_NAME=solo-full ./scripts/cva6_docker.sh regression`
- Result: **174/174 PASS** (96 `rv64ui`, 26 `rv64um`, 38 `rv64ua`,
  6 `rv64si`, 7 `rv64mi`, 1 `rv64uc`; 92 `-p-` + 82 `-v-`), each
  `*** SUCCESS *** (tohost = 0)`, 0 fail/timeout/mismatch, on
  CVA6 `81245a47` target `cv64a6_imafdc_sv39`, Verilator 5.008,
  riscv-tests `eeacd550`, solo mode (no tandem compare).
- Assembly note: host/Docker crashes interrupted the first two
  attempts, so the matrix merges the preserved partial runs in
  list order — `solo-full` 32 rows, `solo-full-resume` 21 rows,
  `solo-full-chunk1`–`chunk6` 121 rows — plus one retest row
  below. No completed row was re-run or overwritten; the two
  tests in flight at each crash (`rv64ui-p-sraiw`,
  `rv64si-p-csr`; empty/truncated logs, no CSV row) were run in
  the successor chunk. The chunked `TESTS=` runs use the same
  ELFs, model library (`work-ver`), and verdict logic as the
  single-run command above.
- Triage: `rv64ui-p-xor` first recorded `FAIL` exit 139 with a
  115-byte log (JTAG banner only, no SUCCESS/FAILED) — a
  testharness crash, not a tohost failure. Standalone re-run
  (`RUN_NAME=xor-retest`) passes with exit 0, `*** SUCCESS ***`
  after 35,837 cycles; the merged matrix carries the retest row.
- Verification: every merged `PASS` row was cross-checked
  against its per-test log (SUCCESS present, FAILED absent, CSV
  cycles equal to log cycles). Per-test logs remain under
  `build/regression/*/logs/` locally (`build/` is not committed).
- Caveat: solo tohost verdict only — no Spike lockstep
  comparison (B2.3) and no ACT4 (B2.4), issue #2. Scope is the
  three directed lists (`asm,amo,mul`) only; floating-point
  lists, random instruction testing, and RVV are later phases.
  This is directed-test evidence on the integrated CVA6 model,
  not a standalone RV64GCV compliance claim.

## B2.3 — Spike tandem lockstep directed regression (2026-10-12, branch `b2-tandem-act4`)

- Artifacts: [`b2-cva6-tandem-2026-10-12.csv`](b2-cva6-tandem-2026-10-12.csv)
  (174-row merged matrix in directed-list order; smoke step:
  [`b2-tandem-smoke-2026-10-12.csv`](b2-tandem-smoke-2026-10-12.csv))
- Command (single-run reproduce):
  `SPIKE_TANDEM=1 TEST_LISTS=asm,amo,mul RUN_NAME=tandem ./scripts/cva6_docker.sh regression`
  (separate model library `work-ver-tandem`; solo evidence untouched)
- Result: **173/174 PASS, 0 lockstep mismatches, 0 timeouts**,
  plus 1 explained reference-configuration waiver below (counts
  by family as B2.1/B2.2: 96 `rv64ui`, 26 `rv64um`, 38 `rv64ua`,
  6 `rv64si`, 7 `rv64mi`, 1 `rv64uc`; 92 `-p-` + 82 `-v-`).
  Every passing log shows DUT `*** SUCCESS *** (tohost = 0)`
  with tandem banner ISA `RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr`
  (from `get_isa_str`, per the B2.0 waivers), boot `0x10000`,
  PMP regions/granularity 8/8, and no `UVM_ERROR`/`UVM_FATAL`.
- Runner fix: tandem setup reads `+elf_file`/`+core_name` via
  `$value$plusargs`, but `ariane_tb.cpp` allowlists only three
  leading Verilog plusargs, so the runner now passes them after
  the binary, where `Verilated::commandArgs` still exposes them.
  `core_name` is the Makefile default target
  `cv64a6_imafdc_sv39` (`riscv_dpi.cc` requires the `cv64a`
  prefix; the `spike.sv` default `cva6` aborts). No
  `third_party/` patch was needed.
- Assembly note: the matrix merges nine 20-test chunk runs
  (`tandem-chunk1`–`chunk9`, list order) plus one retest below.
  Chunking uses the same ELFs, tandem model, and verdict logic
  as the single-run command; it exists because longer Docker
  runs on this host have died mid-matrix (see B2.2 note).
- Triage (2 initial non-PASS rows, both resolved):
  `rv64ua-v-amoand_w` first recorded `TIMEOUT` under host
  slowdown (log stalled after Spike init); standalone re-run
  passes with 21,225 cycles in 26 s, in family with its sibling
  atomics, and the matrix carries the retest row.
  `rv64mi-p-csr` deterministically records `FAIL` (exit 0,
  1,203 cycles, 0 mismatches): its log contains both CVA6
  `*** SUCCESS ***` and Spike-side `*** FAILED ***`, because
  tandem Spike has no `cycle` CSR without Zicntr (frozen
  `ext_zicntr_supported=0`) and traps on `TEST_CASE 25` while
  CVA6 passes. Standalone-Spike bisection (tandem ISA string
  fails exit 18; adding `_zicntr` passes) confirms a
  reference-configuration divergence, waived with reasons in
  `docs/SPIKE_CONFIG.md` (waived item 5). The matrix keeps the
  `FAIL` row; B2.3 acceptance is zero *unexplained* mismatches.
- Verification: every merged row was cross-checked against its
  per-test log (tandem banner, SUCCESS/FAILED shape, zero
  mismatches, CSV cycles equal to log cycles, no hidden UVM
  errors in passing logs). Per-test logs remain under
  `build/regression/*/logs/` locally (`build/` is not committed).
- Caveat: tandem comparison is architectural lockstep against
  Spike as configured in B2.0 (including its waivers), not a
  second normative compliance run. ACT4 `I,M` on the model is
  B2.4; the combined four-column matrix is B2.5 (issue #2).

## B2.4/B2.5 — ACT4 I/M on CVA6 and combined B2 matrix (2026-10-12, branch `b2-tandem-act4`)

- Artifacts: [`b2-act-cva6-2026-10-12.csv`](b2-act-cva6-2026-10-12.csv)
  (64-row ACT matrix), [`b2-combined-matrix-2026-10-12.csv`](b2-combined-matrix-2026-10-12.csv)
  (174-row Spike-solo / CVA6-solo / tandem matrix, B2.5);
  smoke step: [`b2-act-smoke-2026-10-12.csv`](b2-act-smoke-2026-10-12.csv)
- DUT config: `sw/act4-cva6/` (UDB yaml, `sail.json`, `link.ld`,
  `rvmodel_macros.h`, `test_config.yaml`), adapted from the
  upstream riscv-arch-test CVA6+Ara config to this scalar
  `cv64a6_imafdc_sv39` testharness build; see that directory's
  README for provenance and deliberate under-claims.
- Generation: `./scripts/build_act4_cva6.sh` produces 64
  self-checking ELFs (51 `I` + 13 `M`, riscv-arch-test
  `6af53584`, Sail-generated expected results) and stages them
  under `third_party/cva6/act-elfs/` for the batch runner
  (`ELF_SUBDIR=act-elfs TEST_LISTS=act-im` in
  `scripts/cva6_docker.sh`, four 16-ELF chunks `act-chunk1`–`4`).
- Result: **64/64 PASS** on the CVA6 solo model, 0
  fail/timeout; every log shows DUT `*** SUCCESS ***` and
  `RVCP-SUMMARY: TEST PASSED` with CSV cycles matching the log.
  ACT ELFs are self-checking against Sail, so a model PASS
  means CVA6 reproduced the reference result for every checked
  register/memory signature in that test. The optional
  standalone-Spike ACT cross-check was not run (generation
  already checks each ELF against Sail).
- Combined B2 outcome (B2.5): standalone Spike 174/174 PASS,
  CVA6 solo 174/174 PASS, tandem lockstep 173/174 PASS with
  zero mismatches plus the single waived `rv64mi-p-csr`
  reference-configuration divergence above, and ACT4 `I,M`
  64/64 PASS on the model. Within B2 scope the integrated
  CVA6 model (stock `cv64a6_imafdc_sv39` at `81245a47`, custom
  crypto not yet integrated) is therefore claimed as passing
  the directed `asm,amo,mul` lists plus ACT4 `I,M` — nothing
  wider (floating-point lists, privileged ACT suites, and RVV
  remain later-phase work, issues #7/#9).

## ISA verification sweep — F/D + A (2026-10-12, branch `isa-verify-sweep`, issue #7)

Pre-GDS sweep ordered ahead of B3. Directed float lists are
CVA6 `ci/riscv-fp-tests.list` ("fp"); ACT suites are generated
with the B2.4 DUT config (`sw/act4-cva6/`).

- Artifacts: [`fp-cva6-solo-2026-10-12.csv`](fp-cva6-solo-2026-10-12.csv)
  (46 directed float, CVA6 solo), [`spike-solo-fp-2026-10-12.log`](spike-solo-fp-2026-10-12.log)
  (46, standalone Spike `matched`), [`fp-tandem-f-2026-10-12.csv`](fp-tandem-f-2026-10-12.csv)
  (22 single-precision tandem), [`act-afd-cva6-2026-10-12.csv`](act-afd-cva6-2026-10-12.csv)
  (222 ACT rows: 84 F + 116 D + 18 Zaamo + 4 Zalrsc); smoke
  steps: [`fp-smoke-2026-10-12.csv`](fp-smoke-2026-10-12.csv),
  [`fp-tandem-smoke-2026-10-12.csv`](fp-tandem-smoke-2026-10-12.csv)
- Directed result: **CVA6 solo 46/46 PASS** (22 F + 24 D,
  `-p-`/`-v-`), **Spike solo 46/46 PASS**, **tandem F 22/22
  PASS** with 0 mismatches. Tandem D (24 tests) is waived as
  a harness limitation, not run to a matrix: every D test
  probed (`fadd`, `fdiv`, `move`, `ldst`) shows DUT SUCCESS
  with Spike-side FAILED and zero compare mismatches,
  including load/move-only tests, isolating tandem `fld`
  stepping at this pin (`docs/SPIKE_CONFIG.md` waived item 6).
  D arithmetic itself is evidenced by both solo oracles.
- ACT result: **220/222 PASS** on the CVA6 solo model (all F,
  D, Zaamo, and Zalrsc-`lr` rows PASS with
  `RVCP-SUMMARY: TEST PASSED`). The two `Zalrsc-sc` rows
  (`sc.d`, `sc.w`) hang to the cycle cap (still running at
  10M cycles, `tohost` untouched) in this testharness and are
  recorded `FAIL` as an explained waiver: directed
  `rv64ua-*-lrsc` passes solo and tandem (B2) and ACT
  `Zalrsc-lr` passes here, so core LR/SC logic is evidenced;
  the ACT `sc` case mix (hundreds of constrained-loop cases
  including `rs1=x0` forms) wedges the simulation memory
  path. Revisit with a directed case-level probe under #7;
  do not claim ACT Zalrsc-sc coverage.
- One transient harness crash (`F-fadd.s-00`, exit 139,
  banner-only log) passes cleanly on standalone re-run and in
  its chunk row, as with B2.2 `xor`.
- Berkeley TestFloat for this slice is stored separately
  below (2026-10-13).

## ISA verification sweep — B/C/Zicond/scalar-crypto (2026-10-12, branch `isa-verify-sweep`, issues #16/#17)

- Artifact: [`act-bc-cva6-2026-10-12.csv`](act-bc-cva6-2026-10-12.csv)
  (133-row ACT matrix in suite order)
- Config change: `Zcb`, `Zicond`, `Zkne`, `Zknd`, `Zknh`
  declared in `sw/act4-cva6/` after decoder audit at
  `81245a47` (compressed_decoder Zcb cases, `czero` under
  `RVZiCond`, AES/SHA ops under `ZKN`); Sail support enabled
  to match. Generation as B2.4 (`EXTENSIONS=` per suite),
  run solo on the CVA6 model in seven chunks
  (`act-b-chunk1`–`7`, `TIME_OUT` raised cycle cap supported
  by the runner for long ACT tests).
- Result: **133/133 PASS**, 0 fail/timeout (Zba 8, Zbb 24,
  Zbc 3, Zbs 8, Zbkb 14, Zbkc 2, Zca 32, Zcd 4, Zcb-family
  12, Zicsr 6, Zifencei 1, Zicond 2, Zkne 4, Zknd 5, Zknh 8);
  every log shows DUT `*** SUCCESS ***` and
  `RVCP-SUMMARY: TEST PASSED` with matching cycles.
- Scope notes: solo-model ACT evidence. Tandem lockstep for
  these suites was not run (B2.3 waivers already exclude
  Zicond/ZKN operands from comparison; bitmanip tandem is
  possible future work, not claimed). `Misalign` suite
  generated zero ELFs under this config and is handled with
  the privileged slice. Issues #16/#17 acceptance (stored
  green reports) is met by this artifact.

## ISA verification sweep — Berkeley TestFloat vs cvfpu (2026-10-13, branch `isa-verify-sweep`, issue #7)

- Artifact: [`testfloat-cva6-2026-10-13.csv`](testfloat-cva6-2026-10-13.csv)
  (12-row merged matrix in generator op order)
- Harness: `./scripts/build_testfloat.sh` builds host
  `testfloat_gen` (Berkeley SoftFloat/TestFloat 3e, RISCV
  specialization; berkeley-softfloat-3 `a0c6494c`,
  berkeley-testfloat-3 `a9c849f1`, uncommitted under
  `third_party/`), generates level-1 seed-42 vectors, and
  `scripts/testfloat_cva6.py` emits bare-metal checkers
  (`sw/testfloat/`) that execute each vector on the FPU and
  compare result bits (any NaN matches any NaN) and accrued
  `fflags` exactly, halting via HTIF `tohost` with the failing
  case index encoded. ELFs staged under
  `third_party/cva6/testfloat-elfs/`, run solo on the CVA6
  model in four 3-ELF chunks (`tf-chunk1`–`4`,
  `TIME_OUT=20000000 TEST_TIMEOUT_SEC=420`); the single-run
  reproduce (`TEST_LISTS=testfloat RUN_NAME=tf-all`, runner
  list added with this evidence) reproduces the identical
  12-row matrix.
- Result: **12/12 PASS**, 0 fail/timeout — f32/f64 add, sub,
  mul, div, sqrt, and fused mulAdd at RNE with
  tininess-after-rounding, 466,008 vector executions in
  total (46,464 per binary op; the two mulAdd ops are
  stride-sampled 46,464 of 6,133,248 level-1 cases; sqrt
  full at 600 f32 / 768 f64). Every log shows
  `*** SUCCESS ***` with CSV cycles matching the log.
- Scope notes: vectors are checked against SoftFloat with
  the RISCV specialization, so a PASS means the cvfpu
  configuration in this CVA6 build agrees with the
  IEEE-754/RISC-V reference arithmetic (including exception
  flags) for these operations at RNE. Conversions,
  comparisons/`roundToInt`, non-RNE rounding modes, and
  level-2 density remain follow-up work under issue #7;
  do not claim full TestFloat coverage. This completes the
  TestFloat task of #7; its privileged/Sv39 + Linux task
  is the next section.

## ISA verification sweep — privileged ACT (Sv39/PMP/exceptions) (2026-10-13, branch `isa-verify-sweep`, issue #7)

- Artifact: [`act-priv-cva6-2026-10-13.csv`](act-priv-cva6-2026-10-13.csv)
  (134-row merged matrix in generated-list order)
- Config changes: `include_priv_tests: True` in
  `sw/act4-cva6/test_config.yaml`, and Svnapot declared in
  the UDB yaml + `sail.json` after the discovery pass showed
  the hardware translating NAPOT PTEs the config claimed
  unsupported (`SvnapotEn: bit'(1)`,
  `cv64a6_imafdc_sv39_config_pkg.sv` @`81245a47`). The full
  matrix was regenerated and rerun under the corrected
  config (nine 16-ELF chunks `priv2-chunk1`–`9`,
  `TIME_OUT=10000000`), so every row below is from the
  corrected config; the three divergence classes reproduced
  identically across both passes.
- Result: **126/134 PASS**, 0 timeouts (ExceptionsSv 2,
  ExceptionsSvSm 4, ExceptionsSvZaamo 2,
  ExceptionsSvZaamoSm 3, ExceptionsSvZalrsc 0/2,
  ExceptionsSvZalrscSm 0/3, PMPF 1, PMPS 10, PMPSm 35/37,
  PMPU 10, PMPZaamo 1, PMPZalrsc 0/1, PMPZca 11, Sv 28,
  SvPMP 4, SvSm 6, Svade 2, Svbare 2, SvbareSm 1,
  Svnapot 4); every PASS log cross-checked (`SUCCESS` +
  `RVCP-SUMMARY: TEST PASSED` + matching cycles).
- Waived divergences (8 rows kept as FAIL/MISMATCH in the
  matrix; each log fingerprinted at merge time):
  1. **LR exception cause class** (6 tests: all
     ExceptionsSvZalrsc* + PMPZalrsc): CVA6 reports LR
     faults with store/AMO causes (misaligned 6 vs 4, page
     fault 15 vs 13, access fault 7 vs 5) because its LSU
     classifies LR on the store side; Sail/ACT classify LR
     as a load. Verified at the faulting `lr.w` (XEPC
     disassembly). Exception *behavior* otherwise matches.
  2. **PMP grain readback** (`PMPSm_grain-00`): for G=1,
     the spec gives NAPOT pmpaddr bit 0 its stored value,
     but `csr_regfile.sv` forces readback bit 0 to 1
     whenever A[1]=1 (the read-as-ones rule applies to
     bits [G-2:0], empty at G=1). Address matching itself
     (grain check suite) passes.
  3. **PA0 data value** (`PMPSm_cfg_A_tor_zero-00`): the
     test loads from physical address 0 and checks data;
     Sail's boot image and the harness debug ROM hold
     different words there (0x8067 vs 0x2). PMP permission
     behavior around the probe passes; the data word is
     platform content, not DUT logic.
- Not generated (0 ELFs, correctly deselected):
  `Misalign` (UDB declares misaligned ld/st unsupported —
  inherited measurement D13 says misaligned scalar accesses
  silently corrupt rather than fault; re-measure before
  claiming), Svadu/SvaduPMP (Svade implemented instead),
  Svinval/SvinvalSm and Svpbmt (no decode/PBMTE at this
  pin, checked in RTL), PMPZicbo/SvPMPZicbo/SvZicbo (no
  Zicbo). Sv48/Sv57 variants deselect against Sv39.
- Linux boot smoke: **not run, assessed out of scope for
  this harness tonight** — it needs cva6-sdk
  OpenSBI/Buildroot images and a linux-gnu toolchain (none
  present) plus ~10^9-cycle Verilator boots, a different
  flow from the tohost regression harness. Tracked as
  follow-up; privileged/Sv39 *spot checks* are the matrix
  above. Tandem lockstep for privileged suites not run.

## Sweep follow-ups — TestFloat conversions + comparisons (2026-10-13, branch `sweep-followups`, issue #20)

- Artifact: [`testfloat-cvt-cva6-2026-10-13.csv`](testfloat-cvt-cva6-2026-10-13.csv)
  (24-row merged matrix in `testfloat-cvt` list order)
- Harness: `scripts/testfloat_cva6.py` extended with
  conversion/comparison classes (float->int, int->float,
  f32<->f64, feq/fle/flt); arithmetic output verified
  byte-identical to the committed generator. Runner gains
  `TEST_LISTS=testfloat-cvt`; `scripts/build_testfloat.sh`
  default op set covers all 36 checkers. Run solo in four
  chunks (`tfcvt-chunk1`–`4`, `TIME_OUT=20000000
  TEST_TIMEOUT_SEC=420`).
- Result: **24/24 PASS**, 290,136 vector executions —
  f32/f64 to i32/i64/ui32/ui64, i32/i64/ui32/ui64 to
  f32/f64, f32->f64, f64->f32 (372–768 level-1 cases
  each), and f32/f64 eq/le/lt (46,464 each). Every log
  cross-checked against its row.
- Flag caveat (float->int only): TestFloat generates
  to-int vectors with SoftFloat `exact=false`, so its
  expected flags never include NX, while RISC-V `fcvt`
  raises NX on inexact conversions (flag distribution in
  the vectors is only {none, NV}). The checkers therefore
  mask NX for the 8 float->int ops and compare the other
  flags exactly; `fcvt` NX behavior itself is covered by
  ACT F/D against Sail (200/200 above). Everything else
  (result bits including saturation, NV) is exact.
- Remaining TestFloat depth under #20: non-RNE rounding
  modes, level-2 density. `roundToInt` has no instruction
  in this config (Zfa `fround` not implemented) and stays
  unclaimed.

## Sweep follow-ups — misaligned-access re-measure (2026-10-13, branch `misalign-probe`, issue #20)

- Artifact: [`misalign-probe-2026-10-13.csv`](misalign-probe-2026-10-13.csv)
  (1 row, PASS); probe source `sw/misalign/probe.S`
- Question: the inherited upstream CVA6+Ara config notes
  (discrepancy D13) claim misaligned scalar accesses
  silently corrupt data; our UDB declares
  `MISALIGNED_LDST: false` with an LSU-trap rationale.
  The probe (53 directed cases: lh/lhu/lw/lwu/ld,
  sh/sw/sd, flw/fld/fsw/fsd, lr.w/lr.d,
  amoadd.w/amoadd.d at every misaligning offset, aligned
  controls, and a no-write-on-trap memory check) runs on
  the scalar model and requires exact mcause per case.
- Result: **PASS** — every misaligned access traps
  (loads cause 4, stores/AMO/LR cause 6, LR store-class
  as in the privileged matrix), trapping stores modify
  nothing, aligned controls do not trap. D13 does not
  apply to this build; `docs/SPIKE_CONFIG.md`-era tandem
  `rv64mi-p-ma_addr` agreement is consistent with this.
- Consequence: `MISALIGNED_LDST: false` stands as
  measured truth, and the ACT `Misalign` suite — which
  requires `MISALIGNED_LDST: true` (hardware handles
  misaligned accesses without trapping) — correctly
  generates zero ELFs for this DUT. Misaligned handling
  by trap is the claim; non-trapping handling is not
  claimed. Config comments updated to cite this probe
  (behavior fields unchanged; no prior ELF changes).

## Sweep follow-ups — TestFloat non-RNE rounding modes (2026-10-13, branch `testfloat-rounding`, issue #20)

- Artifact: [`testfloat-rm-cva6-2026-10-13.csv`](testfloat-rm-cva6-2026-10-13.csv)
  (76-row merged matrix in `testfloat-rm` list order)
- Harness: generator `--rm` sets `frm` per ELF (RNE
  default output verified byte-identical); build script
  `RMODE=rtz|rdn|rup|rmm` generates vectors with the
  matching `testfloat_gen` flag (`-rminMag/-rmin/-rmax/
  -rnear_maxMag`, tininess-after) and stages
  `tf-<op>_<mode>`; runner list `testfloat-rm`
  enumerates all 76. Arithmetic ops are stride-sampled
  to 23,232 cases (half of level-1 binary density;
  mulAdd 23,232 of 6,133,248); conversions run full
  level-1 (372–768).
- Result: **76/76 PASS**, 771,936 vector executions —
  RTZ, RDN, RUP, and RMM each over f32/f64
  add/mul/div/sqrt/mulAdd plus nine conversions
  (f32_to_i32, f32_to_ui64, f64_to_i64, f64_to_ui32,
  i64_to_f32, ui64_to_f64, i32_to_f64, ui32_to_f32,
  f64_to_f32), run solo in eight chunks
  (`tfrm-<mode>-arith/cvt`). Every PASS log
  cross-checked. Single-run reproduce:
  `TEST_LISTS=testfloat-rm` (same selection; chunking is
  a host-stability measure, as in B2.2). Float->int NX
  masking applies as in the conversions evidence.
- TestFloat totals across the three matrices: 112
  checkers, 1,528,080 vectors, all PASS. Remaining
  under #20: level-2 mulAdd density. Sub-operations
  f32_sub/f64_sub rounding is covered at RNE and shares
  the adder rounding path; not separately run per mode.

## B3 — OpenROAD closure, muse_crypto nangate45 (2026-10-13, branch `b3-openroad`, issue #3)

- Artifact: [`b3-openroad-nangate45-2026-10-13.log`](b3-openroad-nangate45-2026-10-13.log)
  (metrics + liberty signoff extract); GDS published as
  the GitHub release asset `b3-nangate45-2026-10-13`
  (`6_final.gds`, 61 MB, not in git).
- Commands: `./scripts/openroad_docker.sh` then
  `./scripts/orfs_liberty_check.sh` (both Dockerized;
  config in `flow/designs/nangate45/muse_crypto/`).
- Baseline (pre-fix run): detail-route DRC 0, antenna 0,
  setup/hold TNS 0 (+5.13/+0.038 ns @ 10 ns), GDS
  written, but 51 post-route max-capacitance violations
  vs liberty (0 at every pre-route stage; final routed
  parasitics exceed estimates by up to 22%).
- Fix (three measured iterations): `EARLY_SIZING_CAP_RATIO
  = 0.8` alone changed nothing (buffering decisions key
  on the full limit); an SDC `set_max_capacitance` repair
  guardband is honored by the resizer at every stage —
  42 fF left 9 liberty violators, 21 fF (26.05/1.223,
  tightest violator class over worst observed growth)
  left 5, all weakest PMOS-stack gates; `DONT_USE_CELLS`
  (with `override` — the platform config is included
  after the design config and otherwise clobbers the
  list) bans NOR3_X1/NOR4_X1/NOR4_X2.
- Final result: **detail-route DRC 0, antenna 0, liberty
  max-cap/slew/fanout violations 0, setup WS +4.52 ns,
  hold WS +0.039 ns, TNS 0/0**; 61,590 stdcells,
  95,431 µm² stdcell area in a 296,867 µm² core (32.1%
  utilized), 20.16 mW total. The 21 fF SDC value is a
  repair target only; signoff is liberty limits via
  `scripts/orfs_liberty_check.sh` (the flow finish
  report counts 2,979 pins over the 21 fF guardband by
  design). Hold margin (+39 ps) is positive but thin —
  recorded, not waived. sky130hd deltas live in
  `flow/designs/sky130hd/muse_crypto/README.md`; no
  sky130hd run is claimed.

## Ara RVV integration — model build + vector smoke (2026-10-13, branch `9-ara-rvv`, issue #9)

- Artifact: [`ara-smoke-2026-10-13.log`](ara-smoke-2026-10-13.log);
  smoke source `sw/ara-smoke/`, runner
  `scripts/ara_docker.sh`.
- System: Ara `34bd3bc1` (2 lanes, VLEN 512) attached
  to its Bender-pinned CVA6 `99eac9a6`
  (`cv64a6_imafdcv_sv39`), verilated with Ara's pinned
  Verilator 5.047 in a native-arm64 container. The
  earlier "host RAM/toolchain" deferral turned out
  avoidable: only Verilator is built from source
  (~3 min), Bender deps come from the lockfile
  (`checkout`, not `update`), the SRAM DPI patch is
  applied, and the smoke kernel compiles with the
  packaged `riscv64-unknown-elf-gcc` — no LLVM build,
  no Docker memory increase (VM remains 7.65 GiB).
- Result: **smoke PASS** — strip-mined `vadd.vv` and
  `vfadd.vv` over 64 elements verified scalar-side,
  exit 0 in 3,751 cycles (~46 kHz); corrupted-expectation
  negative control exits 2; restored kernel re-passes
  deterministically.
- App kernels: [`ara-apps-2026-10-13.csv`](ara-apps-2026-10-13.csv)
  — 15/17 PASS on the model via the GCC substitute path
  (`sw/ara-smoke/run_apps.sh`, packaged
  `riscv64-unknown-elf-gcc` + picolibc specs): hello_world,
  dotproduct, fdotproduct, imatmul, fmatmul, iconv2d,
  fconv2d, jacobi2d, dropout, exp, softmax, pathfinder,
  roi_align, lavamd, fconv3d. `fft` and `dwt` fail with
  numerical errors at VLEN512, but both kernels carry
  single-register-group length assumptions that cannot
  hold at VLEN512 for the shipped problem sizes (`fft`:
  source documents "works if n_fft < VLMAX" and ignores
  the `vsetvl` return value, NFFT=64 vs VLMAX 16 for
  e32m1; `dwt`: vl-doubling accounting needs DWT_LEN=512
  to fit one e32m4 group, i.e. VLEN ≥ 2048). Both PASS
  on a VLEN2048 build of the same model with the same
  GCC toolchain
  ([`ara-apps-vlen2048-2026-10-13.csv`](ara-apps-vlen2048-2026-10-13.csv)),
  so they are classified as kernel VLEN assumptions, not
  hardware or compiler failures; the planned LLVM retest
  is descoped for these two kernels because the failure
  mode is compiler-independent by construction.
- Patched riscv-tests vector list (rv64uv, 177 tests,
  `sw/ara-smoke/run_rvtests.sh`, GCC builds):
  [`ara-rv64uv-2026-10-13.csv`](ara-rv64uv-2026-10-13.csv)
  records 49 PASS / 127 FAIL / 1 TIMEOUT (`vrgather`) at
  VLEN512. Every failing test's source assumes VLEN > 512
  by at least one concrete mechanism — hardcoded
  `VSET(avl, ...)` counts above VLMAX at VLEN512 while
  the `VLOAD`/`VCMP` macros check all `avl` elements;
  widening/narrowing cases that require the wide operand
  to fit one physical register; or `check_vtype_vl`
  requiring `vl == avl` for AVL up to 250 — and no test
  whose source fits VLEN512 fails (first failing element
  index is 8 in the widening cases, exactly one 512-bit
  register of e64). Rebuilt at VLEN2048 (Ara's upstream
  default for `2_lanes`) with the same GCC toolchain, the
  full list passes 177/177
  ([`ara-rv64uv-vlen2048-2026-10-13.csv`](ara-rv64uv-vlen2048-2026-10-13.csv)),
  which confirms the VLEN512 failures are test-source
  VLEN assumptions rather than Ara hardware bugs or GCC
  codegen faults. This suite therefore cannot serve as
  VLEN512 acceptance evidence; the VLEN512 claim rests on
  the smoke kernel, the 15 VLEN-agnostic app kernels, and
  the 49 rv64uv tests that fit VLEN512, pending ACT.
- ACT vector suites with a dedicated DUT config
  (`sw/act4-cva6v/`, derived byte-identically except
  `name:`/`description:` from upstream arch-test
  `6af53584`'s `cv64a6_imafdcv_sv39` config for these
  exact pins at VLEN512; `scripts/ara_docker.sh` applies
  upstream's two DUT-build patches — 16 MiB ELF loader
  window and CVA6 RVB/ZKN enable — so the model matches
  the config; note the model was re-verilated with those
  patches after the rv64uv/apps runs above, with smoke,
  rv64uv 1–10, and `dotproduct` re-verified
  cycle-identical). Generation
  (`scripts/build_act4_cva6v.sh`, Sail-checked) produced
  2,047 ELFs across Vf32/Vf64/Vls8–64/Vx8–64; 34 further
  Vls indexed/segment tests fail at generation time on
  the Sail side ("trap signature overflow", a test-side
  defect independent of the DUT;
  [`act-vector-genfail-2026-10-13.csv`](act-vector-genfail-2026-10-13.csv)).
  Running all 2,047 on the model
  ([`act-vector-cva6v-2026-10-13.csv`](act-vector-cva6v-2026-10-13.csv))
  gives 6 PASS / 2,005 FAIL / 36 TIMEOUT. The failures
  are **not** instruction-result mismatches: 2,032 fail
  at test case 1 inside ACT's self-check compare
  (`RVTEST_SIGUPD_V`: `vmsne.vv` + `vfirst.m` at small
  `vl`) with the reported bad byte equal to the expected
  byte, and the only passes are the scalar-result moves
  (`vmv.x.s`, `vfmv.f.s`) that use the scalar signature
  path. A directed probe
  ([`act-vector-vfirst-probe-2026-10-13.log`](act-vector-vfirst-probe-2026-10-13.log),
  source `sw/act4-cva6v/probe_tail.c`) root-causes this:
  data-path ops honor `vl` and tail-undisturbed exactly,
  but at `vl=1` the Ara mask compare writes NrLanes mask
  bits (2 here, 4 on a 4-lane build) instead of one, and
  `vfirst.m` scans past `vl`, returning NrLanes instead
  of -1 — contrary to RVV 1.0, where `vfirst`/`vpopc`
  examine only active elements (index < `vl`) and
  mask-result tails under `mu` are undisturbed. The 36
  TIMEOUTs (masked `vmadc`/`vmsbc`, `vrgather*`,
  `vcompress`) never halt; every terminating test
  finishes within 26,363 cycles, so these are hangs, not
  slow tests (budgets used: 20M cycles ×1, 5M ×7, 1M ×28,
  recorded per-row in the CSV). Net: ACT vector cannot
  pass on Ara at this pin — at either lane count —
  because of this Ara mask-op deviation, which also
  means full RVV 1.0 compliance **cannot be claimed**
  for the integrated CVA6+Ara system; `vfirst`/`vpopc`
  `vl` bounding and mask-tail behavior are requirements
  carried into the in-house core (#18).
- Open on #9: the synthesis area/timing snapshot, and
  the acceptance decision given the ACT blocker above
  (fix belongs upstream in Ara or in #18; it is not
  fixable in test code without invalidating the
  evidence). Vector compliance is not claimed.
  Resolution: #9 closed as merged with both items
  explicitly descoped; synthesis closure is tracked by
  #11, the ACT requirement by #18.

## In-house core stage 1 — RV64I (2026-10-13, issue #18 branch)

- Artifact: [`core-stage1-2026-10-13.log`](core-stage1-2026-10-13.log)
  (extract of a clean `make core-test` run); design and
  staging plan in [`docs/CORE.md`](../CORE.md), RTL in
  `rtl/core/`, C++ Verilator testbenches in `tb/cpp/`,
  directed software in `sw/core-tests/`.
- Result: ALU unit TB 205,642 checks, decoder unit TB
  10,258 checks (full opcode × funct3 × funct7-sample
  sweep vs an encoding-whitelist golden model), regfile
  unit TB 4,194 checks, directed RV64I assembly (14
  groups: arithmetic/logic/shifts incl. W variants, all
  branches, JAL/JALR, every load/store size and
  extension, `x0`, FENCE, AUIPC) and five expected-trap
  programs (illegal CSR access, misaligned load/store,
  ECALL, EBREAK) all PASS on the single-cycle core.
- Coverage: every annotated source line in `rtl/core/`
  executed (273/273, no `%000000` lines); combined
  line+toggle points 163/273 (59%), the residue being
  toggle/partial-expression points on wide datapaths.
- Bugs found by this loop and fixed before commit: ADDI
  with a negative immediate decoded as SUB, and illegal
  encodings leaking side-effecting control fields (both
  in `muserisc_decoder`); harness read-data settle and
  golden-model slips in two TBs.
- Caveat: this is stage 1 of the plan in
  `docs/CORE.md` — single-cycle RV64I only. No
  compliance claim attaches to it; riscv-tests/ACT
  gates start once CSR/trap state lands (stage 3).

## In-house core stage 2 — M extension + pipeline (2026-10-13, #18)

- Artifact: [`core-stage2-2026-10-13.log`](core-stage2-2026-10-13.log)
  (clean `make core-test` extract); plan in
  [`docs/CORE.md`](../CORE.md).
- Stage 2a (commit `1f280ec`): `muserisc_muldiv` (RV64M incl.
  divide-by-zero and signed-overflow rules, W variants) with a
  C++ unit TB (165,877 checks, `__int128` golden model,
  divisor-biased randoms) and `sw/core-tests/rv64m_directed.S`
  (sign quadrants, div-by-zero, `INT_MIN/-1` at both widths,
  div-mul-rem round trips), verified first on the single-cycle
  core.
- Stage 2b: the core is now a 5-stage in-order pipeline (full
  EX forwarding + WB→ID bypass, one load-use bubble, control
  transfers resolved in EX with two flushed slots, exceptions
  carried to WB so a trapping instruction and everything
  younger write nothing — the last point proven by
  `trap_younger_store.S`). The full stage-1/2a suite stays
  green unchanged, plus `pipeline_directed.S` (forwarding
  chains at distances 1–3, load-use into ALU/branch/JALR/store
  data and address, flush suppressing a fall-through store,
  `x0` never forwarding, dependent accumulate loop).
- Coverage: every annotated `rtl/core/` source line executed
  (456/456); combined line+toggle points 314/456 (68%),
  deterministic across reruns. `make test` and `make lint`
  also pass at this commit.
- Caveat: the divider is combinational (correctness vehicle,
  not timing-closable — an iterative divider replaces it
  before any synthesis target), and traps still halt the
  machine at WB; real trap state is stage 3. No compliance
  claim attaches yet.

## In-house core stage 3a — CSRs, privilege, traps, PMP (2026-10-13, #18)

- Artifact: [`core-stage3a-2026-10-13.log`](core-stage3a-2026-10-13.log)
  (`make core-test` extract); plan in
  [`docs/CORE.md`](../CORE.md).
- New `muserisc_csr` (505 lines): M/S/U CSR file with spec write
  masks, `sstatus`/`sie`/`sip` masked views, counters,
  trap entry/return with delegation (`medeleg`/`mideleg`),
  direct+vectored trap targets, interrupt priority
  (MEI > MSI > MTI > SEI > SSI > STI), and 16 PMP entries
  (OFF/TOR/NA4/NAPOT, W-without-R WARL, entry and
  adjacent-TOR locking). The pipeline takes precise traps at
  WB (trapping instruction and everything younger write
  nothing), injects interrupts in ID for a precise `epc`,
  executes CSR ops in EX committing on the EX→MEM edge, and
  checks PMP on fetch and data (with MPRV applied to data).
  `trap_halt_i` preserves the stage-1/2 freeze-and-report mode
  for the directed trap TBs.
- Verification: new C++ CSR unit TB (117 checks at the module
  ports), decoder TB grown to 12,311 checks for the SYSTEM
  space, and `sw/core-tests/priv_directed.S` (14 groups:
  CSR masks, MRET/SRET, delegation, PMP R/W/X denials
  including a NAPOT execute-deny instruction access fault,
  M timer IRQ and a delegated S timer IRQ with precise
  `epc`, counters, MPRV, privilege violations) — all PASS
  alongside the unchanged stage-1/2 suite.
- Coverage: every annotated `rtl/core/` source line executed
  (876/876); combined line+toggle points 475/926 (51%).
  `make test` and `make lint` also pass at this commit.
- One coverage-driven RTL cleanup: `pmp_locked` rewritten
  from early-`return` form to a single expression (identical
  semantics, proven by the same lock readback checks)
  because Verilator attributes no count to the nested
  return line even when the path provably executes.
- Caveat: `satp` is stored but no translation exists yet —
  Sv39+Svnapot MMU is stage 3b, followed by the riscv-tests
  and ACT stage gates (3c/3d). No compliance claim attaches
  yet.

## In-house core stage 3b — Sv39+Svnapot MMU (2026-10-13, #18)

- Artifact: [`core-stage3b-2026-10-13.log`](core-stage3b-2026-10-13.log)
  (`make core-test` extract); plan in
  [`docs/CORE.md`](../CORE.md).
- New `muserisc_mmu` (408 lines): unified 32-entry
  fully-associative TLB with fetch and data lookup ports,
  one walker sharing the core data port (data misses
  preempt fetch walks), Sv39 4K/2M/1G, Svnapot 64K,
  ASID+global, hardware A/D (Svadu), full-flush SFENCE,
  and recorded walk faults that die when the requester's
  VA moves on (no negative caching). Fetch translates in
  IF (stalling there on a miss); a data miss parks the
  access in MEM and holds the pipeline, with younger CSR
  writes and xRETs gated so nothing commits ahead of a
  possibly-faulting older access. PMP now checks physical
  addresses, with a new third port for implicit PTE
  accesses (S-mode); `satp` MODE is WARL-clamped.
- Verification: new C++ MMU unit TB (53 checks against
  hand-built page tables in TB memory: walks, superpages,
  NAPOT, canonicality, malformed PTEs, U/SUM/MXR, A/D
  writebacks incl. PMP-denied writeback, ASID/global,
  fault auto-clear, data-preempts-fetch) and
  `sw/core-tests/vm_directed.S` (14 groups on the running
  core, page faults 12/13/15 with `tval`, U excursion,
  SFENCE staleness, MPRV) — all PASS, stage-1..3a suite
  unchanged.
- Coverage: every annotated `rtl/core/` source line executed
  (1126/1126); combined line+toggle points 621/1210 (51%).
  `make test` and `make lint` also pass at this commit.
- Caveat: translation exists but no upstream suite has
  judged it yet — riscv-tests (3c) and ACT + a Linux boot
  attempt (3d) are next. No compliance claim attaches yet.

## In-house core stage 3c — riscv-tests gate (2026-10-13, #18)

- Artifact: [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  (per-test result and cycle count); reproduce with
  `make riscv-tests` (runner:
  [`sim/run_riscv_tests.sh`](../../sim/run_riscv_tests.sh)).
- Result: **64/64 PASS** at stage 3c — every `rv64ui-p-*` (51) and
  `rv64um-p-*` (13) test from the in-tree riscv-tests
  sources, compiled with the upstream recipe and run on
  the in-house core through the C++ harness's new ELF/HTIF
  mode (PT_LOAD placement, `boot_pc_i` = ELF entry,
  `tohost` exit). The gate has since been extended to
  the privileged `rv64mi-p-*`/`rv64si-p-*` suites
  (80/80; see stage 4.0 note in the 3d section).
  Cross-checks: three of the CVA6-built
  ELFs pass with identical cycle counts, and a hand-made
  HTIF failure probe is correctly reported as FAIL
  (the harness cannot pass vacuously).
- Core/harness changes: a `boot_pc_i` reset-PC input, and
  paged memory + ELF64/HTIF support in `tb/cpp/core_tb.cpp`
  (flat-binary directed mode unchanged). One toolchain
  shim: this riscv-tests vintage writes `satp` via its
  pre-1.10 alias `sptbr`, which modern binutils rejects;
  the runner shadows `env/p/riscv_test.h` with a renamed
  copy. No test logic is altered.
- Coverage: every annotated `rtl/core/` source line executed
  (1127/1127, one ELF run contributes to the merge);
  `make core-test`, `make test`, and `make lint` also pass
  at this commit.
- Caveat: riscv-tests are a smoke-grade suite, not
  architectural certification — ACT I/M (and a Linux boot
  attempt) in stage 3d is the stricter judge. No
  compliance claim attaches yet. Note this riscv-tests
  vintage has no `ma_data`/misaligned or virtual-memory
  (`-v-`) variants in the `rv64ui` directory; the `-p-`
  set above is complete for that tree.

## In-house core stage 3d — ACT I/M + privileged suites (2026-10-13, #18)

- Artifact: [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv);
  DUT config in [`sw/act4-core/`](../../sw/act4-core/)
  (README there records the generation commands and the
  sail.json derivation), built by
  [`scripts/build_act4_core.sh`](../../scripts/build_act4_core.sh)
  and run by [`sim/run_act_core.sh`](../../sim/run_act_core.sh).
- Result: **ACT I + M 64/64 PASS**, and the privileged
  suites for the declared scope (ExceptionsSv/SvSm, PMP
  S/Sm/U/F, Sv, SvPMP, SvSm, Svbare/Sm, SvaduPMP) bring
  the total to **180/181 PASS**. Self-checking ELFs are
  judged by their HTIF halt on the same C++ harness as
  the directed tests.
- Sole waiver: `PMPSm_cfg_A_tor_zero-00`, the same
  platform divergence waived for the CVA6 host above —
  its probes store/load/execute at PA 0, which Sail's
  memory map access-faults (no region) while this
  harness has RAM there, so the expected traps never
  occur. Fixing it for real needs a bus-fault input on
  the core (SoC-stage work), not a core change.
- ACT earned its keep: triage of the first run (37 priv
  failures) found and fixed five real RTL bugs —
  `misa` had the wrong letter bits (A/Q instead of S),
  pmpcfg reserved bits [6:5] read back instead of
  reading zero, the R0W1→R0W0X0 WARL clearing also ate
  legal X-only entries, `mstatus.TVM` did not trap
  `satp` access from S, `MPRV` was incorrectly cleared
  on trap entry, and instruction-address-misaligned was
  attributed to the jump target's fetch instead of the
  jump instruction (plus counter-enable CSR masks and
  counter access gating added during config). The
  directed CSR TB and `vm_directed.S` were wrong in two
  places for the same old behaviors and were corrected
  (one vm-test fix is itself a lesson: after `mret`,
  MPP=U with MPRV retained makes M-mode loads translate
  as U).
- Coverage: every annotated `rtl/core/` source line executed
  (1143/1143) after the fixes; `make core-test`,
  `make riscv-tests` (64/64), `make test`, and
  `make lint` also pass at this commit.
- Still not a compliance claim: ACT coverage is bounded
  by the declared configuration (RV64IM + priv/Sv39
  scope) and this run is simulation only. A Linux boot
  attempt is the remaining stage-3d item.

- Stage 4.0 follow-up (same branch as stage 4): the
  `rv64mi`/`rv64si` probe failures are closed. `access`
  needed the architectural 56-bit physical-address limit
  enforced (fetch/load above 2^56 now access-fault; two
  directed trap tests added), gated on translation
  completion after ACT caught the first cut faulting
  high-canonical VAs mid-walk; `breakpoint` needed
  zero-trigger Sdtrig CSR stubs (read 0, writes ignored).
  The riscv-tests gate now includes mi/si (**80/80**,
  the CSV above is refreshed in place) and ACT is back
  at 180/181 with the same single waiver.

## In-house core stage 4a — A extension (2026-10-13, #18)

- Same artifacts, refreshed in place:
  [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  is now **99/99** (adds `rv64ua-p-*`, 19 tests) and
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  is now **214/215** (adds Zaamo/Zalrsc +
  ExceptionsSvZaamo/Zalrsc + PMPZaamo/PMPZalrsc; same
  single `tor_zero` waiver).
- Implementation: MEM-stage RMW against the loaded value
  (combinational memory makes AMOs single-cycle), physical
  LR/SC reservation with exact-access semantics (SC must
  lie inside the LR's range; cleared by SC, overlapping
  stores, and traps), `misa` gains A. Directed coverage:
  `sw/core-tests/amo_directed.S` (all 9 AMO ops × W/D where
  meaningful, LR/SC success and failure modes), decoder TB
  12,317 checks.
- One real bug found by ACT PMPZalrsc on first run: AMO/SC
  did not declare their rs2 source to the load-use
  interlock, so an SC immediately after its LR stored a
  stale register value. Fixed in `id_uses_rs2`; a directed
  back-to-back LR→SC regression is test 8 of
  `amo_directed.S`.

## In-house core stage 4b — F/D floating point (2026-10-13, #18)

- New `rtl/core/muserisc_fpu.sv`: combinational IEEE-754
  binary32/64 (add/sub/mul/div/sqrt/FMA×4, sign-inject,
  min/max, compares, class, all conversions, FMV), one
  shared round-and-pack stage, canonical-NaN results,
  NaN-boxing on S ops. Verified by
  [`tb/cpp/fpu_tb.cpp`](../../tb/cpp/fpu_tb.cpp) against
  Berkeley SoftFloat 3: 690,071 checks (random sweep over
  all ops × 5 rounding modes × both formats, plus directed
  specials and tininess-boundary regressions).
- Pipeline: separate 32×64 FP register file (3 read ports),
  full EX forwarding for FP sources incl. FMA rs3, load-use
  interlock for FLW/FLD, `mstatus.FS` with precise Dirty
  tracking, `fflags` accumulation from EX, dynamic-`frm`
  legality checked in EX, `misa` += F,D.
- Gates: `fp_directed.S` + decoder/CSR/FPU unit TBs green;
  [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  now **122/122** (adds `rv64uf`+`rv64ud`, 23 tests);
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  now **414/415** (adds full ACT F and D suites; same
  `tor_zero` waiver). Line coverage: everything except the
  FPU at 100%; `muserisc_fpu.sv` 482/493 merged with ACT
  runs (remainder: defensive default arms for op/rm codes
  the decoder never emits).
- Two real bugs found by ACT (both now regression-tested):
  (1) unpacked ±0 carried exponent `emin`, out-ranking
  tiny subnormals in add/FMA alignment and compares —
  fixed with a below-range exponent for zero; (2) underflow
  tininess must follow Berkeley's rule (jammed significand
  + rounding increment vs 2^emin), not simply "rounded
  result is subnormal".

## In-house core stage 4c — B, Zicond, scalar crypto (2026-10-13, #18)

- New `rtl/core/muserisc_bext.sv`: Zba/Zbb/Zbc/Zbs, Zicond,
  Zbkb/Zbkc(clmul)/Zbkx, Zkne/Zknd (aes64es/esm/ds/dsm/im/
  ks1i/ks2), Zknh (SHA-256/512 sigma/sum). AES S-boxes are
  derived at elaboration from the GF(2^8) inverse; the C++
  golden in [`tb/cpp/bext_tb.cpp`](../../tb/cpp/bext_tb.cpp)
  uses the literal FIPS-197 tables — 54,980 independent
  checks. `bext_directed.S` adds a full AES-128 encryption
  KAT (FIPS-197 vector) built from the scalar instructions
  inside the pipeline. `misa.B` set.
- ACT:
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  now **494/495** — adds Zba(8) Zbb(24) Zbc(3) Zbs(8)
  Zicond(2) Zbkb(14) Zbkc(2) Zbkx(2) Zkne(4) Zknd(5)
  Zknh(8), all green; same `tor_zero` waiver. riscv-tests
  unchanged at 122/122 (no B/K suites exist upstream there).

## In-house core stage 5 — C extension (Zca/Zcb/Zcd) (2026-10-13, #18)

- New `rtl/core/muserisc_rvc.sv`: combinational decompressor
  expanding every Zca/Zcb/Zcd 16-bit form (incl. RV64-only
  `c.addiw`/`c.addw`/`c.subw`/`c.ld`/`c.sd` and Zcb
  byte/halfword loads/stores) to its canonical 32-bit
  instruction; reserved/hint space outside the declared
  extensions raises illegal-instruction. Fetch gained a
  realigner: misaligned (2-byte) PCs fetch the aligned word
  and take the high parcel, and a 32-bit instruction
  straddling a page boundary buffers its first half while
  the second half is fetched (a fault on the second half
  reports `tval = pc+2`, `epc = pc`). IALIGN is now 16:
  jump/branch targets no longer raise address-misaligned
  (fetch faults surface at fetch), `xepc` writes keep bit 1,
  `misa` = `0x8000_0000_0014_112F` (RV64 IMABC FD SU).
  `sw/core-tests/trap_instr_misalign.S` deleted (the case
  no longer exists architecturally).
- Verification: [`tb/cpp/rvc_tb.cpp`](../../tb/cpp/rvc_tb.cpp)
  checks the decompressor against an independent golden
  expander over all directed forms plus randomized parcels
  (49,152 checks); `sw/core-tests/rvc_directed.S` covers
  mixed 16/32-bit streams, misaligned branches/jumps, and
  compressed loads/stores in the pipeline.
- Gates: `make core-test` green;
  [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  now **123/123** (adds `rv64uc-p-rvc`);
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  now **543/544** (adds Zca/Zcb/Zcd and the ZcbZba/ZcbZbb/
  ZcbZmmul combined suites, 49 tests; same single
  `PMPSm_cfg_A_tor_zero` platform waiver — PA0 is RAM in
  this harness but access-faults in the Sail memory map).
- Three encoding bugs were caught by the RVC TB / ACT
  before this gate and are regression-covered: D-form
  load/store immediate bit order, Zcb `c.lh`/`c.sh` select
  and offset mapping, and `c.mul` expanding to MULW
  (OP-32) instead of MUL (OP).
- Flow note: `ExceptionsSv` S/U initially "failed" against
  stale ACT artifacts generated under the pre-C config
  (Sail expectations assumed IALIGN=32; the ACT make does
  not track DUT config changes as dependencies). The core
  was correct; regenerating the priv suites from the
  current config restored 543/544 with no RTL change. The
  regeneration commands, including this caveat, are in
  [`sw/act4-core/README.md`](../../sw/act4-core/README.md).

## Crypto accelerator integration check (2026-10-13, #18)

Inventory of the repo's two distinct crypto layers after
stages 4c/5:

- **In-core scalar crypto** (Zbkb/Zbkc/Zbkx, Zkne/Zknd/Zknh
  in `muserisc_bext.sv`): integrated in the pipeline and
  covered by the ACT gate above plus `bext_directed.S`
  (full AES-128 FIPS-197 KAT from scalar instructions,
  SHA-256/512 sigma/sum ops).
- **Standalone accelerators** (`rtl/crypto/`):
  `sha256_block`, `sha512_block`, `keccak_f1600` and the
  256-bit `ec_field` unit behind the AXI4-Lite slave
  `muse_crypto_top` (SHA-256 block + EC field exposed;
  Keccak engine select reserved pending a streaming
  interface; SHA-512 verified standalone, not yet behind
  the AXI top). `muserisc_soc_top` exposes the AXI-Lite
  port at `0x2000_0000`, but no core/bus drives it yet —
  attaching the in-house core (Harvard SRAM ports today)
  needs a bus bridge + MMIO window + driver, which is B4
  SoC integration (#4), explicitly deferred. No core-side
  integration is claimed.
- Gap found and closed by this check: the leaf engines had
  KATs but the AXI4-Lite register layer had never been
  simulated. New `tb/tb_muse_crypto_top.v` (wired into
  `make test`) drives the documented register map end to
  end reusing leaf-KAT vectors: SHA-256("abc") and
  SHA-256("") digests, EC field mul/sub under secp256k1
  and Curve25519 MODSEL, custom-modulus regs, STATUS
  done-clearing on CTRL write, and reserved engine 1
  leaving STATUS idle. `TB_MUSE_CRYPTO_TOP PASS`; full
  `make test` remains `ALL PHASE-0 KATs PASS`.

### Linux/OpenSBI boot attempt — blocked on A (stage 4)

- Log: [`core-stage3d-linux-attempt-2026-10-13.log`](core-stage3d-linux-attempt-2026-10-13.log).
  OpenSBI generic builds cleanly under Docker with a
  Linux toolchain, but targets RV64GC (59% compressed
  instructions) and — decisively — refuses to configure
  without atomics: `riscv_locks.c: #error "need A or
  Zaamo or Zalrsc"` under `PLATFORM_RISCV_ISA=rv64im_*`.
  The boot is therefore gated on stage 4 (A) and, for
  stock binaries, stage 5 (C); harness CLINT/UART models
  are the remaining small pieces. No boot is claimed.
  This historical block was superseded by stage 6 below.

## In-house core stage 6 — OpenSBI and Linux boot (2026-10-14, #21)

- New platform harness
  [`tb/cpp/soc_tb.cpp`](../../tb/cpp/soc_tb.cpp) around the
  same core (the compliance `core_tb` remains the gate
  harness): boot ROM at `0x1000` presenting `a0=hartid` /
  `a1=DTB`, CLINT at `0x0200_0000`, PLIC at `0x0C00_0000`,
  byte-wide 16550 UART at `0x1000_0000`, and 128 MiB RAM at
  `0x8000_0000`. The machine is described by
  [`sw/linux/muserisc.dts`](../../sw/linux/muserisc.dts).
- [`scripts/build_opensbi.sh`](../../scripts/build_opensbi.sh)
  builds generic OpenSBI `fw_jump` (`0x8020_0000`) and the
  DTB in Docker. OpenSBI v1.9 boots and enters an S-mode
  payload: [`core-stage6a-opensbi-2026-10-14.log`](core-stage6a-opensbi-2026-10-14.log)
  ends with `HELLO FROM S-MODE`.
- [`scripts/build_linux_kernel.sh`](../../scripts/build_linux_kernel.sh)
  builds Linux 6.6 `defconfig` (modules and debug info off)
  with the static embedded-initramfs `/init` from
  [`sw/linux/init.c`](../../sw/linux/init.c). The recorded
  boot used this explicit kernel command line from the DT:
  `console=ttyS0,115200 earlycon=sbi cryptomgr.notests
  initcall_debug loglevel=8 rw`; in particular, crypto
  self-tests are disabled for this evidence run.
- Linux gate:
  [`core-stage6-linux-boot-2026-10-14.log`](core-stage6-linux-boot-2026-10-14.log).
  `SOC TB PASS` at **508,905,040 cycles**. The kernel
  reaches `Run /init as init process`, `/init` prints
  `muserisc init: userspace alive`, reports
  `uname: Linux 6.6.0 ... riscv64`, reads `/proc/version`,
  and prints `MUSERISC_LINUX_BOOT_OK`.
- Two real core bugs were found by this boot and are now
  regression-covered. (1) CSR writes commit in EX while
  traps commit at WB, so OpenSBI's younger `mtvec` restore
  beat its probing trap to the vector;
  `trap_younger_csr.S` failed before the `!mem_exc` gate and
  passes after it. (2) `time` was aliased to inhibited
  `mcycle`; OpenSBI PMU stop-all sets `mcountinhibit.CY`,
  which froze Linux's clocksource at `pmu_sbi_devinit`.
  `time` now has an independent real-time counter, covered
  by the CSR unit TB and `counter_time_directed.S`. A
  harness-only walker-starvation bug (page-table walks do
  not assert `dmem_re_o`) was also found and fixed in
  `soc_tb`; the page tables and core walker were correct.
- Final gates after both RTL fixes: `make core-test` and
  `make lint` green, `make test` = `ALL PHASE-0 KATs PASS`,
  [`riscv-tests-core-2026-10-14.csv`](riscv-tests-core-2026-10-14.csv)
  **123/123**, and
  [`act-core-impriv-2026-10-14.csv`](act-core-impriv-2026-10-14.csv)
  **543/544** (same `PMPSm_cfg_A_tor_zero` PA0 platform
  waiver).
- Claim boundary: this is a single-hart Verilator platform
  boot to a small embedded initramfs `/init`, not a distro,
  shell, block/network-device, SMP, H/KVM or V claim, and
  it does not integrate `muse_crypto_top` with the core
  (B4/#4 remains deferred).

## In-house core stage 7 — H hypervisor and KVM smoke (2026-10-14, #22)

- Stage 7a adds the virtualization mode bit, HS/VS CSR banks
  with S↔VS substitution, two-level trap delegation
  (M → HS → VS), virtual-instruction exceptions, and
  `misa.H`. Stage 7b adds two-stage Sv39 + Sv39x4 address
  translation in `muserisc_mmu.sv`, including G-stage
  translation of VS page-table accesses, combined 4 KiB TLB
  fills tagged by ASID/VMID, and guest-page faults
  (causes 20/21/23) with `htval`/`mtval2`. Stage 7c adds
  HLV/HSV/HLVX and HFENCE.VVMA/GVMA. Stage 7d completes VS
  interrupt selection and `hvip` injection. GEILEN is 0.
- First-party gates: CSR TB **196 checks**, MMU TB
  **74 checks**, decoder TB **12,332 checks**, and
  `hyp_directed.S` (M → HS → VS → VU entry, guest ecalls,
  virtual instructions, two-stage store, guest-page fault
  with `htval`, HLV/HSV/HLVX from HS, HFENCE remapping, an
  HLV guest fault reporting `hstatus.GVA`, and an injected
  VSSI handled and cleared in VS) — all inside
  `make core-test`, with `make lint` green.
- Upstream gates re-run on the Stage 7 core:
  [`riscv-tests-core-stage7-2026-10-14.csv`](riscv-tests-core-stage7-2026-10-14.csv)
  **123/123**, and
  [`act-core-stage7-2026-10-14.csv`](act-core-stage7-2026-10-14.csv)
  **543/544** (only the known `PMPSm_cfg_A_tor_zero-00`
  PA0 platform waiver). The pinned ACT tree contains no
  hypervisor suite (`tests/priv/` has no H tests), so there
  is no ACT H result to report; the ACT config now declares
  H for when a suite exists. `make test` still reports
  `ALL PHASE-0 KATs PASS`.
- KVM smoke:
  [`core-stage7-kvm-smoke-2026-10-14.log`](core-stage7-kvm-smoke-2026-10-14.log).
  With `riscv,isa = "rv64imafdcbh"` in the DT, Linux 6.6
  reports `kvm [1]: hypervisor extension available`,
  `using Sv39x4 G-stage page table format`, and `VMID 14
  bits available`. The embedded `/init`
  ([`sw/linux/kvm_smoke.c`](../../sw/linux/kvm_smoke.c),
  built with `MUSERISC_INIT_SRC=sw/linux/kvm_smoke.c
  MUSERISC_IMAGE_OUT=build/linux/Image-kvm
  scripts/build_linux_kernel.sh`) opens `/dev/kvm`,
  creates a VM and one vCPU with a 4 KiB RAM slot at GPA
  `0x1000`, and runs a four-instruction VS-mode guest. The
  guest's store of 42 to MMIO GPA `0x2000` exits with
  `KVM_EXIT_MMIO` (`addr=0x2000 len=4 write=1 data=42`),
  `/init` prints `MUSERISC_KVM_OK`, and the harness reports
  `SOC TB PASS` at **502,972,620 cycles**.
- Claim boundary: this is a one-vCPU KVM entry/exit smoke
  with a four-instruction bare-metal guest on the Verilator
  platform. It is not a guest-OS boot, not SMP, not an
  AIA/IMSIC or external-interrupt-virtualization claim
  (GEILEN=0, no PLIC guest context), and not a substitute
  for a future ACT hypervisor suite.

## In-house core stage 8 — integer V vector (2026-10-14, #23)

- Scope: integer RVV 1.0 (Zve32x/Zve64x, Zvl512b) with
  VLEN=512, ELEN=64 in `muserisc_vec.sv` /
  `muserisc_vregfile.sv` plus the MEM-stage element
  sequencer in `muserisc_core.sv`. Floating-point vector
  (Zve32f/Zve64f/Zve64d, i.e. full V) is **not**
  implemented; `misa.V` is set on the strength of the
  integer subset, so the claim for stage 8 is the integer
  vector subset only. Tail/mask-agnostic is implemented
  as undisturbed (matching the Sail reference
  configuration in `sw/act4-core/sail.json`).
- First-party gates: vector unit TB
  **1,014,476 checks** and `vec_directed.S` inside
  `make core-test`; `make lint` green.
- ACT vector result:
  [`act-core-stage8-2026-10-14.csv`](act-core-stage8-2026-10-14.csv)
  records all 1,936 generated self-checking ELFs run on
  the core (1,872 Vx/Vls vector + 51 I + 13 M):
  **1,936/1,936 PASS**. Generation used
  `scripts/build_act4_core.sh` with `sw/act4-core/`
  config; ELFs run via `build/sim/core_tb`.
- Tests not run (43), listed in
  [`act-vector-core-genfail-2026-10-14.csv`](act-vector-core-genfail-2026-10-14.csv):
  34 ordered-indexed load/store tests (`vlox*`/`vsoxseg*`
  in Vls8/16/32) fail Sail signature *generation* with
  `Trap signature overflow in sig mode` before any DUT
  is involved, so no self-checking ELF exists for them;
  9 Vx64 `vmulh`/`vsmul` tests are deselected by ACT's
  extension filter because their test config requires
  full `V`. Unordered indexed (`vlux*`/`vsux*`) and
  `vmulh` at SEW 8/16/32 are inside the passing set.
- Not re-run at this stage: the SoC Linux/KVM smokes
  (green at stages 6/7) and riscv-tests (123/123 at
  stage 7); scalar behavior is covered here by
  `make core-test` and the I/M ACT ELFs above.

## In-house core stage 9 — floating-point V vector (2026-10-14, #29)

- Scope: FP vector classes (Zve32f/Zve64f/Zve64d) in
  `muserisc_decoder.sv` (OP-V funct3 001/101 carve-out),
  `muserisc_vec.sv` (per-element execution through the
  shared scalar `fp_eval`/`fp_estimate` in
  `muserisc_fpu_pkg.sv`, extracted in stage 9a), and
  `muserisc_core.sv` (FP scalar operand from the FP
  regfile, accrued `fflags`, FS/SEW/frm legality).
  Covers binary/widening arithmetic, FMA (incl. the
  `vfwmacc` family), compares, sqrt/class,
  `vfrec7`/`vfrsqrt7` estimates, all conversions
  (incl. round-to-odd `vfncvt.rod`), ordered/unordered
  reductions, and FP moves/slides. Full `V` and FP16
  (the ACT Vf16 suite) are **not** claimed; `misa.V`
  remains set on the integer+FP subsets above.
- First-party gates: vector unit TB **1,014,624 checks**
  (HOST-oracle FP section incl. estimates and ROD),
  `fpvec_directed.S` + all suites inside
  `make core-test`, `make lint` green, FPU TB unchanged
  at **690,071 checks**. The `vfrec7`/`vfrsqrt7` tables
  were extracted from the Sail reference with an
  exponent/fraction/sign sweep probe and verified
  bit-exact (results and flags) over 10,792
  operand/result pairs, then re-verified on the DUT by
  signature diff of the same probe programs.
- ACT FP-vector result:
  [`act-fpvector-stage9-2026-10-14.csv`](act-fpvector-stage9-2026-10-14.csv)
  records all 162 generated self-checking ELFs run on
  the core (100 Vf32 + 62 Vf64): **162/162 PASS**.
  Generation: `EXTENSIONS=Vf32,Vf64
  ./scripts/build_act4_core.sh` after declaring
  Zve32f/Zve64f/Zve64d in `sw/act4-core/` and setting
  the Sail `support_level` to `Float_double`.
- Tests not run: the privileged `ExceptionsVf*` suites
  are deselected by the ACT framework for this DUT
  config because their test config requires `Zfhmin`
  and full `V`; FP-vector illegality (FS off, reserved
  `frm`, SEW<32) is covered by `fpvec_directed.S` and
  Sail probes instead. 4 of the 66 Vf64 sources
  (`vfmv.f.s`, `vfmv.s.f`, `vfslide1up.vf`,
  `vfslide1down.vf`) generated no ELF because their
  test config requires full `V`; the same instructions
  are covered in Vf32 above and in `fpvec_directed.S`.
  Integer ACT spot re-runs (Vx32, I) after the stage-9
  changes are recorded in the issue.

## Crypto/SoC RTL SystemVerilog port (2026-10-14, #19)

- `rtl/crypto/*.v` and `rtl/soc/muserisc_soc_top.v`
  ported to `.sv` (behavior-identical: `logic`,
  `always_ff`/`always_comb`, typed `automatic`
  functions). Function bodies keep assignment-to-name
  style because the Yosys classic frontend rejects
  `return` statements.
- Gates after the port: `make test` → `TB_SHA256 PASS`,
  `TB_KECCAK PASS`, `TB_SHA512 PASS`, `TB_EC_FIELD
  PASS`, `TB_MUSE_CRYPTO_TOP PASS`,
  `ALL PHASE-0 KATs PASS` (iverilog `-g2012` against
  the unchanged `tb/*.v` benches); `make lint` and
  `make core-test` green.
- Synthesis: local Yosys `read_verilog -sv` clean, and
  the ORFS synth stage re-ran on the `.sv` sources via
  `scripts/openroad_docker.sh
  results/nangate45/muse_crypto_top/base/1_2_yosys.v`
  (exit 0, no synth-log errors). The full P&R flow was
  **not** re-run for the `.sv` sources; the b3 GDS
  evidence above remains the P&R record for this
  (behavior-identical) design.
- Remainder of #19: migrating the `tb/*.v` benches to
  Verilator/cocotb is still open.

## Crypto testbench Verilator migration (2026-10-14, #19)

- The five Icarus benches (`tb/tb_sha256.v`,
  `tb/tb_sha512.v`, `tb/tb_keccak.v`, `tb/tb_ec_field.v`,
  `tb/tb_muse_crypto_top.v`) are replaced by C++
  Verilator benches in `tb/cpp/` with the same KAT
  vectors and pass markers: `sha256_tb.cpp`,
  `sha512_tb.cpp`, `keccak_tb.cpp`, `ec_field_tb.cpp`,
  and `crypto_top_tb.cpp`.
- Build/run wiring lives in `sim/Makefile` (`make -C sim
  crypto`); the top-level `make test` now runs the
  Python golden models plus those targets and still
  ends with `ALL PHASE-0 KATs PASS`. Icarus Verilog is
  no longer a host prerequisite for the fast gates.
- No RTL changed in this step.

## QEMU reference-boot oracle spike (2026-10-14, #30)

- QEMU cannot execute RTL; it is used only as a fast
  software oracle for the same Linux payload. The
  Verilated `soc_tb` log above remains the only
  "Linux on our RTL" evidence. Full note and decision:
  [`docs/QEMU.md`](../QEMU.md).
- System mode: `scripts/qemu_reference_boot.sh` boots
  the exact `build/linux/Image` from the stage-6 gate
  under `qemu-system-riscv64 -machine virt` (Docker,
  QEMU 8.2.2, bundled OpenSBI v1.3) and diffs the
  platform-independent markers (kernel banner,
  `muserisc init`, `uname`, `/proc/version`,
  `MUSERISC_LINUX_BOOT_OK`) against
  `core-stage6-linux-boot-2026-10-14.log`: **match**
  (`QEMU REFERENCE BOOT PASS`). Captured log:
  [`qemu-virt-reference-boot-2026-10-14.log`](qemu-virt-reference-boot-2026-10-14.log)
  (263 lines). All remaining deltas are platform/DT/
  firmware/harness (virt DT, OpenSBI version, 256 MiB
  vs 128 MiB RAM, PLIC interrupt count, baud reporting,
  no cycle count); none is a core-behavior difference.
- User mode: `scripts/qemu_user_oracle.sh` builds
  `sw/qemu/user_oracle.c` as a static RISC-V binary
  and runs it under `qemu-riscv64`, producing
  `MUSERISC_QEMU_USER_OK x=655d5f49 sum=325770522
  acc=17500.0`.
- Decision: boot-log marker diffing plus the user-mode
  smoke are sufficient. A lockstep trace-compare
  harness is not worth building now, because QEMU
  virt and `soc_tb` differ as platforms; ISA-level
  differential coverage already comes from
  riscv-tests, ACT vs Sail, and the unit TBs.

## OpenROAD P&R rerun on current .sv sources (2026-10-14, #31)

- Full ORFS rerun of the nangate45 `muse_crypto_top`
  macro on the current `.sv` sources. This supersedes
  the #19 note above ("full P&R was not re-run"): it
  has now been re-run. Scope is the crypto macro
  only — GDS generated / place-and-route complete,
  not a tapeout, not full-SoC closure (#11), and no
  core-timing claim. Full log with the b3 comparison
  table:
  [`openroad-nangate45-31-2026-10-14.log`](openroad-nangate45-31-2026-10-14.log).
- Rerun 1 (b3 cell ban) closed timing but liberty
  signoff (`scripts/orfs_liberty_check.sh`) found 3
  new max-capacitance violators, all AOI221_X1
  (13.81 fF limit) or OAI221_X1 (22.16 fF).
  `flow/designs/nangate45/muse_crypto/config.mk`
  now also bans those two cells.
- Rerun 2 (released): setup WS 4.34 ns, hold WS
  0.039 ns, setup/hold TNS 0 at the 10 ns
  (100 MHz) constraint; ORFS fmax estimate
  176.7 MHz; 63,474 stdcells, die 308,436 um2,
  utilization 0.321, total power 0.0211 W; route
  DRC 0, antenna 0, liberty max-cap/max-slew/
  max-fanout violators 0. `6_final.gds` (60 MB) is
  published as a GitHub release asset, not in git.

## Synthesizable RTL SoC: core + fabric + crypto (2026-10-15, #4)

- `rtl/soc/muserisc_soc_top.sv` now integrates the
  in-house core with a synthesizable fabric, boot ROM
  (0x1000), CLINT, PLIC (32 sources, UART=10), 16550
  UART, and the crypto accelerator at `0x2000_0000`
  behind a scalar-MMIO→AXI4-Lite bridge; the core
  gains `dmem_stall_i` to park MEM during AXI
  transactions. RAM is external at the `mem_*` ports
  (simulation model here; ASIC SRAM wrapper / FPGA
  BRAM-DDR later). Full log:
  [`soc-rtl-4-2026-10-15.log`](soc-rtl-4-2026-10-15.log).
- On-core crypto proof (`make -C sim socrtl`,
  `sw/soc-tests/crypto_soc_test.c` on `soc_rtl_tb`):
  `SOC CRYPTO PASS` at 11,097,819 cycles — SHA-256,
  field-mul KAT, Jacobian 2·G, and secp256k1 ECDSA
  verify of the `sw/ec_ops.py` frozen vector, all
  field ops (incl. scalar inverse via custom
  modulus n) on the accelerator. Ed25519 verify is
  not yet ported and remains open on #4.
- Platform proof: OpenSBI v1.9 boots on the RTL SoC
  (ACLINT + uart8250 reported from the RTL devices)
  and enters the S-mode payload: `HELLO FROM S-MODE`,
  `SOC RTL TB PASS` at 5,978,097 cycles. This is
  not a Linux boot on the RTL SoC — Linux evidence
  remains the `soc_tb` C++ platform above; ASIC
  timing is #11, FPGA hardware is #32.

## Multi-cycle synthesizable FPU + EX-stage stall protocol (2026-10-15, #32)

- `rtl/core/muserisc_fpu.sv` is a multi-cycle F/D unit. An FSM
  runs over registered stages; div/sqrt is a radix-2 restoring
  recurrence at `FPU_DS_BITS` (2) steps per cycle;
  normalisation uses log-depth leading-zero shifters; rounding
  is a separate stage; there are no data-dependent loops. The
  arithmetic lives in `rtl/core/muserisc_fpu_ops.svh`, which is
  `include`d both by the module and by `muserisc_fpu_pkg.sv`,
  whose `fp_eval` chains the same functions combinationally
  for the (still combinational) vector FP path. Per-op latency
  and the generic EX-stage req/done/ack/kill handshake are in
  [`docs/CORE.md`](../CORE.md) ("EX-stage multi-cycle units").
  All numbers below:
  [`fpu-multicycle-upstream-2026-10-15.log`](fpu-multicycle-upstream-2026-10-15.log).
- FPU unit TB vs SoftFloat: **476,563 checks**, also on the
  `FPU_DS_BITS = 1` build (`make -C sim fpu-ds1`). The TB
  covers random/special/boundary operands for every op × both
  formats × 5 IEEE modes, round-to-odd and NaN-boxing. On the
  handshake side it checks randomized ack delays (HOLD),
  operand scrambling while busy, back-to-back issue, mid-op
  kills/request drops and in-flight resets, and every op's
  latency. TestFloat (`scripts/testfloat_fpu_vectors.sh`,
  berkeley-testfloat-3 a9c849f1, level 1, seed 42, 36 F/D ops
  × 5 rounding modes): **64,648,560/64,648,560 PASS**
  (1,163 s).
- Coverage (merged `make core-test`): `muserisc_fpu.sv` line
  39/39, branch 22/22, toggle 3,682/3,698; the untoggled
  points are flag bits that are constant by construction.
  `muserisc_fpu_ops.svh` line 123/123, branch 156/156.
  Verilator collects no line coverage inside package
  functions; the module-local `include` makes the arithmetic
  visible. `fpu_tb` now writes its coverage before freeing the
  model.
- Directed tests:
  - `fp_directed.S` tests 11–16: dependent chains through
    multi-cycle ops; int, store and branch consumers; FP
    load-use; fflags ordering vs CSR accesses; dynamic rm
    sampled at issue.
  - `fp_stall_directed.S`:
    - an older trap or vector-load fault kills an in-flight
      fdiv, which then replays cleanly;
    - FP ops completing during an older vector load's
      `mem_stall` park in HOLD;
    - FP ops in branch/jump shadows never execute;
    - precise ecall/illegal right after long ops;
    - FS dirtying;
    - vector ops interleaved with fdiv/fsqrt;
    - the held-EX operand refresh (test 4 fails on the
      previous core: a scalar operand of an instruction held
      by `vec_wb_stall` went stale once its producer retired).
  - `fp_irq_directed.S`: timer IRQ at 48 consecutive offsets
    across in-flight ops; results identical to an IRQ-free run.
  - `core-ds1`: the FP suites on an `FPU_DS_BITS = 1` core.
- Gates on upstream `main` 4c5a51a:
  - `make core-test` green (282 s);
  - `make lint` clean;
  - `make test` `ALL PHASE-0 KATs PASS`;
  - [`riscv-tests-core-fpu-multicycle-upstream-2026-10-15.csv`](riscv-tests-core-fpu-multicycle-upstream-2026-10-15.csv)
    **123/123**;
  - [`act-core-fpu-multicycle-upstream-2026-10-15.csv`](act-core-fpu-multicycle-upstream-2026-10-15.csv)
    **2,577/2,578**: the scalar 543/544, with only the known
    `PMPSm_cfg_A_tor_zero-00` PA0 waiver failing, plus the
    vector 2,034/2,034. No new waivers;
  - Verilator 5.020 (the CI version, Docker): lint, unit TBs,
    `make -C sim core` and the riscv-tests smoke subset pass;
  - RTL SoC: crypto firmware `SOC CRYPTO PASS`, and OpenSBI
    v1.9 + S-mode payload `HELLO FROM S-MODE` on
    `soc_rtl_tb`.
- Linux (`soc_tb`): on this base, upstream `main` itself does
  not complete the boot (S-external interrupt livelock after
  `/init`, fixed by the separate mip RMW change). The M-level
  trap trace and UART output of this branch are therefore
  compared with upstream `main`. They are cycle-identical over
  the first 30M boot cycles (710 trap events each). With the
  mip fix and the element-serial vector unit, the same FPU
  boots Linux to `MUSERISC_LINUX_BOOT_OK` at 502,782,909
  cycles.
- Synthesis (`scripts/synth_fpu.sh`):
  - Flow: sv2v v0.0.13 → Yosys → OpenROAD
    repair_design/repair_timing + OpenSTA, Nangate45 typical,
    no wire parasitics, Yosys ripple-carry adders.
  - **44,416 µm²** (35,546 cells, 1,388 flops), register-to-
    register min period **5.34 ns (187 MHz)**. Inputs and
    outputs are unconstrained. The critical path is the 2-step
    div/sqrt recurrence.
  - With `FPU_DS_BITS = 1` (div/sqrt 30/59 cycles):
    43,325 µm², 3.73 ns (268 MHz).

## Multi-cycle M unit (2026-10-16, #32)

- `muserisc_muldiv_mc` replaces the combinational M unit in EX on
  the generic multi-cycle protocol of #41 (`docs/CORE.md`, "M unit").
  Gates on the upstream stack:
  [`muldiv-multicycle-upstream-2026-10-16.log`](muldiv-multicycle-upstream-2026-10-16.log):
  lint, test, core-test (new `md_directed`, `md_irq_directed` at 72
  IRQ offsets, `md_kill_directed` late kills, `core-mdcomb`),
  riscv-tests 123/123, ACT 2,577/2,578 regenerated in-tree
  ([`act-core-muldiv-multicycle-upstream-2026-10-16.csv`](act-core-muldiv-multicycle-upstream-2026-10-16.csv),
  only the known `PMPSm_cfg_A_tor_zero-00` waiver), Verilator 5.020,
  `socrtl` + OpenSBI on `soc_rtl_tb`. Block synthesis: 28.6k µm²,
  4.69 ns reg→reg, against 49.8k µm² and 115.8 ns combinational for
  the old unit. Not run on this base: SoC `read_slang` and the Linux
  boot (combinational vector unit too slow; see the log).

## L1 I$/D$ + latency-tolerant core memory interface (2026-10-16, #32)

- `muserisc_cpu` = `muserisc_core` + `muserisc_icache` (8 KiB 2-way)
  + `muserisc_dcache` (16 KiB 4-way write-back) + `muserisc_bus_arb`
  behind one valid/ready memory bus (`docs/CORE.md`, "Memory
  interface and L1 caches"); `muserisc_soc_top` instantiates it via
  `muserisc_soc_fabric`. Gates on the upstream stack (on top of
  #43), all with the harness bus model's every-cycle request
  stability check:
  [`l1cache-upstream-2026-10-16.log`](l1cache-upstream-2026-10-16.log).
- `make lint` clean; `make test` PASS; `make core-test`: 99
  `CORE TB PASS`, 0 fail, unit TBs incl. `icache_tb` / `dcache_tb`;
  every directed test (6 new: `smc_fencei`, `amo_cache`,
  `mmio_bypass`, `vm_sfence_cache`, `fp_hold_cache`, `ptw_drop`)
  runs with caches + random bus latency and with caches off,
  including the `md_irq` (72), `fp_irq` (48) and `irq_exc_race`
  (101) IRQ-offset sweeps. Coverage (merged): `muserisc_icache`,
  `muserisc_dcache`, `muserisc_bus_arb`, `muserisc_sram_sp` 100 %
  line and branch.
- riscv-tests 123/123 with caches + random latency
  ([csv](riscv-tests-core-l1cache-upstream-2026-10-16.csv)) and
  uncached ([csv](riscv-tests-core-l1cache-nocache-upstream-2026-10-16.csv)).
- ACT, the same 2,578 ELFs as #43: 2,577/2,578 with caches + random
  latency ([csv](act-core-l1cache-upstream-2026-10-16.csv)) and
  uncached ([csv](act-core-l1cache-nocache-upstream-2026-10-16.csv));
  only the known `PMPSm_cfg_A_tor_zero-00` waiver. Run with the
  parallel runner of #37 (same per-ELF verdict and 5M budget).
- `soc_rtl_tb`: crypto + ECDSA PASS (18,851,904 cycles cached +
  random latency; 34,486,744 uncached); OpenSBI + `s_hello` HELLO
  at latency 1 (11,317,000) and random latency (11,362,632).
- Cycle cost of the blocking caches (2 cycles per hit, one request
  in flight): riscv-tests 2.74x total cycles (3.15x geomean) against
  #41's CSV, uncached 3.64x; ACT 3.14x (uncached 3.81x) against
  #43's CSV; `soc_rtl_tb` crypto 1.70x and OpenSBI hello 1.87x
  against #43.
- Synthesis, `scripts/synth_caches.sh` (Yosys + Nangate45, arrays as
  black boxes): I$ 2,928 um2, D$ 13,796 um2, arbiter 259 um2
  ([log](synth-caches-nangate45-upstream-2026-10-16.log)).
- Verilator 5.020 (Docker ubuntu:24.04): lint clean, unit TBs PASS,
  `make -C sim core` PASS, `soc_tb` / `soc_rtl_tb` build,
  riscv-tests smoke 26/26.
- Not run on this base: the Linux boot (the combinational vector
  unit makes `soc_tb` too slow for a multi-billion-cycle boot).
- `priv_directed` test 11 leaves its IRQ wait loop once `irq_flag`
  is set (the test drops from 1.2M to 2,735 cycles with caches +
  random latency). Re-run after that change: `make lint` clean
  (5.048 and 5.020); `make core-test` 99 `CORE TB PASS`, 0 fail
  (344 s); riscv-tests 123/123 cached + random latency and uncached;
  stress at 20 % bus ready (seeds 401-402 x {lat 1-6 gap 2,
  `--no-cache` lat 1-4, lat 2-30 gap 6}, riscv-tests + directed):
  870 runs, 0 failures, 0 protocol errors; Verilator 5.020 unit TBs,
  `make -C sim core`, SoC builds and riscv-tests smoke 26/26 PASS.

## Element-serial vector unit + banked VRF (2026-10-15, #32)

- Change: `muserisc_vec.sv` goes from whole-group combinational
  evaluation to a 4-stage element-serial engine on a 64-bit
  datapath. It has an iterative multiplier and divider and one
  shared `fp_eval`/`fp_estimate` call.
  `muserisc_vregfile.sv` goes from a 32x512 flop array with
  three 4096-bit group read ports to three 1R1W 256x64
  byte-write RAM replicas with synchronous read, which can map
  to SRAM or BRAM.
  The MEM vector load/store sequencer in `muserisc_core.sv` now
  reads and writes VRF elements directly. It no longer has
  4096-bit EX/MEM, MEM/WB or capture registers, or an address
  multiplier.
  See [`docs/CORE.md`](../CORE.md) "Vector unit" for the design,
  the stall/trap/interrupt contract, and per-op cycle counts.
- Behavior changes (all spec-conformant):
  - every completed vector instruction resets `vstart` to 0;
  - `vslidedown` offsets near 2^64 no longer wrap;
  - segment loads never leave a partially written segment on a
    fault;
  - a CSR access or vset right behind a vector load/store
    observes its `vstart`/`vl` update;
  - fault-only-first traps only when element 0 faults, and
    trims `vl` for a fault on any later element;
  - `vmv<nr>r.v` and whole-register loads/stores honor `vstart`.
- Unit TB (`tb/cpp/vec_tb.cpp` on
  `tb/sv/muserisc_vec_harness.sv`, which is the unit plus the
  VRF):
  - randomized against an independent C++ RVV golden model for
    all 88 integer VOP classes;
  - covers SEW x LMUL (1/8..8) x vl x vstart x v0 masking x
    vta/vma x vxrm;
  - compares the whole VRF before and after every op, and
    exercises every allowed source/destination overlap;
  - also includes host-IEEE FP directed checks, a kill-mid-op
    check and cycle probes.

  `make core-test`: **VEC TB PASS (61,672 checks, 22,880
  random trials, seed 0x5eed8a)**. The seed can be overridden
  with `VEC_TB_SEED`.
- New directed test `sw/core-tests/vec_trap_directed.S`
  (`--irq-timer-after 2000`), 16 checks:
  - an M-timer interrupt during a long `vmacc` is taken at the
    next boundary, with no replay;
  - a misaligned indexed load commits the elements before the
    fault and sets `vstart`;
  - a PMP-faulting segment load leaves no partial segment and
    resumes from `vstart`;
  - FOF segment trim is visible to back-to-back
    `csrr vl` / `vsetvli x0,x0`;
  - arithmetic with `vstart>0`;
  - strided store fault;
  - FOF with element 0 masked off, and FOF with `vstart>0`;
  - FOF element-0 trap;
  - `vstart>0` and the fault-to-`vstart` rescale on
    whole-register loads/stores and `vmv1r.v`.
- Coverage (merged `make core-test`, Verilator line+toggle):
  - `muserisc_vec.sv`: every line hit. Every toggle point hit
    except some bits of `fl_q`, the flags of exact widening FP
    conversions, which can never raise OF/UF/DZ/NX.
  - `muserisc_vregfile.sv`: 100%.
- Gates on this branch (Verilator 5.048; wall-clock in
  parentheses):
  - `make lint`: clean (6 s). Also clean with Ubuntu 24.04
    Verilator 5.020.
  - `make test`: `ALL PHASE-0 KATs PASS` (42 s).
  - `make core-test`: all PASS (190 s).
  - `make riscv-tests`:
    [`riscv-tests-core-vecserial-2026-10-15.csv`](riscv-tests-core-vecserial-2026-10-15.csv)
    **123/123** (33 s).
  - `soc_rtl_tb` crypto firmware: `SOC CRYPTO PASS`,
    `SOC RTL TB PASS` at 11,097,819 cycles. `make -C sim
    socrtl` itself fails to find `crypto_soc_test.bin`: it
    `cd`s into `build/sim` and then uses a path relative to
    `sim/`. That bug is pre-existing and was worked around by
    running the binary by hand.
  - Yosys `read_slang` elaboration of the full SoC file list
    from `flow/designs/nangate45/muserisc_soc/config.mk`:
    clean in 13 s.
- ACT, full core set (I/M, priv, A/F/D/B/K/Zicond, C, Vx8-64,
  Vls8-64, Vf32/Vf64; 2,578 ELFs):
  [`act-core-vecserial-2026-10-15.csv`](act-core-vecserial-2026-10-15.csv)
  **2,577/2,578**:
  - Vx/Vls **1,872/1,872**;
  - Vf32/Vf64 **162/162**;
  - scalar+priv **543/544**, with only the existing
    `PMPSm_cfg_A_tor_zero-00` PA0 waiver failing.

  Run with `sim/run_act_core_par.sh` from #37 (32 jobs, 185 s).
  It uses the same per-ELF verdict and CSV format as
  `sim/run_act_core.sh`, writes one result file per ELF, checks
  that the row count and test names match the ELFs, and exits
  1 on any FAIL. On the equivalent development branch, a
  serial `run_act_core.sh` run matched it row for row, cycle
  counts included.

  Simulated cycles: the vector suites take 2.4-5.9x as many as
  the old single-cycle-per-instruction unit (element-serial by
  design); the scalar suites take about 5% more (the ACT
  prologue initializes vector registers).
- Synthesis
  (`scripts/synth_vec.sh`: Yosys + OpenROAD STA from
  `openroad/orfs:latest`, Nangate45 typical, 10 ns, Kogge-Stone
  carry networks, ORFS `abc_speed`, sv2v v0.0.13 pinned).
  `fp_eval`/`fp_estimate` are black-boxed in both designs by
  `flow/vec-synth/fpu_stub_pkg.sv`, and the VRF RAM replicas
  are black-boxed as SRAM macros. Log:
  [`vec-serial-synth-2026-10-15.log`](vec-serial-synth-2026-10-15.log).

  | Block | Before | After |
  |---|---|---|
  | `muserisc_vec` | Yosys did not finish elaboration (killed at 141 GiB after ~4 h; 512-way unrolled loops with 22 `*`/`/`/`%` and 15 `fp_eval`/`fp_estimate` sites per element) | **52,735 um^2**, 1,371 flops, depth **76** generic gates, worst path **3.29 ns** (inputs at 0 delay) |
  | `muserisc_vregfile` | **603,640 um^2** (16,384 flops + 3x4096-bit muxes), depth 18 | **5,254 um^2** logic + 3x 256x64 1R1W SRAM (fakeram45_512x64 is 17,302 um^2, an upper bound for each), depth 6 |

  In the ORFS SoC flow, which has no SRAM macros configured,
  the three RAM replicas synthesize as flops (49,152 bits,
  about 3x the old flat VRF's flop count) unless they are
  mapped to `fakeram45` macros.
- Linux (`soc_tb`, OpenSBI v1.9 + Linux 6.6): this RTL does not
  change the scalar pipeline when no vector instruction runs,
  and the boot runs no vector instruction. The boot livelocks
  in S-external interrupts after `/init`'s `uname`, and the
  pre-change RTL livelocks the same way, cycle for cycle. It
  passes
  (`MUSERISC_LINUX_BOOT_OK`, 508,685,709 cycles) once the
  separate `mip` CSRRS/CSRRC pin-latching fix is applied; that
  fix is upstreamed in its own PR.
