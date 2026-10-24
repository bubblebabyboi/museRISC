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

## B3 — OpenROAD closure, sigil_crypto nangate45 (2026-10-13, branch `b3-openroad`, issue #3)

- Artifact: [`b3-openroad-nangate45-2026-10-13.log`](b3-openroad-nangate45-2026-10-13.log)
  (metrics + liberty signoff extract); GDS published as
  the GitHub release asset `b3-nangate45-2026-10-13`
  (`6_final.gds`, 61 MB, not in git).
- Commands: `./scripts/openroad_docker.sh` then
  `./scripts/orfs_liberty_check.sh` (both Dockerized;
  config in `flow/designs/nangate45/sigil_crypto/`).
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
  `flow/designs/sky130hd/sigil_crypto/README.md`; no
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
  in `sigil_decoder`); harness read-data settle and
  golden-model slips in two TBs.
- Caveat: this is stage 1 of the plan in
  `docs/CORE.md` — single-cycle RV64I only. No
  compliance claim attaches to it; riscv-tests/ACT
  gates start once CSR/trap state lands (stage 3).

## In-house core stage 2 — M extension + pipeline (2026-10-13, #18)

- Artifact: [`core-stage2-2026-10-13.log`](core-stage2-2026-10-13.log)
  (clean `make core-test` extract); plan in
  [`docs/CORE.md`](../CORE.md).
- Stage 2a (commit `1f280ec`): `sigil_muldiv` (RV64M incl.
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
- New `sigil_csr` (505 lines): M/S/U CSR file with spec write
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
- New `sigil_mmu` (408 lines): unified 32-entry
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

- New `rtl/core/sigil_fpu.sv`: combinational IEEE-754
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
  FPU at 100%; `sigil_fpu.sv` 482/493 merged with ACT
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

- New `rtl/core/sigil_bext.sv`: Zba/Zbb/Zbc/Zbs, Zicond,
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

- New `rtl/core/sigil_rvc.sv`: combinational decompressor
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
  in `sigil_bext.sv`): integrated in the pipeline and
  covered by the ACT gate above plus `bext_directed.S`
  (full AES-128 FIPS-197 KAT from scalar instructions,
  SHA-256/512 sigma/sum ops).
- **Standalone accelerators** (`rtl/crypto/`):
  `sha256_block`, `sha512_block`, `keccak_f1600` and the
  256-bit `ec_field` unit behind the AXI4-Lite slave
  `sigil_crypto_top` (SHA-256 block + EC field exposed;
  Keccak engine select reserved pending a streaming
  interface; SHA-512 verified standalone, not yet behind
  the AXI top). `sigil_soc_top` exposes the AXI-Lite
  port at `0x2000_0000`, but no core/bus drives it yet —
  attaching the in-house core (Harvard SRAM ports today)
  needs a bus bridge + MMIO window + driver, which is B4
  SoC integration (#4), explicitly deferred. No core-side
  integration is claimed.
- Gap found and closed by this check: the leaf engines had
  KATs but the AXI4-Lite register layer had never been
  simulated. New `tb/tb_sigil_crypto_top.v` (wired into
  `make test`) drives the documented register map end to
  end reusing leaf-KAT vectors: SHA-256("abc") and
  SHA-256("") digests, EC field mul/sub under secp256k1
  and Curve25519 MODSEL, custom-modulus regs, STATUS
  done-clearing on CTRL write, and reserved engine 1
  leaving STATUS idle. `TB_SIGIL_CRYPTO_TOP PASS`; full
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
  [`sw/linux/sigil.dts`](../../sw/linux/sigil.dts).
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
  `sigil init: userspace alive`, reports
  `uname: Linux 6.6.0 ... riscv64`, reads `/proc/version`,
  and prints `SIGIL_LINUX_BOOT_OK`.
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
  it does not integrate `sigil_crypto_top` with the core
  (B4/#4 remains deferred).

## In-house core stage 7 — H hypervisor and KVM smoke (2026-10-14, #22)

- Stage 7a adds the virtualization mode bit, HS/VS CSR banks
  with S↔VS substitution, two-level trap delegation
  (M → HS → VS), virtual-instruction exceptions, and
  `misa.H`. Stage 7b adds two-stage Sv39 + Sv39x4 address
  translation in `sigil_mmu.sv`, including G-stage
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
  built with `SIGIL_INIT_SRC=sw/linux/kvm_smoke.c
  SIGIL_IMAGE_OUT=build/linux/Image-kvm
  scripts/build_linux_kernel.sh`) opens `/dev/kvm`,
  creates a VM and one vCPU with a 4 KiB RAM slot at GPA
  `0x1000`, and runs a four-instruction VS-mode guest. The
  guest's store of 42 to MMIO GPA `0x2000` exits with
  `KVM_EXIT_MMIO` (`addr=0x2000 len=4 write=1 data=42`),
  `/init` prints `SIGIL_KVM_OK`, and the harness reports
  `SOC TB PASS` at **502,972,620 cycles**.
- Claim boundary: this is a one-vCPU KVM entry/exit smoke
  with a four-instruction bare-metal guest on the Verilator
  platform. It is not a guest-OS boot, not SMP, not an
  AIA/IMSIC or external-interrupt-virtualization claim
  (GEILEN=0, no PLIC guest context), and not a substitute
  for a future ACT hypervisor suite.

## In-house core stage 8 — integer V vector (2026-10-14, #23)

- Scope: integer RVV 1.0 (Zve32x/Zve64x, Zvl512b) with
  VLEN=512, ELEN=64 in `sigil_vec.sv` /
  `sigil_vregfile.sv` plus the MEM-stage element
  sequencer in `sigil_core.sv`. Floating-point vector
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
  `sigil_decoder.sv` (OP-V funct3 001/101 carve-out),
  `sigil_vec.sv` (per-element execution through the
  shared scalar `fp_eval`/`fp_estimate` in
  `sigil_fpu_pkg.sv`, extracted in stage 9a), and
  `sigil_core.sv` (FP scalar operand from the FP
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

- `rtl/crypto/*.v` and `rtl/soc/sigil_soc_top.v`
  ported to `.sv` (behavior-identical: `logic`,
  `always_ff`/`always_comb`, typed `automatic`
  functions). Function bodies keep assignment-to-name
  style because the Yosys classic frontend rejects
  `return` statements.
- Gates after the port: `make test` → `TB_SHA256 PASS`,
  `TB_KECCAK PASS`, `TB_SHA512 PASS`, `TB_EC_FIELD
  PASS`, `TB_SIGIL_CRYPTO_TOP PASS`,
  `ALL PHASE-0 KATs PASS` (iverilog `-g2012` against
  the unchanged `tb/*.v` benches); `make lint` and
  `make core-test` green.
- Synthesis: local Yosys `read_verilog -sv` clean, and
  the ORFS synth stage re-ran on the `.sv` sources via
  `scripts/openroad_docker.sh
  results/nangate45/sigil_crypto_top/base/1_2_yosys.v`
  (exit 0, no synth-log errors). The full P&R flow was
  **not** re-run for the `.sv` sources; the b3 GDS
  evidence above remains the P&R record for this
  (behavior-identical) design.
- Remainder of #19: migrating the `tb/*.v` benches to
  Verilator/cocotb is still open.

## Crypto testbench Verilator migration (2026-10-14, #19)

- The five Icarus benches (`tb/tb_sha256.v`,
  `tb/tb_sha512.v`, `tb/tb_keccak.v`, `tb/tb_ec_field.v`,
  `tb/tb_sigil_crypto_top.v`) are replaced by C++
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
  `sigil init`, `uname`, `/proc/version`,
  `SIGIL_LINUX_BOOT_OK`) against
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
  `SIGIL_QEMU_USER_OK x=655d5f49 sum=325770522
  acc=17500.0`.
- Decision: boot-log marker diffing plus the user-mode
  smoke are sufficient. A lockstep trace-compare
  harness is not worth building now, because QEMU
  virt and `soc_tb` differ as platforms; ISA-level
  differential coverage already comes from
  riscv-tests, ACT vs Sail, and the unit TBs.

## OpenROAD P&R rerun on current .sv sources (2026-10-14, #31)

- Full ORFS rerun of the nangate45 `sigil_crypto_top`
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
  `flow/designs/nangate45/sigil_crypto/config.mk`
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

- `rtl/soc/sigil_soc_top.sv` now integrates the
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

## Shallow AES S-box in sigil_bext (2026-10-15, branch `aes-sbox-shallow`)

- The scalar-crypto S-box (aes64es/esm/ds/dsm/ks1i) computed
  the GF(2^8) inverse as x^254 — 8 chained variable GF(2^8)
  multiplies in a `while` loop: very deep, and rejected by
  Yosys (`Function gf_inv can only be called with constant
  arguments`). It is now a composite-field GF((2^4)^2)
  circuit (Satoh/Canright style, polynomial basis,
  GF(16) = GF(2)[w]/(w^4+w+1), z^2+z+0xA): forward and
  inverse share one tower inverter, with the AES<->tower
  isomorphism and the (inverse) affine transform folded into
  four 8x8 GF(2) matrices (λ and the isomorphism root chosen
  by exhaustive search for minimum matrix weight — unique
  minimum 110, next 112; reproduced and checked against the
  RTL by `scripts/gen_aes_tower.py --check`).
  `sigil_bext` now has eight S-box lanes, each shared by
  SubBytes/InvSubBytes and also serving aes64ks1i (lanes
  0-3), instead of 16 (+4 ks1i) S-box instances. Still
  single-cycle, combinational.
- Why not a 256-entry table per direction: per lane, table
  pair 793 um2 / 8 levels / 0.52 ns vs tower 313 um2 / 17
  levels / 1.07 ns; at unit level the critical path differs
  by 0.04 ns (2.461 vs 2.497 ns, buffered) because
  MixColumns and the result mux share the path, while tables
  cost +3,800 um2 (+17%).
- Synthesis (Yosys 0.68 + OpenSTA from `openroad/orfs:latest`,
  Nangate45 typical, 10 ns virtual clock), full log with
  method and critical paths:
  [`bext-sbox-synth-2026-10-15.log`](bext-sbox-synth-2026-10-15.log).
  Baseline = original RTL with the while loop hand-unrolled
  (the original itself does not synthesize):

  | sigil_bext | cells | area um2 | ltp levels | STA (buffered) | Yosys wall |
  |---|---|---|---|---|---|
  | original | — | — | — | Yosys error | — |
  | original, unrolled | 45,293 | 55,156 | 89 | 6.961 ns (87 cells) | 15:53 |
  | this change | 18,795 | 22,786 | 60 | 2.497 ns (32 cells) | 1:17 |

  The new ltp of 60 is the 64-bit ripple-carry `+` (Zba),
  not the AES path. Other loops in the unit (clmul, clz/ctz,
  cpop, MixColumns `gf_mul` by constants, SHA sigma) are
  constant-bound, synthesize, and are off the critical
  path — left alone.
- Unit TB ([`tb/cpp/bext_tb.cpp`](../../tb/cpp/bext_tb.cpp)):
  new exhaustive sweep of both S-boxes (all 256 inputs on
  all 8 lanes via aes64es/aes64ds, plus aes64ks1i lanes 0-3)
  against the literal FIPS-197 tables, which are themselves
  self-checked against the GF(2^8) inverse + affine
  definition; op loop extended to the unassigned encodings
  59-63 (must return 0). **60,866 checks PASS**; a single
  flipped matrix bit fails 128/256 sweep inputs (mutation
  check). Coverage of `sigil_bext.sv` from the unit TB:
  **line 100% (70/70), toggle 100% (974/974)**. Verilator
  does not instrument inlined package-function bodies, so
  the S-box internals are covered by the exhaustive sweep
  rather than line counts. Two fixes made these numbers
  real: the TB wrote coverage *after* `delete dut` (reading
  freed counters — origin/main's TB reported garbage counts
  such as 2,444,302,752 hits on one line; fixed, the old RTL
  measures 98.6% line / 92.8% toggle), and `a32z` became a
  block-local variable (its constant-zero upper half was 64
  untoggleable points). `fpu_tb.cpp` and `rvc_tb.cpp` have
  the same write-after-delete pattern (out of scope here).
- Gates: `make lint` clean (17 s); `make test`
  `ALL PHASE-0 KATs PASS` (101 s); `make core-test` green —
  all unit TBs + 32 directed core binaries incl.
  `bext_directed` (AES-128 FIPS-197 KAT in the pipeline)
  (357 s cold / 152 s rebuild); `make riscv-tests` **123/123**
  (29 s).
- ACT on the core:
  [`act-core-bext-sbox-2026-10-15.csv`](act-core-bext-sbox-2026-10-15.csv)
  **92/92 PASS**, no waivers — Zba 8, Zbb 24, Zbc 3, Zbs 8,
  Zbkb 14, Zbkc 2, Zbkx 2, Zkne 4, Zknd 5, Zknh 8, Zicond 2,
  Zcb 7 + ZcbZba 1 + ZcbZbb 3 + ZcbZmmul 1: same test names
  and verdicts as `act-core-stage7-2026-10-14.csv`. Every
  test runs exactly +263 cycles vs that file, crypto and
  non-crypto alike. Confirmed not this RTL: the same ELFs on
  a `core_tb` built from origin/main give an identical CSV
  (review round 1); the cause is the vector-register prologue
  (`vsetvli` + `vmv.v.x v0..v31`) that ACT emits since
  Zve*/Zvl* entered `sw/act4-core/sigil-core.yaml` in
  stages 8c/9. ELFs:
  `EXTENSIONS=Zba,Zbb,Zbc,Zbs,Zbkb,Zbkc,Zbkx,Zicond,Zkne,Zknd,Zknh`
  then `EXTENSIONS=Zcb` via `scripts/build_act4_core.sh`
  (17 s + cached), then `sim/run_act_core.sh` (48 s).

## mip CSRRS/CSRRC must not latch the S-mode interrupt pins (2026-10-15, #21)

- Symptom: the `soc_tb` Linux boot (OpenSBI v1.9 + Linux 6.6)
  got as far as `/init`'s `uname` line. It then took
  S-external interrupts back to back until the cycle limit,
  and every PLIC claim returned 0.
- Root cause: CSRRS/CSRRC built the new `mip` value from the
  read value, which ORs the `irq_s_ext_i` pin into SEIP and
  `irq_s_timer_i` into STIP. OpenSBI's
  `csr_set/csr_clear(mip, MIP_STIP)` on each timer event
  therefore latched a high PLIC S-context line into the
  software SEIP bit. The privileged spec says the RMW uses
  only the software bit.
- Fix: `sigil_csr` exports `rmw_rdata_o`. It equals
  `rdata_o`, except that for `mip`, SEIP and STIP are the
  software bits. The core uses it for CSRRS(I)/CSRRC(I), and
  reads still return pin | software bit. `sigil_soc_top`
  drives `irq_s_ext_i` from the PLIC, so the RTL SoC had the
  same bug.
- Regression: a new `core_tb` IRQ_CTL store (0x10000008) lets
  directed tests drive the interrupt pins.
  `irq_seip_rmw.S` and `irq_mip_rmw_variants.S` fail (tests
  4 and 3) on the 4c5a51a CSR/core RTL and pass with the
  fix. `csr_tb` checks `rmw_rdata_o`.
- Gates on this branch: `make lint` clean; `make test`
  passes; `make core-test` passes (24/24 directed);
  `make riscv-tests` 123/123; ACT on the core
  [`act-core-irq-mip-rmw-2026-10-15.csv`](act-core-irq-mip-rmw-2026-10-15.csv)
  2,577/2,578, with only the `PMPSm_cfg_A_tor_zero-00`
  waiver. `soc_rtl_tb` passes `SOC CRYPTO PASS` and
  OpenSBI + `HELLO FROM S-MODE`. Lint, unit TBs, the core
  harness and the SoC TB builds are also clean under
  Ubuntu's Verilator 5.020. Commands, counts and wall times
  are in
  [`irq-mip-rmw-21-2026-10-15.log`](irq-mip-rmw-21-2026-10-15.log).

## Multi-cycle synthesizable FPU + EX-stage stall protocol (2026-10-15, #32)

- `rtl/core/sigil_fpu.sv` is a multi-cycle F/D unit. An FSM
  runs over registered stages; div/sqrt is a radix-2 restoring
  recurrence at `FPU_DS_BITS` (2) steps per cycle;
  normalisation uses log-depth leading-zero shifters; rounding
  is a separate stage; there are no data-dependent loops. The
  arithmetic lives in `rtl/core/sigil_fpu_ops.svh`, which is
  `include`d both by the module and by `sigil_fpu_pkg.sv`,
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
- Coverage (merged `make core-test`): `sigil_fpu.sv` line
  39/39, branch 22/22, toggle 3,682/3,698; the untoggled
  points are flag bits that are constant by construction.
  `sigil_fpu_ops.svh` line 123/123, branch 156/156.
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
  boots Linux to `SIGIL_LINUX_BOOT_OK` at 502,782,909
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

- `sigil_muldiv_mc` replaces the combinational M unit in EX on
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

- `sigil_cpu` = `sigil_core` + `sigil_icache` (8 KiB 2-way)
  + `sigil_dcache` (16 KiB 4-way write-back) + `sigil_bus_arb`
  behind one valid/ready memory bus (`docs/CORE.md`, "Memory
  interface and L1 caches"); `sigil_soc_top` instantiates it via
  `sigil_soc_fabric`. Gates on the upstream stack (on top of
  #43), all with the harness bus model's every-cycle request
  stability check:
  [`l1cache-upstream-2026-10-16.log`](l1cache-upstream-2026-10-16.log).
- `make lint` clean; `make test` PASS; `make core-test`: 99
  `CORE TB PASS`, 0 fail, unit TBs incl. `icache_tb` / `dcache_tb`;
  every directed test (6 new: `smc_fencei`, `amo_cache`,
  `mmio_bypass`, `vm_sfence_cache`, `fp_hold_cache`, `ptw_drop`)
  runs with caches + random bus latency and with caches off,
  including the `md_irq` (72), `fp_irq` (48) and `irq_exc_race`
  (101) IRQ-offset sweeps. Coverage (merged): `sigil_icache`,
  `sigil_dcache`, `sigil_bus_arb`, `sigil_sram_sp` 100 %
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

- Change: `sigil_vec.sv` goes from whole-group combinational
  evaluation to a 4-stage element-serial engine on a 64-bit
  datapath. It has an iterative multiplier and divider and one
  shared `fp_eval`/`fp_estimate` call.
  `sigil_vregfile.sv` goes from a 32x512 flop array with
  three 4096-bit group read ports to three 1R1W 256x64
  byte-write RAM replicas with synchronous read, which can map
  to SRAM or BRAM.
  The MEM vector load/store sequencer in `sigil_core.sv` now
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
  `tb/sv/sigil_vec_harness.sv`, which is the unit plus the
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
  - `sigil_vec.sv`: every line hit. Every toggle point hit
    except some bits of `fl_q`, the flags of exact widening FP
    conversions, which can never raise OF/UF/DZ/NX.
  - `sigil_vregfile.sv`: 100%.
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
    from `flow/designs/nangate45/sigil_soc/config.mk`:
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
  | `sigil_vec` | Yosys did not finish elaboration (killed at 141 GiB after ~4 h; 512-way unrolled loops with 22 `*`/`/`/`%` and 15 `fp_eval`/`fp_estimate` sites per element) | **52,735 um^2**, 1,371 flops, depth **76** generic gates, worst path **3.29 ns** (inputs at 0 delay) |
  | `sigil_vregfile` | **603,640 um^2** (16,384 flops + 3x4096-bit muxes), depth 18 | **5,254 um^2** logic + 3x 256x64 1R1W SRAM (fakeram45_512x64 is 17,302 um^2, an upper bound for each), depth 6 |

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
  (`SIGIL_LINUX_BOOT_OK`, 508,685,709 cycles) once the
  separate `mip` CSRRS/CSRRC pin-latching fix is applied; that
  fix is upstreamed in its own PR.

## SoC synthesis with all large arrays on SRAM macros (2026-10-16, branch `soc-sram-synth`)

- ORFS synthesis of the whole `sigil_soc_top`, measured on the
  development tree CantelopePeel/museRISC at b634ffc (this stack plus
  #45, #48 and #35). All
  15 large arrays are macros: 3 VRF banks, 6 L1 data ways and 6 L1 tag
  ways.
  - On Nangate45 the macros are fakeram45, partly generated.
  - On sky130hd they are the OpenRAM macros prebuilt in ORFS.
- Flat results:
  - Nangate45: 504,350 µm² std cells + 158,051 µm² macros, 26,447
    flops.
  - sky130hd: 2,364,368 µm² + 6,225,284 µm², 26,453 flops.
- Unrepaired fmax (period bisection in OpenSTA):
  - Nangate45: 162 MHz.
  - sky130hd: 12.3 MHz. It is set by the OpenRAM half-cycle reads: 18.4
    MHz with the VRF outputs registered, 23.0 MHz with all 15
    registered.
- The rough sky130 placed core size is 11.8–13.5 mm².
- The VRF never presents a same-address read and write to a macro:
  S3 write combining, a full-word bypass, and a retry for partial
  writes. The `srammacro` models return whole-word garbage for that
  mode, permanently.
- Summary: [`../SOC_AREA.md`](../SOC_AREA.md). Runs, timing, collision
  statistics, mutations, gates and the vendor-model check:
  [`soc-sram-synth-2026-10-16.log`](soc-sram-synth-2026-10-16.log),
  with stat and STA reports in `soc-sram-synth-*-2026-10-16.*`.
- Gates:
  - lint (5.048, and Docker 5.020 run non-root);
  - test;
  - core-test, including `srammacro`;
  - riscv-tests 123/123;
  - `socrtl` and OpenSBI hello, cached and uncached;
  - vendor OpenRAM model run;
  - ACT 2,577/2,578
    ([`act-core-soc-sram-synth-2026-10-16.csv`](act-core-soc-sram-synth-2026-10-16.csv)),
    with only the `PMPSm_cfg_A_tor_zero-00` waiver failing.

## W0: merged PR stack #33–#50 gates (2026-10-20)

All 18 open PRs merged in dependency order on branch
`integrate-prs` (merge commits, not squashed; conflicts were
`docs/evidence/README.md` sections, `sim/Makefile` target lists,
and `tb/cpp/core_tb.cpp` where #36's IRQ_CTL test register met
#44's mbus harness; both kept). Full log:
[`w0-stack-gates-2026-10-20.log`](w0-stack-gates-2026-10-20.log).

- `make lint` clean on Verilator 5.044 (macOS), 5.048
  (`deps/`) and CI's 5.020 (ubuntu:24.04 in Docker).
- `make test`: ALL PHASE-0 KATs PASS. `make core-test`: 212
  `TB PASS` lines, no failures (1,277 s, macOS).
- `make riscv-tests`: **123/123**.
- ACT, full core set:
  [`act-core-w0-stack-2026-10-20.csv`](act-core-w0-stack-2026-10-20.csv)
  **2,577/2,578** (Vx 821/821, Vls 1,051/1,051, Vf 162/162,
  scalar+priv 543/544 with only the `PMPSm_cfg_A_tor_zero-00`
  PA0 waiver failing) — identical to the #38 result on the
  pre-stack tree. The 34 Sail generation failures listed in
  `act-vector-core-genfail-2026-10-14.csv` were moved out of
  the (uncommitted) ACT test tree before building: the current
  ACT build tool skips linking every ELF when any one Sail
  signature run fails.

## W3 / #6 — Streaming SHA-512 + Keccak/SHA3 in the accelerator (2026-10-20)

Branch `6-sha512-keccak-stream` (based on `integrate-prs`, i.e. the
#33–#50 stack). Design and register map: `docs/SPEC.md` 3/3.1
(register FIFO streaming with hardware padding; no DMA, rationale
there). RTL `rtl/crypto/sigil_hash_stream.sv`, `sha512_block.sv`
(`cont` chaining input), `sigil_crypto_top.sv` (0x8C..0xA3, AXI write
backpressure), `rtl/soc/sigil_crypto_bridge.sv` (address phase
now waits for AWREADY/ARREADY).

- KATs: [`hash-stream-make-test-2026-10-20.log`](hash-stream-make-test-2026-10-20.log)
  — `make test`, clean `build/sim`, 27 s wall: `TB_HASH_STREAM PASS`
  (70 KATs through AXI-Lite: SHA-512 ×25, SHA3-256 ×20,
  Keccak-256 ×20, SHAKE256 ×5 incl. 500-byte multi-squeeze;
  lengths 0..7, rate−1, rate, rate+1, 2·rate±1, 3·rate+5, 1000, the
  SHA-512 length-field edge 110–113 / rate+111/112, Keccak 132–135),
  plus register/abort/interleave checks, `ALL PHASE-0 KATs PASS`.
  References: Python `hashlib` (SHA-512, SHA3-256, SHAKE256);
  Keccak-256 from the in-repo sponge in `sw/hash_kat.py`, checked
  against three published Keccak-256 vectors and against hashlib
  (same sponge with domain 0x06/0x1F).
- Lint: [`hash-stream-lint-2026-10-20.log`](hash-stream-lint-2026-10-20.log)
  — `make lint`, Homebrew Verilator 5.044, clean. **Not run:** the
  CI-parity Verilator 5.020 Docker lint (Docker daemon unavailable
  locally); CI `regression.yml` covers it.
- Core gate: [`hash-stream-core-test-2026-10-20.log`](hash-stream-core-test-2026-10-20.log)
  — `make core-test` (extract), 1456 s wall, exit 0, including
  `srammacro` (SoC crypto firmware `SOC RTL TB PASS` at 18,851,904
  cycles on both fakeram45 and sky130 SRAM-macro builds, i.e. legacy
  SHA-256/field users unchanged through the modified bridge).
- RTL SoC: [`hash-stream-soc-rtl-2026-10-20.log`](hash-stream-soc-rtl-2026-10-20.log)
  — `make -C sim sochash` (builds `soc_rtl_tb`, runs
  `sw/hash-tests/hash_soc_test.c` on the in-house core): SHA-512
  ("abc", 1000 B), SHA3-256 (137 B), Keccak-256("abc"), SHAKE256
  (200 B, one squeeze) all match; `SOC HASH PASS`, cached
  104,279 cycles, `--no-cache` 343,961. SHA-512 of 1000 B costs
  22,606 cycles cached (MMIO-store bound, ~22 cycles/byte).
- Synthesizability: [`hash-stream-yosys-2026-10-20.log`](hash-stream-yosys-2026-10-20.log)
  — the CI yosys `proc; opt; stat` step on the crypto top, exit 0.
- Caveats: at SoC MMIO speed the hash buffer never fills while the
  core is busy, so the AWREADY backpressure path is exercised only
  in `hash_stream_tb` (direct AXI master, 288 stall cycles), not
  through the bridge in the SoC. Functional only, not a
  side-channel claim (see SPEC security note). Full standalone
  `make -C sim socrtl` (EC firmware, ~25 min) not rerun separately;
  the same firmware passed inside `srammacro` above.

## On-core Ed25519 + secp256k1 verify on the RTL SoC (2026-10-20, #4, branch `4-ed25519-soc`)

- New firmware `sw/soc-tests/ed25519_soc_test.c`. It runs on the
  in-house core in `sigil_soc_top` and verifies the RFC 8032
  sec. 7.1 TEST 1 and TEST 2 signatures, the same frozen vectors as
  `sw/ec_ops.py`. Every Curve25519 field add/sub/mul goes to the
  accelerator at `0x2000_0000` with `MODSEL=1`.
- Hash step: SHA-512 is not on the accelerator yet. It runs in
  software on the core, KAT-checked against SHA-512("abc") before
  use. `k = SHA-512(R||A||M) mod L` is also computed in software.
  No precomputed digests are used.
- Reject cases:
  - Flipping bit 0 of S rejects at the final point compare, after
    the full verify computation.
  - S + L (non-canonical S) rejects at the range check.
- `crypto_soc_test.c` gains stage 5, a tampered-z ECDSA reject. Its
  header already claimed this check, but `main()` never ran it.
- Both images share the `soc_crypto_drv.h` driver.
  `make -C sim socrtl` runs both; `SOCRTL_ARGS=--no-cache` runs them
  uncached.
- Results, with random bus latency in both configurations
  (cycle = the `SOC CRYPTO PASS` exit cycle):

  | Image | Cached | Uncached |
  |---|---:|---:|
  | `crypto_soc_test` (ECDSA + tamper) | 27,689,496 | 84,253,072 |
  | `ed25519_soc_test` | 28,615,074 | 87,676,446 |

  Wall time for both images: 115 s cached, 331 s uncached, on an
  Apple M3 with Verilator 5.044.
- Negative control: a scratch copy with one byte of TEST 1's R
  flipped prints `SOC CRYPTO FAIL stage 3` and times out (rc=2).
- Gates: `make lint` (4 s), `make test` (14 s) and `make core-test`
  (1,565 s) pass. `core-test` includes `srammacro`, which runs the
  changed `crypto_soc_test` on both SRAM-macro builds (27,689,496
  cycles each). Not run: the Docker Verilator 5.020 lint. This change
  touches no RTL or testbench.
- Functional proof only: the firmware is variable-time, not
  constant-time (W2/W4). Full log:
  [`soc-rtl-ed25519-4-2026-10-20.log`](soc-rtl-ed25519-4-2026-10-20.log).

## #11: full-SoC ORFS synthesis completes on both platforms (2026-10-20)

Full log:
[`soc-synth-full-11-2026-10-20.log`](soc-synth-full-11-2026-10-20.log).
The ORFS `synth` target for the whole SoC (15 SRAM macros), run on
the merged PR stack (pre-rename tree `8c3013e`) with the pinned
`openroad/orfs` image on an r7i.4xlarge:

| | nangate45 | sky130hd |
|---|---:|---:|
| Wall time | 50 min | 43 min |
| Peak memory (Yosys step) | 2.6 GB | 2.5 GB |
| Synthesized area | 0.662 mm² (662,401 µm²) | 8.590 mm² (8,589,652 µm²) |
| Cells (incl. macros) | 296,459 | 260,033 |
| `synth_check` | 0 problems | 0 problems |

Area and cell counts are identical to the #50 figures in
`docs/SOC_AREA.md`, so they hold on the full merged stack (including
the #36 mip, #45 CSR/PLIC timing and #48 PLIC changes). For contrast,
the 2026-10-15 attempt on the pre-refactor tree
([`soc-openroad-synth-11-2026-10-15.log`](soc-openroad-synth-11-2026-10-15.log))
died in slang canonicalize at the 7.65 GiB Docker limit, and on #38's
test host at 201 GB. This is synthesis only: no floorplan, placement,
routing, timing signoff or GDS for the SoC follows from it (#11 stays
open for P&R).

## Post-merge gates: W3, W1 and the Sigil rename (2026-10-20)

Full log: [`post-merge-gates-2026-10-20.log`](post-merge-gates-2026-10-20.log).
On `594c41c` (W3 + W1) and again on `95b02da` (rename on top): `make
lint` clean on Verilator 5.048 and CI's 5.020, `make test` and `make
core-test` pass, riscv-tests **123/123**, `SOC HASH PASS` and both
`socrtl` images (secp256k1 27,689,496 cycles, Ed25519 28,615,074). Full
ACT on the renamed tree (marchid now `"SIGL"`, DUT config `sigil-core`):
**2,577/2,578**, identical to the pre-rename result.

## #32: F2 FPGA feasibility — Yosys resource estimate (2026-10-21)

[`fpga-yosys-estimate-32-2026-10-21.log`](fpga-yosys-estimate-32-2026-10-21.log):
Yosys `synth_xilinx -family xcup` of the whole `sigil_soc_top` (main
`d3080d0`, behavioural SRAMs): ~110k LUTs, 31,652 FFs, 32 DSP48E2,
9 RAMB36 — roughly 8–9% of the VU47P's LUTs. Estimate only (no AWS
Shell/DDR, not Vivado); feasibility notes in `docs/FPGA_F2.md`.

## W7.1 + W7.2: registered SRAM outputs, reset synchronizer, sky130 4 KiB L1 (#11, 2026-10-20)

Full log: [`w7-sram-oreg-2026-10-20.log`](w7-sram-oreg-2026-10-20.log).
Branch `11-sky130-sram-reg`, local macOS (Homebrew Verilator 5.044):

- **Registered SRAM read outputs** (`sigil_cache_pkg::SRAM_OREG`, on
  for `SIGIL_SRAM_SKY130`, or any build with `+define+SIGIL_SRAM_OREG`):
  every L1 data/tag way and VRF port read is captured in a
  rising-edge register before any logic. Cache hits and VRF reads take
  one more cycle. Off for nangate45/FPGA/default simulation: on the
  same cache geometry it costs +46.8 % cycles on the RTL SoC crypto
  firmware and +34.7 % on the cached directed tests.
- **Reset synchronizer** in `sigil_soc_top` (async assert, two-flop
  synchronous release).
- **sky130 config:** 4 KiB direct-mapped I$ and D$ (`IC_WAYS=1
  DC_WAYS=1`): 7 OpenRAM macros, 2.914 mm² (was 15, 6.225 mm²).
- Gates: `make lint` clean (5 s), `make test` pass (17 s), `make
  core-test` pass (1,630 s; 217 TB PASS, 0 fail, `srammacro` with
  fakeram45, sky130 and the new behavioural `oreg` family, plus the
  I$/D$ unit tests with `SRAM_OREG`), riscv-tests **123/123** on the
  default, sky130 and oreg core builds, `socrtl` (both images) and
  `sochash` pass.
- Not run here: CI-parity lint (Verilator 5.020, Docker), ACT, ORFS
  synthesis/STA/P&R and `vendor_model_check.sh`. Re-measured sky130
  fmax and area are pending that synthesis run.

## sky130 RTL prep merged: gates (2026-10-21)

[`sky130-prep-gates-2026-10-21.log`](sky130-prep-gates-2026-10-21.log)
(tree `73a681a`, merged to `main` as `560463e`): lint clean on Verilator
5.048 and CI's 5.020, `make test`, `make core-test` (217 TB PASS incl.
the sky130 and oreg `srammacro` families), riscv-tests **123/123**, both
`socrtl` images and `SOC HASH PASS`; full ACT **2,577/2,578** on both
the default `core_tb` and `core_tb_sky130` (registered SRAM reads,
4 KiB direct-mapped L1s), only the PA0 waiver failing; the vendor
OpenRAM model check passes with 0 same-address read/write warnings.

## #51 FPGA F0: Vivado OOC implementation of the whole SoC (2026-10-21)

Reports in [`fpga-f0-2026-10-21/`](fpga-f0-2026-10-21/): Vivado 2025.2,
`xcvu47p-fsvh2892-2-e` (F2 Small Shell part), whole `sigil_soc_top`
synthesized, placed and routed out-of-context in 27 min. 78,699 LUTs
(6.0%), 32,463 FFs (1.25%), 9 RAMB36, 29 DSP. Setup WNS −4.703 ns at
10 ns (≈68 MHz), hold clean. Worst path: VRF BRAM read → 63 levels →
core EX/MEM result register. Details in `docs/FPGA_F2.md` (F0 result).

## #52 / FPGA F1: FPGA SoC top + mbus→AXI4 DDR bridge (2026-10-21)

[`fpga-top-52-2026-10-21.log`](fpga-top-52-2026-10-21.log), per-test
riscv-tests cycles in
[`fpga-top-rvtests-52-2026-10-21.csv`](fpga-top-rvtests-52-2026-10-21.csv).
Branch `52-fpga-soc-top`, local macOS (Homebrew Verilator 5.044).
`rtl/fpga/sigil_fpga_top.sv` wraps the unchanged `sigil_soc_top` (same
memory map / DTS) and serves its RAM window from an AXI4 master
(`sigil_mbus_axi4`, 64–512-bit data; a 64-byte line is one 512-bit
beat), with SoC reset hold/quiesce, a cycle counter and virtual-UART
FIFOs for the #54 CL wrapper. Verilator against an AXI4 DDR model
(latency 8–40, R gaps, 70% AW/W/AR ready, protocol checks):

- `axibridge` (in core-test): 9 × 20,000 random transactions vs a
  reference memory at 64/128/512 bits — PASS.
- `fpgatop` (261 s; its `fpgatop-quick` part is in core-test): smoke
  test (D$-thrashing memory test + 170-byte UART RX line, mid-traffic
  SoC reset, rerun) at 64 and 512 bits, `SOC HASH PASS`, both crypto
  images `SOC CRYPTO PASS` (27,691,528 / 28,618,145 cycles at 64-bit;
  secp256k1 27,690,766 at 512-bit) — PASS.
- `fpgatop-rvtests`: riscv-tests **123/123** uncached through the AXI
  path at 64 and 512 bits; `fpgatop-hello`: OpenSBI v1.9 + `s_hello`
  `HELLO FROM S-MODE` at 64 bits (11,491,166 cycles) and 512 bits.
- Gates: `make lint` clean, `make test`, `make core-test` (incl. the
  new targets), riscv-tests 123/123, `socrtl`, `sochash` pass.
- Not run: CI-parity lint (Verilator 5.020), ACT, any Vivado
  elaboration/synthesis/timing, any AWS work.

## #53 FPGA timing step 1: registered VRF reads (2026-10-21)

[`fpga-vrf-oreg-53-2026-10-21.log`](fpga-vrf-oreg-53-2026-10-21.log):
`SIGIL_VRF_OREG` (FPGA build) registers only the vector register file
read outputs. Vivado OOC on the F2 part: WNS −4.703 → **−4.226 ns**
(≈68 → 70.3 MHz), 79,087 LUTs. The worst path moves to the MEM stage
(address translation / PMP / trap cause into `exmem_result_q`, 68
levels) — the next #53 step. Gates: core-test 234 PASS (incl. the new
`vrforeg` srammacro family), riscv-tests 123/123, full ACT 2,577/2,578
on `core_tb_vrforeg`, lint clean on Verilator 5.044/5.048/5.020.

## #53 FPGA timing: review round 2 fixes and directed tests (2026-10-22)

[`fpga-timing-53-review2-2026-10-22.log`](fpga-timing-53-review2-2026-10-22.log):
three `FPGA_TIMING`-only divergences from `main`, found by directed
review tests, fixed on `53-mem-stage-pipeline`. An EX data capture took
a stale walk-fault record (spurious page fault on HLV/HSV/HLVX right
after a trimmed `vle*ff` of the same VA; such a capture now replays in
MEM, +1 cycle in that rare case). A fetch access fault wrote a stale GPA
to `mtval2`/`htval`. The `it_q` simulation check fired on a legal stale
translation. 21 review programs (`vm_irq` at 152 IRQ offsets) now run in
`sim/run_directed.sh`. They pass on `main` (`d7fb9a2`, `9da0006`) and on
the branch with `FPGA_TIMING` off, on and alone, and off is
cycle-identical to `main`. Gates at `08c607a` (RTL of `d8d5e92`): lint
on 5.048/5.020/5.044, `make test`, `make core-test`, `socrtl` and
riscv-tests 123/123 pass in both settings, every existing line
cycle-identical to round 1. ACT 2,577/2,578 in both settings, same
verdicts and cycles as round 1; riscv-dv vs Spike 100/100 in the FPGA
setting. Off formally equivalent to `main` `eeaa332` (`sigil_core`
default and SRAM_OREG, `sigil_csr`, `sigil_mmu`, `sigil_dcache`,
`sigil_icache`). Vivado F0 at 10 ns: WNS +0.799 ns. Not kept: two tests
that hang `main` (a misaligned vector element on an unmapped page) and
two that fail on `main` before the #74 walker fix.

## #53 FPGA timing: full gates in both settings, round 1 (2026-10-22)

[`fpga-timing-53-gates-2026-10-22.log`](fpga-timing-53-gates-2026-10-22.log):
branch `53-mem-stage-pipeline` at `116c4a4`, with `SIGIL_FPGA_TIMING`
off (default/ASIC) and on (FPGA: plus `SIGIL_VRF_OREG`), on clean
worktrees of the pushed commit. Lint clean on Verilator 5.048, 5.020 and
5.044 (29 configurations each), CI-parity unit/core/riscv-tests on
5.020; `make test`, `make core-test` (all srammacro families, examples,
`fpgatop-quick`, `vec`), `socrtl`, riscv-tests 123/123 and full ACT
2,577/2,578 (only `PMPSm_cfg_A_tor_zero-00`; Vx/Vls/Vf all pass) in
both settings; riscv-dv vs Spike 100/100 on `main` and on the branch in
the FPGA setting. Off: core-test, `socrtl`, riscv-tests and all 2,578
ACT ELFs cycle-identical to `main`, and `sigil_core` (default and
SRAM_OREG), `sigil_csr`, `sigil_mmu`, `sigil_dcache`, `sigil_icache`
formally equivalent to `main`. Yosys cell counts are not an identity
test (they change for byte-identical RTL with what else is read;
controls in the log). The round fixed a CI break (`-GFPGA_TIMING=1` on
5.020) and a `sigil_mmu` off branch that was equivalent but not
`main`'s code. Vivado F0 at 10 ns on `116c4a4`: WNS +0.614 ns.
`main` moved to `d7fb9a2` during the round with simulation-only RTL
changes; its synthesis view is byte-identical to `eeaa332`, so the ASIC
results hold against it too.

## #53 FPGA timing baseline: all failing paths, by family (2026-10-22)

[`fpga-timing-53-baseline-2026-10-22.md`](fpga-timing-53-baseline-2026-10-22.md):
`main` `eeaa332` with `SIGIL_VRF_OREG` at 10 ns (Vivado 2025.2 OOC,
WNS −4.226 ns, 18,180 failing endpoints) grouped into 13 path families
with worst slack, logic levels and endpoint counts. The new
`fpga/f0/f0_timing_reports.tcl` writes the per-endpoint reports and
peels families with the cut steps in `fpga/f0/f0_cuts.tcl`. The MEM
data translate (D-TLB + PMP in one cycle, −4.226 ns) hides almost every
endpoint; under it fail the fetch translate/PMP path (−3.857 / −2.307),
the Bext EX path (−2.163) and nine smaller families (−1.43 … −0.48 ns).

## #11: whole-SoC place-and-route on nangate45 — GDS generated (2026-10-21)

[`soc-pnr-nangate45-11-2026-10-21/`](soc-pnr-nangate45-11-2026-10-21/)
(summary in `summary.log`, overview image `final_all.jpg`). The whole
`sigil_soc_top` — in-house RV64GCV core with vector unit and L1 caches,
crypto/hash engine, CLINT/PLIC/UART/boot ROM, 15 fakeram45 macros —
through the full ORFS flow to `6_final.gds`:

| | nangate45 |
|---|---:|
| Clock / setup | 10 ns met, worst slack +0.74 ns, TNS 0 (fmax 107.9 MHz) |
| Hold | met |
| Route DRC (OpenROAD) | 0 |
| Antenna (OpenROAD ANT) | 0 net / 0 pin |
| Power connectivity (PSM) | clean |
| Die / std-cell area | 2,020 × 2,020 µm (4.08 mm²) / 0.934 mm², 23% util |
| Power | 0.129 W |

KLayout `make drc` with the FreePDK45 deck reports 179 markers (176
antenna per that deck's model, 2 `WELL.4`, 1 `METAL1.5` inside library
cell `OAI221_X4`) that OpenROAD's own checks do not flag; earlier
nangate45 releases reported only the OpenROAD checks. Runs 1–2 failed the
6_report power-connectivity check (45 cells on a rail segment in a 22 µm
macro gap with no metal4 strap); fixed with full 60 µm macro channels
(`RTLMP_MIN_CHANNEL_SIZE`, `RTLMP_PIN_AWARE_CHANNELS 0`). Wording: GDS
generated / place-and-route complete — not a tapeout.

## W7 / #11: whole-SoC sky130hd place & route in the Caravel user area (2026-10-21) — not routed

Full log: [`w7-sky130-pnr-2026-10-21.log`](w7-sky130-pnr-2026-10-21.log).
Branch `11-sky130-pnr`, ORFS image `openroad/orfs@sha256:63981d1a…`,
config `flow/designs/sky130hd/sigil_soc/`:

- **Done:** synthesis (5.92 mm², 312k cells, 7 OpenRAM macros),
  floorplan in a 2900 × 3500 µm die (inside the 2920 × 3520 µm Caravel
  user area), a design PDN (`pdn.tcl`) that connects the OpenRAM
  met3 `vdd`/`gnd` pins through met4 straps (the platform PDN failed
  with PDN-0217), placement, CTS and global routing. Setup WNS at
  40 ns (25 MHz): +3.68 ns after placement, +3.51 after CTS, +1.76
  after global routing (period_min 38.2 ns, ~26 MHz); no hold
  violations; estimated power 0.76 W.
- **Not done:** detailed routing does not converge (1,036,832
  violations after iteration 0, 842,148 after iteration 1, mostly
  signal-signal met1/met2 shorts). No GDS, DRC, antenna or post-route
  timing.
- **Cause:** routing demand. At the ORFS sky130hd default derating
  (0.5), global routing needs 122 % of the met2 capacity in the
  Caravel die; it only fits at 0.1, which detailed routing cannot
  realize. A 3700 × 4400 µm (16.3 mm²) run still had ~20,000
  overflowed gcells. An owner decision on the sky130 configuration
  (smaller design, larger die or hierarchical P&R) is needed.

## #54 / FPGA F3: AWS F2 CL wrapper, virtual UART, host runtime (2026-10-21)

Log: [`fpga-cl-54-2026-10-21.log`](fpga-cl-54-2026-10-21.log); post-route
reports in [`fpga-cl-54-2026-10-21/`](fpga-cl-54-2026-10-21/). Branch
`54-fpga-cl`. Build/sim on the EC2 r7iz.8xlarge build instance (F2
Developer AMI 1.19.2, Vivado/XSIM 2025.2, aws-fpga v2.3.5 `c34f88e`,
Small Shell `0x10212415`); Verilator 5.044 on macOS. Nothing ran on F2
hardware and no AFI was created (#55).

- **DCP build** (`fpga/scripts/build_cl_sigil.sh --recipe-b B1`, i.e.
  `aws_build_dcp_from_cl.py --mode small_shell --aws_clk_gen
  --no-encrypt`, recipes A1/B1/C0/H2): BuildAll in 1 h 07–1 h 09 min,
  "no negative slack path". Core clock `clk_extra_b1` 16 ns (B1,
  62.5 MHz): WNS **+0.147 ns** (≈63.1 MHz), `clk_main_a0` +0.197 ns,
  DDR +0.213 ns, design +0.070 ns, hold +0.010 ns. CL: 122,329 LUTs
  (9.4%), 95,551 FFs, 71 RAMB36 + 3 RAMB18, 32 DSP; SoC 80,529 LUTs.
  Worst core path: VRF BRAM read → 43 levels → D$ data RAM enable.
- **XSIM** (HDK testbench, fast AXI memory model): `test_sigil_regs`
  (register map, PCIS ↔ DDR, measured 62.5 MHz), `test_sigil_hash`
  (`SOC HASH PASS`, 104,734 cycles at 62.5 MHz) and
  `test_sigil_host_cosim` (the unchanged `fpga/host/sigil_host.c` via
  DPI: `SOC HASH PASS`, measured 62.500 MHz) — PASS. Long images at
  the B5 recipe (100 MHz, for simulation speed): `FPGA SMOKE PASS`
  (11,740,850 cycles), OpenSBI v1.9 → `HELLO FROM S-MODE`
  (11,451,667), `crypto_soc_test` `SOC CRYPTO PASS` (27,690,806),
  `ed25519_soc_test` `SOC CRYPTO PASS` (28,617,201) — PASS (5–12 h
  wall each).
- **Verilator** `make -C sim fpgaocl` (`fpgaocl-quick` added to
  core-test): `sigil_fpga_ocl` driven only through its OCL registers —
  `SOC HASH PASS` (105,056), `FPGA SMOKE PASS` (11,791,881),
  `SOC CRYPTO PASS` (27,690,936) — PASS; `axibridge`, `fpgatop-quick`
  re-run after the `sigil_mbus_axi4` assertion rewrite — PASS;
  `make lint` clean (new: `sigil_fpga_ocl`, `sigil_axi_decerr`);
  `scripts/rename_to_sigil.sh check` clean.
- Host runtime builds `-Wall -Wextra -Werror` against the v2.3.5 SDK
  (static `libfpga_mgmt.a`).
- Not run: F2 hardware, AFI creation, CI-parity lint (Verilator 5.020;
  no Docker daemon), full `make core-test`, Linux in XSIM (~a week at
  ~800 cycles/s).

## #55: whole SoC on a real AWS F2 FPGA — Linux boots (2026-10-22)

[`f2-first-boot-55-2026-10-22/SUMMARY.md`](f2-first-boot-55-2026-10-22/SUMMARY.md)
with every host log and UART capture. Public AFI
`agfi-035116450e0a0d093` on an `f2.6xlarge`, core at a measured
**62.500 MHz**: hash engine, 512 KiB DDR4 test + UART RX, secp256k1
ECDSA and Ed25519 verify (tampered inputs rejected), OpenSBI to S-mode,
and **Linux 6.6 to userspace**. Runs used `sigil_host --ignore-mem-err`
(#62); UART character drops (#63) and pre-rename Linux payloads (#64)
are tracked.

## SDK examples on F2 hardware (2026-10-22)

[`f2-sdk-examples-2026-10-22/SUMMARY.md`](f2-sdk-examples-2026-10-22/SUMMARY.md):
all 7 `sw/examples` programs (hello, timer_irq, sha256_accel,
hash_stream, ed25519_verify, vector_dot, fp_math) pass on the public AFI
on a real `f2.6xlarge`, built on the instance with Ubuntu GCC 13.2.

## #56: performance harness, first baseline — Dhrystone 2.1 (2026-10-22)

[`perf-dhrystone-56-2026-10-22/`](perf-dhrystone-56-2026-10-22/report.md):
`report.md`, `results.csv`, `results.json` (every counter plus
metadata), `runs/` (UART log and `SIGIL_PERF` record of all 32 runs),
the build logs with the full compiler command lines,
`synth-view-diff.log`, `cross-sim-5.020.log` and `gates.log`. Method:
[`docs/PERFORMANCE.md`](../PERFORMANCE.md).

- **Design.** main `eeaa332` RTL, measured before any #53 pipelining.
  Harness commit `534f846` (branch `56-perf-harness`) adds only
  `` `ifndef SYNTHESIS`` code. `scripts/synth_view_diff.sh eeaa332
  534f846` shows the preprocessed RTL is byte-identical under
  `SYNTHESIS` alone and with `SIGIL_SRAM_FAKERAM45`,
  `SIGIL_SRAM_SKY130`, `SIGIL_SRAM_OREG` and `SIGIL_VRF_OREG`
  (`synth-view-diff.log`).
- **Run.** `make -C sim perf BENCHES=dhrystone CONFIG="default sky130
  oreg fpga" MEM="soc axi" JOBS=4 REPEAT=2 VJOBS=4` on sigil-verify
  (c7i.8xlarge, Ubuntu 24.04), results written 2026-10-22T08:34:51Z, with Verilator 5.048
  and riscv64-unknown-elf-gcc 16.1.0 (`deps/`). The 8 testbench builds
  plus 32 simulations took 4 min 33 s. Earlier runs at `623c576` and
  `e3b40fc` (same counter logic) gave byte-identical records.
- **Benchmark.** Dhrystone 2.1 (netlib `dhry-c`, ported:
  `sw/bench/dhrystone/README.md`), 2000 runs. Flags: `sdk.mk` (`-O2
  -mstrict-align -mcmodel=medany -ffreestanding -std=gnu11`, separate
  compilation, no LTO) plus `-fno-inline` (ground rules). Two variants:
  - `scalar`, the headline:
    `-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`;
  - `sdk`: the SDK default `-march`, with V.
- **Memory models.**
  - `soc`: `soc_rtl_tb`, fixed 1-cycle first-beat latency.
  - `axi`: `fpga_top_tb`, through the 64-bit `sigil_mbus_axi4` bridge,
    with a fixed 24-cycle AXI latency.
- **Validation.** 32/32 runs valid:
  - the program self-checked every final value;
  - `cycles` = `mcycle` delta and `instret` = `minstret` delta;
  - the accounting sums to `cycles`;
  - both repeats are identical in all 91 record fields;
  - the same images on a Verilator 5.020 build give identical records.

DMIPS/MHz (= 2000 / cycles × 10^6 / 1757, over the `Number_Of_Runs`
loop):

| Variant | Memory | default | sky130 | oreg | fpga (VRF_OREG) |
|---|---|---:|---:|---:|---:|
| **scalar** | soc | **0.371** | **0.216** | 0.225 | **0.371** |
| scalar | axi | 0.371 | 0.201 | 0.225 | 0.371 |
| sdk (V) | soc | 0.327 | 0.191 | 0.202 | 0.317 |
| sdk (V) | axi | 0.327 | 0.173 | 0.202 | 0.317 |

Scalar, default, soc: 3,070,244 cycles and 1,036,022 instructions,
IPC 0.337, 1,535 cycles per Dhrystone. The cycles break down as:

| Category | % of cycles |
|---|---:|
| retire | 33.7 |
| fetch: I$ hit latency / issue gap | 40.6 |
| fetch: 32-bit instruction straddles a fetch word | 8.9 |
| MEM: D$ hit latency | 12.7 |
| squashed wrong-path instructions | 3.7 |
| M unit | 0.2 |
| load-use | 0.1 |

Observations:

- **Fetch dominates.** The core issues one fetch per 2 cycles (3 with
  `SRAM_OREG`) and refetches the word for the second compressed half.
  Fetch costs 49.5% of cycles, at 1.45 I$ accesses per instruction.
- **`SRAM_OREG` alone costs +65% cycles.** On top of that, the sky130
  4 KiB direct-mapped D$ adds 4 conflict misses per Dhrystone: +4.1%
  of cycles at 1-cycle memory, +12.0% behind the AXI model. sky130 is
  the only configuration where Dhrystone is memory-latency sensitive.
- **V code generation is slower here.** GCC turns the 56-byte record
  copy into `vle8`/`vse8`, which takes 19.3% of cycles on the
  element-serial vector LS. The `sdk` build is 13.4% slower than
  `scalar`.
- **Effective miss penalties.** I$: 12 cycles (soc) and 37 (axi).
  D$: 21–27 (soc) and 62–77 (axi).
- **Projection only:** at F2's 62.5 MHz, the scalar figure is about
  23 DMIPS. No hardware run.

Gates on `534f846` (`gates.log`):
- `make lint` is clean on Verilator 5.048, 5.020 (CI version) and 5.044.
- `make test` passes.
- `make core-test`: 235/235 `TB PASS` lines, identical to a core-test
  run of main `eeaa332` on the same host apart from wall-clock seconds.
  Every cycle count is the same, including the SDK examples. Coverage
  is identical: 55.00% (3491/6252).
- riscv-tests: 123/123.

## #56: CoreMark on the performance harness (2026-10-22)

[`perf-coremark-56-2026-10-22/`](perf-coremark-56-2026-10-22/README.md):
`report.md`, `results.csv`, `results.json`, `runs/` (UART log and
`SIGIL_PERF` record of all 12 runs), the build logs, `fetch.log`
(pinned-source fetch and checks), `host-reference.log` (native x86-64
CRC references), `long-1000/` (10 s rule), `flag-sweep/` (`-O2` vs
`-O3`/`-Os`), `image-check.log`, `rerun-final.log` and
`cm_long_run.py`. Port and method:
[`sw/bench/coremark/README.md`](../../sw/bench/coremark/README.md).

- **Design.** `rtl/` tree `89b98cb227c6`: main `eeaa332` plus the
  harness's simulation-only counters, as in the Dhrystone entry above.
  No #53 pipelining.
- **Benchmark.** EEMBC CoreMark 1.0, eembc/coremark `b56889a7`,
  unmodified, fetched into the git-ignored `third_party/coremark` and
  sha256/md5-checked. 2K data set, data on the stack, 20 iterations,
  `-O2`, every file with the same flags, no LTO. Commit `320cf57`
  (branch `56-perf-coremark`); the final code `4526052` rebuilds
  byte-identical images.
- **Run.** `make -C sim perf BENCHES=coremark CONFIG=default MEM="soc
  axi" REPEAT=2 JOBS=12` on sigil-verify, results written
  2026-10-22T09:39:42Z, Verilator 5.048, riscv64-unknown-elf-gcc
  16.1.0.
- **Validation.** 12/12 runs valid and deterministic. The port checked
  the seed, list, matrix and state CRCs and `crcfinal` against a native
  x86-64 build of the same sources; both EEMBC seed sets validate (run
  rule 2).

| Variant | soc | axi |
|---|---:|---:|
| **scalar** (`rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`), CoreMark/MHz | **1.395** | 1.395 |
| sdk (with V) | 1.372 | 1.372 |
| validation seeds (scalar) | 1.392 | 1.392 |

- Scalar, soc: 14,337,806 cycles for 20 iterations, IPC 0.366. Fetch
  latency and straddles take 45.8% of cycles; the L1s hold CoreMark
  (39 I$ and 11 D$ misses, all cold), so the 24-cycle AXI model adds
  only 1,250 cycles.
- **10 s rule.** 1000-iteration runs (`long-1000/`, about 70 minutes
  of simulation each, 11.5 s of region at 62.5 MHz) give the same
  1.395 (performance seeds) and 1.392 (validation seeds), and CoreMark
  printed `Correct operation validated`.
- `-O3` is 19% slower than `-O2` here (more straddling fetches), so
  `-O2` is the headline.
- Only the default configuration was measured; sky130, oreg and fpga
  are still to run.

## #56: vector and FP kernels, C vs RVV (2026-10-22)

[`perf-kernels-56-2026-10-22/`](perf-kernels-56-2026-10-22/README.md):
13 kernels from `sw/bench/kernels`: int32/int64 add, daxpy, saxpy, fp64
and int32 dot products, memcpy and memset (e64 and e8), 32x32
dgemm/sgemm, a 16-tap fp32 FIR, and int8/int16 widening MACs. Each runs
as scalar C and as RVV intrinsics and is checked bit for bit against a
scalar reference, which is in turn checked against a known answer from
an exact host model.

- **Run.** Default configuration, `soc` and `axi` memory models, two
  repeats. Commit `7ea3e51` (branch `56-perf-kernels`), main `eeaa332`
  design, Verilator 5.048, GCC 16.1.0.
- **Validation.** 224/224 region results valid and deterministic. Fault
  injection: 7 wrong results, 7 failed runs.
- **RVV speedup over scalar C** (soc): 1.51–2.96x (memset 2.96x,
  fir_f32 2.56x, memcpy 2.51x, sgemm 2.07x, dgemm 1.85x, idot 1.51x).
  The e8 forms of memcpy/memset are 2.5–3x *slower* than scalar.
- **Bottlenecks.**
  - Vector load/store: about 3 cycles per element.
  - FP vector ops: 8 cycles per element (`vfmacc` = 8N + 4).
  - Scalar C: front-end bound, IPC 0.22–0.42.
- **GCC 16 `-O3` auto-vectorization** reaches 1.0–1.67x.
- **Caveat.** Shifting the scalar C code by 2 bytes moves its cycles by
  -24% to +26%, from 32-bit instructions straddling a 4-byte fetch
  word. The kernels are therefore 64-byte aligned.

## #56: performance harness, microbenchmarks (2026-10-22)

[`perf-micro-56-2026-10-22/`](perf-micro-56-2026-10-22/micro_table.md):
`micro_table.md` (cycles per operation for every region, where the
cycles go per operation, derived cache parameters), the harness's
`report.md`, `results.csv` and `results.json`, `runs/` (UART log and
`SIGIL_PERF` records of all 20 simulations), `build-micro_*.log`
(full compiler command lines), `perf-run.log` (harness console) and
`determinism.log`. Method:
[`sw/bench/micro_common/README.md`](../../sw/bench/micro_common/README.md).

- **Design.** `rtl/` tree `89b98cb227c6`: the harness branch's RTL
  (`534f846`, main `eeaa332` plus the simulation-only counters, see the
  Dhrystone entry above). Measured before any #53 pipelining. The
  benchmarks are on branch `56-perf-micro` (`904d59e`), which adds only
  `sw/bench/micro_*` to `56-perf-harness` `d2b3df4`.
- **Run.** `make -C sim perf BENCHES="micro_pipe micro_units micro_dmem
  micro_imem micro_vec" CONFIG=default MEM="soc axi" REPEAT=2 JOBS=10`
  on sigil-verify (c7i.8xlarge, Ubuntu 24.04), results written
  2026-10-22T09:54:30Z, Verilator 5.048, riscv64-unknown-elf-gcc
  16.1.0 (`deps/`). 20 simulations in 34 s.
- **Benchmarks.** Five benchmarks, 105 regions, each region one
  mechanism running exactly `iterations` operations (assembly kernels,
  unrolled loops), so the harness's cycles/iteration is cycles per
  operation. Each benchmark has an `empty` region that measures the
  window's own cost (66–81 cycles soc, 91–131 axi); `micro_table.md`
  also lists every value net of it.
- **Validation.** 420/420 region results valid (105 regions x 2 memory
  models x 2 repeats):
  - every kernel result matched its value computed in C (sums, counts,
    nodes reached, stored elements), and each program printed `MICRO
    CHECK OK`;
  - in every record, `cycles` = `mcycle` delta, `instret` = `minstret`
    delta and the accounting sums to `cycles`;
  - both repeats are identical, and a second harness invocation at
    `49352b9` (same images, sha256 in `determinism.log`) gave identical
    records too: 4 identical runs of each of the 210 (region, memory
    model) pairs.

Cycles per operation, default configuration, raw as the harness
reports them. micro_pipe, micro_units and micro_vec show soc; axi is
within 0.1 cycles of it for every region in those three:

| micro_pipe | cycles/op |
|---|---:|
| `add` 32-bit, dependent or independent | 2.04 |
| `c.add` 16-bit | 2.04 |
| 32-bit `add` straddling two fetch words | 4.06 |
| branch not taken | 2.04 |
| branch taken; `jal` | 4.04 |
| call + `ret` with a one-instruction callee (`jal` or `jalr`) | 10.04 |
| loop trip (`addi` + taken `bnez`) | 6.02 |
| data-dependent branch: never / always / alternating / random 50% taken | 8.61 / 10.61 / 9.61 / 9.61 |
| `ld` hit, dependent (load-to-load) | 3.03 |
| `ld` hit, independent; `sd` hit | 2.54 |
| `ld` + `add` using it, distance 1 / distance 2 (per pair) | 4.04 / 4.04 |
| `rdcycle`, `rdtime`, `csrr`, `csrw`, `csrrw`, `fence` | 2.04 |

| micro_units | dependent | independent | docs/CORE.md EX cycles |
|---|---:|---:|---:|
| `mul` | 4.20 | 4.19 | 3 |
| `div`, 63 quotient bits | 36.18 | 36.18 | 35 |
| `div`, dividend < divisor | | 4.15 | 3 |
| `divw`, 31 quotient bits | 20.18 | | 19 |
| `rem`, 62 quotient bits | | 35.17 | 34 |
| `fadd.d` / `fmul.d` | 6.20 / 6.18 | 6.16 | 5 |
| `fmadd.d` | 8.19 | | 7 |
| `fdiv.d` / `fsqrt.d` | 33.17 / 33.17 | 33.17 / 33.15 | 32 |
| `fdiv.s` / `fsqrt.s` | 18.18 / 18.17 | | 17 |

| micro_dmem (one 64-byte line per load) | soc | axi |
|---|---:|---:|
| random chase, 1–12 KiB | 3.10 | 3.10 |
| random chase, 16 KiB | 3.12 | 3.18 |
| random chase, 20 / 24 / 32 KiB | 7.47 / 9.93 / 12.24 | 17.43 / 25.47 / 33.03 |
| random chase, 64 / 128 / 256 KiB | 13.96 / 14.11 / 14.11 | 38.67 / 39.15 / 39.15 |
| address-order chase, 4 / 8 / 16 / 32 KiB | 3.10 / 3.10 / 3.12 / 10.48 | 3.10 / 3.11 / 3.18 / 27.27 |
| load stream, per 8-byte `ld` | 4.27 | 7.41 |
| store stream into dirty lines, per 8-byte `sd` | 6.25 | 13.02 |

| micro_imem (straight-line 32-bit code), cycles/instruction | soc | axi |
|---|---:|---:|
| footprint 1–4 KiB | 2.01–2.06 | 2.01–2.06 |
| 6 / 8 KiB | 2.04 / 2.03 | 2.11 / 2.09 |
| 12 / 16 / 24 / 32 KiB | 2.47 / 2.53 / 2.58 / 2.61 | 3.52 / 3.71 / 3.89 / 3.98 |

| micro_vec | cycles per vector instruction |
|---|---:|
| `vsetvli`, same vtype / alternating vtype | 2.43 / 2.49 (2.12 / 2.17 net of window) |
| `vadd.vv` e8, vl = 1 / 8 / 64 / 512 | 7.43 / 14.40 / 70.40 / 518.40 (N + 6.4) |
| `vadd.vv` e64, vl = 8 | 14.41 |
| `vle8.v`, vl = 1 / 8 / 64 / 512 | 4.96 / 25.92 / 193.92 / 1,537.92 (3N + 1.9) |
| `vse8.v`, vl = 1 / 8 / 64 / 512 | 4.98 / 25.93 / 193.93 / 1,537.93 |
| `vmul.vv` / `vfadd.vv` / `vredsum.vs` e64, vl = 8 | 70.42 / 54.47 / 16.47 |

What the calibration shows:

- **Every instruction costs at least 2 cycles: one fetch per
  instruction, 2 cycles per fetch.** Compressed code fetches no faster:
  `c.add` costs the same as `add`, at 1.02 I$ accesses per instruction,
  because the word is fetched again for the second half. A 32-bit
  instruction that straddles two fetch words costs 4.
- **A redirect costs 2 cycles, and there is no prediction.** A taken
  branch, `jal` or `jalr` costs 2 cycles more than falling through:
  one squashed wrong-path slot plus one refetch slot. A data-dependent
  branch costs the same at a 50% taken rate whether the pattern
  alternates or is random, exactly midway between never taken and
  always taken. Its cost depends only on the outcome.
- **Load-use bubbles hide in the fetch gap.**
  - An L1 load hit costs 2.5 cycles independent and 3 dependent
    (load-to-load).
  - A load followed by an ALU consumer costs 4.04 per pair at distance
    1 and at distance 2.
  - CSR accesses, `rdcycle`, `rdtime` and `fence` cost the same as an
    ALU op. They do not serialize.
- **The M unit and FPU do not overlap work.** Every operation costs its
  `docs/CORE.md` EX occupancy plus 1.1 cycles (net of window), and
  dependent and independent sequences cost the same.
- **D$ (16 KiB, 4-way).**
  - A random working set of up to 16 KiB hits (0.002 misses per load).
    The miss rate is 40% at 20 KiB, 83% at 32 KiB and 100% from
    128 KiB.
  - A clean miss costs 12.0 cycles (soc) or 37.0 cycles (axi), as
    `dc_miss_cyc / dc_miss`. A dependent load that misses costs 14.1 or
    39.1 cycles.
  - Streaming loads move 1.87 or 1.08 bytes/cycle.
- **I$ (8 KiB, 2-way).**
  - Straight-line footprints up to 4 KiB never miss. At 6–8 KiB,
    3.5–4.5% of line fetches miss: round-robin victim conflicts with
    the driver's lines.
  - From 12 KiB, 67–88% of line fetches miss. The rate is never 100%,
    because the shared round-robin pointer leaves some lines resident.
  - The miss penalty is 12.0 cycles (soc) or 37.0 cycles (axi).
- **Vector.**
  - Arithmetic matches `docs/CORE.md` exactly in the vector unit
    (`stk_vec`): `vadd` N+4, e64 `vmul` (4+4)N+4, `vfadd` 6N+4,
    `vredsum` N+6. Each vector instruction adds about 2.1 cycles of
    issue on top.
  - Unit-stride `vle8`/`vse8` take **3 cycles per element** in MEM
    (`stk_vls` = 3N). `docs/CORE.md` gives 2 per element plus 1, and
    quotes 1,025 cycles for `vle8` at vl=512; this run measures 1,536
    MEM cycles in the SoC with the D$.
  - `vsetvli` costs an ALU op, whether vtype changes or not.

## #56 / #10: SHA-256 hash chain and 64 KiB bulk hashing (2026-10-22)

[`perf-sha256chain-56-2026-10-22/`](perf-sha256chain-56-2026-10-22/report.md)
holds:
- `report.md`, `results.csv` and `results.json`;
- `runs/`: the UART log and `SIGIL_PERF` records of all 8 simulations;
- `perf-run.log`, the harness console output with the determinism
  check;
- the build logs;
- the generated `hashlib` known-answer headers;
- `iter40-smoke/`;
- `unaligned-c7bd3b7/` with `diff-unaligned-c7bd3b7-vs-aligned.md`.

The benchmarks are described in
[`sw/bench/sha256chain/README.md`](../../sw/bench/sha256chain/README.md).

- **Design.** The `rtl/` tree is `89b98cb`, identical to harness
  `534f846`: main `eeaa332` plus the simulation-only counters. No #53
  changes are included.
- **Benchmarks.** Commit `2b8e1ae` (branch `56-perf-sha256chain`).
- **Run.** `make -C sim perf BENCHES="sha256chain sha256chain_bulk"
  CONFIG=default MEM="soc axi" REPEAT=2 JOBS=4` on sigil-verify.
  - Results written 2026-10-22T09:55:45Z.
  - Tools: Verilator 5.048, riscv64-unknown-elf-gcc 16.1.0 and Python
    3.12.3 `hashlib`.
  - Flags: `sdk.mk` with the SDK default `-march`, plus
    `-falign-functions=64`.
- **Validation.** All 48 region records are valid.
  - Before the regions, every implementation passed the FIPS 180-4 /
    FIPS 202 known answers.
  - After each region, every result matched `hashlib`, including all 16
    RVV lanes.
  - The harness cross-checks passed, and both repeats are identical.
  - At `ITER=40` (soc, not a result), the runs also validate, including
    the RVV remainder step at vl = 8.

SHA-256 chain, 1024 hashes per region. Cycles/hash on soc: axi is
within 0.02%. Hashes/s is the clock divided by cycles/hash. RVV ×16 is
aggregate throughput over 16 independent chains.

| Implementation | cycles/hash | hashes/s @62.5 MHz | hashes/s @100 MHz |
|---|---:|---:|---:|
| plain C | 9,918.2 | 6,302 | 10,082 |
| C + Zknh | 6,753.2 | 9,255 | 14,808 |
| RVV ×16 | 4,642.0 | 13,464 | 21,542 |
| accelerator, `sigil_sha256_block` | 572.1 | 109,248 | 174,797 |
| accelerator, `sigil_sha256` | 2,793.1 | 22,376 | 35,802 |
| accelerator SHA-512 chain (64 B), `sigil_hash` | 2,472.2 | 25,281 | 40,450 |
| accelerator SHA3-256 chain, `sigil_hash` | 1,370.1 | 45,616 | 72,986 |

Bulk hashing of 64 KiB, in bytes/cycle, soc / axi:
- SHA-256 plain C: 0.0065 / 0.0065;
- SHA-256 Zknh: 0.0095 / 0.0095;
- SHA-256 RVV ×16 (16 × 4 KiB segments): 0.0131 / 0.0130;
- accelerator SHA-512: 0.2388 / 0.2205;
- accelerator SHA3-256: 0.2398 / 0.2215.

In MB/s, multiply by the clock in MHz. For example, accelerator SHA-512
on soc gives 14.9 MB/s at 62.5 MHz and 23.9 MB/s at 100 MHz. There is no
SHA-256 accelerator bulk row, because its engine has no chaining.

Code alignment matters. Without `-falign-functions=64` (same
instructions, `unaligned-c7bd3b7/`), these chains took more cycles:
- SHA-512: 43% more (3,609,723 against 2,531,505);
- SHA3-256: 37% more;
- Zknh: 6.8% more.

The extra cycles are fetch latency and 32-bit instructions straddling a
fetch word.

## #56: whole benchmark suite after integration (2026-10-22)

[`perf-suite-56-2026-10-22/`](perf-suite-56-2026-10-22/README.md):
`report.md`, `results.csv`, `results.json`, `runs/`, `build-logs/`,
`perf-run.log`, `compare-evidence.log` and `harness-options-smoke.log`.
One run of every benchmark after `56-perf-coremark`,
`56-perf-kernels`, `56-perf-micro` and `56-perf-sha256chain` were
merged into `56-perf-harness` with the harness changes they asked for.
It is an integration check, not a new baseline.

- **Design.** `rtl/` tree `89b98cb227c6` (main `eeaa332` plus the
  simulation-only counters). No #53 pipelining.
- **Run.** `make -C sim perf CONFIG=default MEM="soc axi" REPEAT=2
  JOBS=12 CLOCK_MHZ="62.5 100"` at `662bad7` on sigil-verify,
  2026-10-22T11:05:49Z–11:11:11Z, Verilator 5.048,
  riscv64-unknown-elf-gcc 16.1.0. 10 benchmarks, 14 images, 56
  simulations.
- **Validation.** 712/712 region results valid and deterministic.
  Every image sha256, counter and hardware-counter number is identical
  to the branch evidence above: dhrystone 8/8 (default configuration),
  coremark 12/12, kernels 224/224, micro 420/420, sha256chain 48/48.
- **Harness changes.** Per-region bytes/work per iteration and
  baselines, a window region, per-variant regions and expect lines,
  `VARIANTS`, `MAX_CYCLES`, `CLOCK_MHZ`, `cc_commands`, and a
  row-per-run layout for wide reports (`docs/PERFORMANCE.md`). The
  options this run does not use are smoke-tested in
  `harness-options-smoke.log`.

## #56: the benchmark suite on AWS F2 hardware (2026-10-22)

[`perf-f2-56-2026-10-22/`](perf-f2-56-2026-10-22/README.md):
`README.md` (analysis), `tables.md`, `regions.md`, `results.json`,
`logs/` (UART capture and host report of all 46 runs),
`instance-info.txt`, `aws-lifecycle.txt`, `SHA256SUMS` and `scripts/`.
The #56 benchmark images ran on a real F2 FPGA with the public AFI.

- **Hardware.** One `f2.6xlarge` (`i-0fa8f24634bfa912f`, us-east-1a,
  FPGA Developer AMI 1.19.2) ran public AFI `agfi-035116450e0a0d093`
  (Small Shell `0x10212415`). The measured core clock was
  62.500–62.501 MHz.
- **Design.** The AFI (built from `4058108`) runs the `default`
  configuration of the main `eeaa332` design: it predates `VRF_OREG`
  (#53), and there is no #53 pipelining.
- **Run.** `sigil_host --ignore-mem-err` (aws-fpga v2.3.5), from
  2026-10-22T11:25:40Z to 11:27:43Z.
- **F2 time.** 5 min 35 s running (0.093 instance-hours); the instance
  is terminated.
- **Images.** The 16 images are byte-identical to the simulation
  evidence: the 14 of `perf-suite-56-2026-10-22` and the 2
  1000-iteration CoreMark images of `perf-coremark-56-2026-10-22`.
  They were built at `8d15410` with GCC 16.1.0.
- **Validation.** 46/46 runs are valid. Each run printed `SIGIL TEST
  PASS` after its own CRC, KAT or known-answer checks, every expect
  line was present, and there was one `SIGIL PERF` line per region.
  The UART output equals the simulation's line for line, except
  numbers on timing lines; no byte was dropped and nothing overflowed.
  178 of 180 regions retire exactly the simulated `minstret`. The
  exceptions are the two SHA-512 accelerator poll loops.

| Benchmark | F2 hardware | Simulation, default/axi |
|---|---:|---:|
| Dhrystone 2.1, scalar | 0.371 DMIPS/MHz = **23.17 DMIPS** | 0.371 |
| CoreMark 1.0, 1000 iterations (11.47 s on hardware, `Correct operation validated`) | 1.395 CoreMark/MHz = **87.19 CoreMark** | 1.395 (soc) |
| SHA-256 accelerator `sigil_sha256_block`, cycles/hash | 572.1 = 109,250 hashes/s | 572.1 |
| SHA-256 plain C / Zknh / RVV x16, cycles/hash | 9,918.4 / 6,753.4 / 4,642.6 | identical |

How closely the hardware matches the simulation:

- **Agreement.** 145 of 180 regions are within 0.1% of the
  default-configuration simulation behind the 24-cycle AXI DDR model,
  and 165 are within 1%. Regions without cache misses repeat
  cycle-exactly.
- **Memory-bound regions.** All the larger gaps are cache-miss
  microbenchmarks:
  - a refill costs about 1.5 cycles more on the real DDR4 path (D$
    dependent miss 40.6 against 39.1 cycles);
  - a dirty write-back costs about 10 cycles less.
- **The `fpga` (VRF_OREG) simulation.** It is not this AFI's design.
  In all 61 regions where the two configurations differ, the hardware
  is closer to `default`: for example, `vse8` at vl=512 takes 1,537.8
  cycles, against 2,049.8 with `VRF_OREG`.

## #56: deterministic simulation baseline of main `eeaa332`, three configurations (2026-10-22)

[`perf-baseline-56-2026-10-22/`](perf-baseline-56-2026-10-22/README.md):
`headline.md` (cross-configuration tables), and per configuration
(`default/`, `sky130/`, `fpga/`) `results.csv`, `report.md`
(`scripts/perf_report.py`), `results.json`, `runs/`, `build-logs/` and
`perf-run.log`. Also `env.log`, `synth-view-diff.log`, `tb-build.log`,
`compare-prior-evidence.log`, `micro_table.md`, `kernels_report.md`,
`run_baseline.sh` and `baseline_tables.py`. This is the reference
against which #53 and later changes are compared.

- **Design.** `rtl/` tree `89b98cb227c6`: main `eeaa332` plus the
  simulation-only counters. The synthesis views are byte-identical to
  `eeaa332` for every flow's defines. No #53 pipelining.
- **Run.** `run_baseline.sh` at `8d15410` on sigil-verify,
  2026-10-22T11:20:07Z–11:40:57Z, Verilator 5.048,
  riscv64-unknown-elf-gcc 16.1.0. Fresh testbench builds, then `make
  -C sim perf CONFIG=<default|sky130|fpga> MEM="soc axi" REPEAT=2
  JOBS=12`. Every benchmark and variant: 14 images, 168 simulations.
- **Validation.**
  - 2136/2136 region results valid, every program self-checked
    (CRCs, known answers, `hashlib`).
  - Both repeats identical in every counter.
  - The 14 images are bit-identical across the three builds.
  - `default` is identical to `perf-suite-56-2026-10-22` (712/712) and
    to the branch evidence. The `sky130`/`fpga` Dhrystone results are
    identical to `perf-dhrystone-56-2026-10-22`.
- **Headline** (`soc` / `axi`):

  | | default | sky130 | fpga (VRF_OREG) |
  |---|---:|---:|---:|
  | Dhrystone `scalar` DMIPS/MHz | 0.371 / 0.371 | 0.216 / 0.201 | 0.371 / 0.371 |
  | CoreMark `scalar` CoreMark/MHz | 1.395 / 1.395 | 0.868 / 0.867 | 1.395 / 1.395 |
  | SHA-256 cycles/hash: C, Zknh, RVV ×16, accel block (`soc`) | 9,918 / 6,753 / 4,642 / 572 | 15,634 / 10,747 / 4,949 / 792 | 9,918 / 6,753 / 4,855 / 572 |

- **`fpga`** changes only vector code. Regions with no vector
  instruction have identical counters. Vector arithmetic costs 1 more
  cycle per instruction and unit-stride stores 1 more cycle per
  element (Dhrystone `sdk` +3.2%, SHA-256 RVV +4.6%, memset RVV +29%).
- **`sky130`** is 1.58–1.85x slower on scalar code. The fetch issue gap
  is 3 cycles instead of 2, a load takes 5 cycles instead of 2.5, and
  the 4 KiB direct-mapped D$ misses on every access from an 8 KiB
  working set.

## #56 / #10: where the cycles go and ranked upgrade candidates (2026-10-22)

[`perf-analysis-56-2026-10-22/`](perf-analysis-56-2026-10-22/README.md)
holds the analysis behind `docs/PERFORMANCE.md` §12–14:

- `counters/`: `derive.py`, and its output `derived.md`, which has every
  counter-derived ratio the document quotes, plus helper scripts;
- `frontend-model/`: the trace-driven front-end model (`fe.cpp`), its
  run scripts and outputs, the what-if table `whatif.md`, and the
  model's check against the RTL;
- `analyses/`: the three analyses as written (front end, memory
  hierarchy, execution units).

Results: [`docs/PERFORMANCE.md`](../PERFORMANCE.md) §12–14.

- **Inputs.**
  - The counters of `perf-baseline-56-2026-10-22` (`56-perf-harness`
    `de21e4b`; `rtl/` tree `89b98cb227c6`, main `eeaa332` plus the
    simulation-only counters, no #53 pipelining).
  - `perf-f2-56-2026-10-22`.
  - Spike 1.1.1-dev (`2c300cd9`) commit traces of the baseline ELFs
    (`8d15410`).
  - RTL retirement traces for the SHA chains, from a simulation-only
    tap in an uncommitted copy (Verilator 5.048).
  - The model, built with g++ 13.3.0 on sigil-verify and run
    2026-10-22, about 12:30–12:45Z.
- **Validation.**
  - The model of today's core reproduces the RTL cycle counts to within
    +0.0002% for CoreMark, +0.0014% for Dhrystone and +0.0001% for
    SHA-256 C and Zknh. On sky130 it is within +0.005%.
  - `ic_access`, `br_taken`, `jal_redir`, `jalr_redir` and
    `muldiv_busy` match the RTL counters exactly.
  - Every (region, variant) pair present in several output sets is
    identical (`version-consistency.log`).
  - Every traced program self-checked under Spike, except one `rdtime`
    rate check in `micro_pipe`. Spike's timer differs from the RTL's,
    and `micro_pipe` serves only to check the model per mechanism.
- **Results** (model figures, `default`):
  - **Decoupled 64-bit fetch:** CoreMark 1.41x, Dhrystone 1.43x,
    SHA-256 C 2.15x.
  - **Plus a 64-entry bimodal predictor with a 4-entry RAS:** 1.70x,
    1.80x and 2.32x.
  - **Changes that leave fetch alone,** such as dual issue and
    multithreading, are bounded today by the I$ port. It is 94.9% busy
    on CoreMark, which caps them at 1.053x.
  - **SHA-256 (#10):** the accelerator block API takes 572 cycles per
    hash, against 9,918 for plain C, 6,753 for Zknh and 4,642 for
    RVV ×16. That is 17.3x plain C, and F2 hardware gives the same
    counts.

## #56 / #10: gates on the final branch, clean-worktree reproduction of the baseline (2026-10-22)

[`perf-56-gates-2026-10-22.log`](perf-56-gates-2026-10-22.log), with the
ACT results in
[`act-core-perf-56-2026-10-22.csv`](act-core-perf-56-2026-10-22.csv). A
completeness review of #56 and #10 on `56-perf-harness`. `rtl/` tree
`89b98cb227c6` is the baseline's tree: main `eeaa332` plus the
simulation-only counters, with no #53 code. The gates ran at `b441f31`
on sigil-verify, from a fresh worktree, on 2026-10-22 from 13:45 to
14:59Z. Tools: Verilator 5.048 (`deps/`), CI's 5.020 and the Mac's
5.044, and riscv64-unknown-elf-gcc 16.1.0.

- **Gates.**
  - `make lint` is clean on 5.048, 5.020 and 5.044.
  - With `SYNTHESIS` defined, every flow's preprocessed RTL is
    byte-identical to `eeaa332`. The `+define+SYNTHESIS` lint gives the
    same diagnostics as main: 24 `UNUSEDSIGNAL` warnings, all of them
    main's own.
  - `make test` passes.
  - `make core-test`: 235 `TB PASS` lines. Every PASS line is identical
    to a main `eeaa332` core-test on the same host, cycle counts
    included. All 1,440 of its coverage files are byte-identical to
    main's, so coverage is 55.00% (3491/6252) on both.
  - riscv-tests 123/123; `srammacro` passes (fakeram45, sky130, oreg,
    vrforeg); all 7 SDK examples pass.
  - ACT 2,577/2,578 (Vx 821/821, Vls 1,051/1,051, Vf 162/162, scalar and
    priv 543/544). Only the `PMPSm_cfg_A_tor_zero-00` waiver fails. All
    2,578 verdicts and cycle counts equal
    `act-core-w0-stack-2026-10-20.csv`.
- **Baseline reproduced.** The baseline was rerun from a clean worktree
  with `make -C sim perf CONFIG=<config> MEM="soc axi"` for `default`,
  `sky130` and `fpga`, 356 region results each. Every image sha256 and
  every counter equals `perf-baseline-56-2026-10-22`.
- **How-to commands.** The `docs/PERFORMANCE.md` §1, §5 and §8 commands
  work as written, with one exception. The documented quick smoke,
  `ITER=200`, overruns the 2e8-cycle limit in `kernels`: 0 of 28 valid,
  about 680 M cycles needed. The quick smoke is now `ITER=1`, which
  validates all 356 results in 105 s.
- **CoreMark at 1000 iterations.** `ITER=1000 MAX_CYCLES=1500000000`
  validates. The `soc` cycles, 716,834,078, equal the CoreMark
  evidence.
- **ACT procedure.** At this riscv-arch-test pin, the ELFs had to be
  built in a different order from `sw/act4-core/README.md`. The vector
  sources only exist after the first `make elfs`, so the 43 listed
  generation failures were moved aside after that build, and the build
  was then rerun.

## #20: ACT Zalrsc-sc case-level probe on the in-house core (2026-10-22, branch `20-isa-followups`)

- Artifacts: [`act-zalrsc-sc-probe-core-2026-10-22.csv`](act-zalrsc-sc-probe-core-2026-10-22.csv)
  (one row per test case: Sail vs core signature words, default
  harness configuration), [`act-zalrsc-sc-probe-runs-core-2026-10-22.csv`](act-zalrsc-sc-probe-runs-core-2026-10-22.csv)
  (one row per test x harness configuration),
  [`act-zalrsc-sc-probe-core-2026-10-22.log`](act-zalrsc-sc-probe-core-2026-10-22.log)
  (tool versions, commands, summaries, cycle ranges).
- Question: the CVA6-era sweep (above, 2026-10-12) recorded ACT
  `Zalrsc-sc.w`/`sc.d` as a waived hang in the CVA6 testharness memory
  path and asked for a case-level probe. On the in-house core both
  ELFs have passed as whole tests since stage 4a; this probe checks
  them case by case.
- Method (`scripts/act_zalrsc_sc_probe.sh`, commit `0c46ae5`,
  sigil-verify, Verilator 5.048, Sail 0.15, riscv-arch-test
  `6af53584`, GCC 16.1.0 from the pinned 2026.08.27 toolchain):
  - Tests: stock `Zalrsc-sc.w-00`/`sc.d-00` (275 cases each: 243
    expect the SC to succeed, 32 expect it to fail) plus "noretry"
    variants of both, where every constrained LR/SC retry budget
    `LI(xN, 100)` is cut to 1 (274 per test). A spurious
    first-attempt SC failure, which the stock retry loop would hide,
    then reaches the signature. All four were built through the
    ACT flow (Sail signature + self-check ELF). Sail's signatures
    for the stock and noretry sources are identical.
  - Harness configurations: default (L1 caches on), `--no-cache`,
    and randomized bus timing (`--mem-lat 1:6 --mem-gap 2
    --mem-ready 70`, seeds 1–16), both cached and uncached: 34 per
    test.
  - Each run executes the self-check ELF (5M-cycle budget, so a hang
    would show as a timeout). It also executes the signature-mode
    `.sig.elf`, the binary Sail ran, with `CORE_TB_SIGDUMP=1`, and
    compares all 568 signature words with Sail's `.sig`
    (`scripts/act_sig_cases.py` maps each word to its test case).
    Signature-mode ELFs use Sail's HTIF console and halt macros, so
    `core_tb` gained an opt-in `CORE_TB_HTIF_CONSOLE` mode. Default
    harness behaviour is unchanged.
- Result: **136/136 runs PASS** (self-check PASS, signature-mode run
  completes, all 568 words equal to Sail). **1,100/1,100 cases** match
  Sail word for word in the default configuration (4 tests x 275).
  No timeouts. The longest run is 239,766 cycles (stock `sc.w`,
  uncached with random bus timing).
- Conclusion: the 2026-10-12 hang is specific to the CVA6
  model/testharness and does not reproduce on the in-house core,
  whose LR/SC behaviour matches Sail for every ACT
  `sc.w`/`sc.d` case under all 34 timing configurations, including
  with retries disabled. ACT Zalrsc (lr + sc) is claimed for the
  in-house core.

## #20: Berkeley TestFloat level-2 mulAdd on the in-house FPU (2026-10-22, branch `20-isa-followups`)

- Artifacts: [`testfloat-l2-muladd-core-2026-10-22.csv`](testfloat-l2-muladd-core-2026-10-22.csv)
  (one row per function x instruction x rounding mode x selection)
  and [`testfloat-l2-muladd-core-2026-10-22.log`](testfloat-l2-muladd-core-2026-10-22.log)
  (versions, generator validation, run logs, every chunk result).
- DUT and check: `rtl/core/sigil_fpu.sv` (RTL identical to `main`
  `eeaa332`) in the FPU unit TB (`tb/cpp/fpu_tb.cpp --testfloat`).
  The runs use its uninstrumented build `fpu_tb_fast` (same TB and RTL
  without coverage counters, about 2x faster). Every case goes through
  the EX handshake (random idle gaps, 5% delayed acks). Result bits
  and all five exception flags are compared exactly with SoftFloat 3e
  `a0c6494c` (RISCV specialization, tininess after rounding), as
  `testfloat_gen` computes them.
- Generator: `sw/testfloat/tf_l2_mulAdd.c` with
  `scripts/testfloat_fpu_l2.sh`. It compiles TestFloat `a9c849f1`'s
  own level-2 case code (`genCases_f32.c`/`genCases_f64.c`,
  `random.c`), with a lock-free replica of glibc `rand()`, so the
  stream can start at any pair index from a saved generator state and
  run as 33,554,432-pair chunks in parallel (16 jobs, seed 42 as in
  the level-1 flow). Level-2 mulAdd is 2·N³ cases per rounding mode:
  each step is a TestFloat random triple followed by the next triple
  of the (QIn x P2)³ grid, with N = 1,936 (f32) or 4,488 (f64). That
  is 14,512,627,712 f32 and 180,795,884,544 f64 cases per mode. A
  stride S > 1 keeps every S-th grid triple and as many random
  triples. S is prime and coprime with N, so every operand value
  still appears in every position.
- Generator validation (`testfloat_fpu_l2.sh validate`): byte-identical
  to `testfloat_gen -level 2 -seed 42 -r<mode>` for the first
  20,000,000 lines of `f32_mulAdd` and `f64_mulAdd` in all five modes,
  and for 2,000,000 lines restored from a checkpoint deep in the
  stream (from line 3,000,000,001 for f32 and 800,000,001 for f64,
  RUP). Its fpu_tb lines are byte-identical to
  `testfloat_fpu_vectors.py` output for the first 1,000,000 cases of
  each format.
- Results: **every selection PASS, 0 result or flag mismatches in
  29,952,200,254 cases**:

  | Function | Instruction | Modes | Selection | Cases checked |
  |---|---|---|---|---|
  | f32_mulAdd | fmadd.s | RNE | complete level-2 stream | 14,512,627,712 |
  | f32_mulAdd | fmadd.s | RTZ, RDN, RUP, RMM | S = 13 | 4 x 1,116,355,978 |
  | f64_mulAdd | fmadd.d | all 5 | S = 97 | 5 x 1,863,875,100 |
  | f32_mulAdd | fmadd.s/fmsub.s/fnmsub.s/fnmadd.s, rotating | all 5 | S = 97 | 5 x 149,614,720 |
  | f64_mulAdd | fmadd.d/fmsub.d/fnmsub.d/fnmadd.d, rotating | all 5 | S = 997 | 5 x 181,339,906 |

  In the rotating rows, random triple r uses opcode r mod 4 and grid
  triple r uses (r + 2) mod 4, so each opcode gets about a quarter
  of the cases. Operands are sign-flipped (fmsub: −c, fnmsub: −a,
  fnmadd: −a and −c) so the expected value stays TestFloat's mulAdd
  result; SoftFloat and Spike define the negated forms the same way.
- Limits: complete level 2 ran for `f32_mulAdd` in RNE only. Running
  the other four f32 modes completely would take about 2.3 core-days.
  Complete f64 level 2 is 903,979,422,720 cases over five modes,
  about 40 core-days at this TB's ~260k cases/s per core. Neither
  was run. Those selections are the decimated level-2 rows above.
  The host was shared with other jobs (load up to ~45 on 32 vCPUs),
  so the f32 plan was cut from five complete modes to RNE complete
  plus S = 13 for the other four. `roundToInt` is not applicable: it
  has no instruction without Zfa, which this configuration does not
  implement.
- Combined with level 1 (all 36 F/D functions x 5 modes,
  64,648,560 vectors, "Multi-cycle synthesizable FPU" above),
  TestFloat level-2 mulAdd density on the in-house FPU is now
  claimed for the selections in the table.

## #20: gates for branch `20-isa-followups` (2026-10-22)

[`isa-followups-20-gates-2026-10-22.log`](isa-followups-20-gates-2026-10-22.log):
at `0c46ae5` (the `core_tb` HTIF console mode and the `fpu_tb`
coverage guard; RTL unchanged from `main` `eeaa332`), `make lint`
clean, `make test` PASS, `make -C sim fpu` PASS (476,563 checks,
coverage written), riscv-tests 123/123, `make core-test` rc 0
(2,794 s). At `17aca6b`, the last code change, `make lint` clean
and `make test` PASS.

## #68 #69 #70 #64: Linux 6.12 + Debian 13 for Sigil, QEMU bring-up (2026-10-22, branch `73-linux-debian`)

Logs in [`linux-debian-73-2026-10-22/`](linux-debian-73-2026-10-22/);
user guide [`docs/LINUX.md`](../LINUX.md). Everything that runs on the
SoC for epic #73, built on `sigil-fpga-build` (Ubuntu 24.04) and brought
up in QEMU against [`LINUX_PLATFORM.md`](../LINUX_PLATFORM.md). **No
FPGA run yet** (the AFI with the 80 GiB map is not published); the F2
numbers below are estimates.

**Versions.** Linux **6.12.114** (`sw/linux/kernel/sigil_defconfig`,
tarball sha256 `7a858991…4af3`); OpenSBI **v1.9** (`cbf9f673`) generic
`fw_jump` + `sw/linux/opensbi/0001-*.patch`; **Debian 13.7 "trixie"
riscv64** from `snapshot.debian.org` **`20261020T000000Z`** (trixie,
-updates, -security), 257 packages
([`debian-manifest.txt`](linux-debian-73-2026-10-22/debian-manifest.txt):
gcc/g++ 14.2.0, binutils 2.44, glibc 2.41, gdb 16.3, make 4.4.1, git
2.47.3, python3 3.13.5, systemd 257.13, numactl/libnuma 2.0.19, …);
build tools in [`build-versions.txt`](linux-debian-73-2026-10-22/build-versions.txt).
Two image builds from the snapshot gave a byte-identical manifest.

**Artifacts** (not in git; `sigil-fpga-build:~/os-artifacts/`, all
checksums in [`SHA256SUMS`](linux-debian-73-2026-10-22/SHA256SUMS)):

| File | Load address | sha256 |
|---|---|---|
| `fw_jump.bin` | `0x8000_0000` | `d98908b4ce2187b3a7e26b27f78747b03eb9bd2ee457e4e974d05a49649cacbf` |
| `Image` | `0x8020_0000` | `0213f645984e386a3799d9be2b9c9bf4de357b2dedbd4a1593b6c3d55f3f7790` |
| `Image-initramfs` (`/init` → `SIGIL_LINUX_BOOT_OK`) | `0x8020_0000` | `2f059b6cd7f944d3d2dbdb5b48f837da6351be917f981e15523212e0e4226a48` |
| `sigil-f2.dtb` | `0x8300_0000` | `eb1689b43fe38e01d75e36c569d51bb7ea21c3163c10fb6acafa4b466f521e04` |
| `sigil-qemu.dtb` / `sigil-sim.dtb` | `0x8300_0000` | `9b8313cc…0a03` / `f144da91…77` |
| `sigil-debian-13-riscv64.ext4.zst` (222 MB) | `0xC_8000_0000` (PCIS `0x0C_0000_0000`) | `a9cfcbc977fad8968f07200d595b37ed3df51f7877b7fc0ec26d985e5fb5bf33` |
| raw `.ext4` (8 GiB, after `zstd -d`) | | `c2d0cd4cf3e543a04e8194283acc7d8c1eec97046189ca8f9d4c1dd9bfe08632` |

**QEMU acceptance: 23/23 PASS** (`python3 scripts/qemu_sigil_check.py
--fresh`; transcript [`qemu-check.log`](linux-debian-73-2026-10-22/qemu-check.log),
summary [`qemu-check-summary.txt`](linux-debian-73-2026-10-22/qemu-check-summary.txt)).
QEMU 8.2.2 `-M virt` shaped like the contract
(`scripts/qemu_sigil_boot.sh`): one hart with only Sigil's extensions,
Sv39, DDR4 node 0 = 48 GiB at `0x8000_0000`, the pmem disk = 16 GiB
file-backed at `0xC_8000_0000`, HBM node 1 = 16 GiB at `0x10_8000_0000`,
the F2's OpenSBI, kernel and disk image with `sigil-qemu.dtb`.

- Login on `ttyS0` as `sigil` after `SIGIL_LINUX_BOOT_OK Debian GNU/Linux
  13 (trixie) up, login prompt next`; `Linux sigil 6.12.114-sigil …
  riscv64`; ISA `rv64imafdch_zicntr_zicond_zicsr_zifencei_zca_zcb_zcd_
  zba_zbb_zbc_zbkb_zbkc_zbkx_zbs_zknd_zkne_zknh_zve32f_zve32x_zve64d_
  zve64f_zve64x`; systemd `running`, no failed units; `/` = `/dev/pmem0`
  ext4 rw.
- `numactl --hardware`: `available: 2 nodes (0-1)`, node 0 cpus 0 size
  48305 MB, node 1 (no CPUs) size 16110 MB, distances 10/20.
- `gcc hello.c && ./a.out` → `Hello from sigil on riscv64`; `make` of
  the examples on the guest; `malloc_test 512` → `MALLOC OK`; libnuma
  `numa_alloc_onnode` on nodes 0 and 1 → all pages on the requested node;
  `memwhere 1024` → `node 0: 1024 MiB`, `numactl --membind=1 memwhere
  1024` → **`node 1: 1024 MiB`**, `--interleave=0,1` → 512 + 512 MiB.
- RVV: `rvv_vadd` (intrinsics, `-march=rv64gc_zve64d`) → `hwprobe: zve32x 1
  zve64x 1 zve64d 1 full-v 0`, `VLEN = 512 bits`, `RVV OK`; `autovec`
  (`-O3 -march=rv64gc_zve64d_zvl512b`) correct with 7 vector
  instructions.
- sudo, python3, git, gdb, strace, vim, file, man; a file written to the
  pmem disk survives `reboot` (finisher `0x7777`); `poweroff` → `reboot:
  Power down`, QEMU exits (finisher `0x5555` via SBI SRST).
- QEMU timings (TCG, **not FPGA**): reset → boot marker 18 s, login prompt
  21 s; `systemd-analyze` 0.5 s kernel + 9.8 s userspace.

**F2 estimate** (`--icount`: QEMU `-icount shift=4,sleep=off`, 16 ns per
instruction = a 62.5 MHz hart at IPC 1, [`qemu-icount.log`](linux-debian-73-2026-10-22/qemu-icount.log)):
`systemd-analyze` 2.07 s kernel + 41.05 s userspace, boot marker at
41.7 s, `gcc -O2 hello.c` 4.9 s, `python3 -c` 1.0 s. Calibration: the #55
F2 payload (the sha256-identical 6.6 `Image`, `fw_jump.bin` and DTB of #55)
reaches `clk: Disabling unused clocks` at 4.74 s in the same icount QEMU
(≈ 0.30 G instructions, [`old66-f2-payload-icount.log`](linux-debian-73-2026-10-22/old66-f2-payload-icount.log));
on the F2 that line came at kernel time 385.36 s with a 10 MHz DT timebase
while `mtime` ran at 62.5 MHz, i.e. 61.7 s = 3.85 G cycles: **≈ 13 cycles
per instruction**. Scaled: login prompt **≈ 9 min** after reset, `gcc
hello.c` ≈ 1 min, `python3` start ≈ 15 s at 62.5 MHz, until measured.
Measured on the F2 later (AFI `agfi-0c8aa56fde1a48495`, section "Debian on
the F2 with the walker-race fix" below): login prompt 5 min 48 s after the
SoC release, `gcc hello.c && ./a.out` 22.9 s, `python3 -c` 9.9 s, an estimated 5
cycles per instruction (F2 times divided by QEMU icount instruction counts).

**Tuning from the icount runs.** Before it
([`qemu-icount-before-tuning.log`](linux-debian-73-2026-10-22/qemu-icount-before-tuning.log))
the marker came at 84.2 s and the first login **timed out** (`login:
timed out after 60 seconds`); with that fixed, `blame` was led by
`user@1000.service` 37.8 s, `dev-pmem0.device` 30.8 s (boot fsck waiting
for udev), `systemd-udev-trigger` 25.3 s (512 legacy pty nodes, 8 loop
devices) and ~5 s each for five `modprobe@` units and `systemd-binfmt`.
Now: logind sessions of class `background-light` (no per-user service
manager at login), no boot-time fsck, `LEGACY_PTYS=n`,
`BLK_DEV_LOOP_MIN_COUNT=0`, those units masked, `LOGIN_TIMEOUT 0`:
marker 84.2 s → 41.7 s, login a few seconds.

**Findings.** (1) A raw pmem namespace needs `ND_CLAIM`: with BTT, PFN
and DAX all off, `devm_nsio_enable()` is a `-ENXIO` stub, `nd_pmem`
fails silently and `root=/dev/pmem0` waits forever; `sigil_defconfig`
keeps `CONFIG_BTT=y`. (2) Sigil's write-back D$ is not coherent with the
host's PCIS view, so Linux powers off and reboots only through SBI SRST
(no syscon reset drivers in the kernel) and the OpenSBI patch runs
`FENCE.I` (writes back every dirty line on Sigil) before the finisher
write; a host save after `poweroff` then holds the whole file system.
(3) 6.12 enables user vector on Zve64d; the vector usercopy threshold is
1 GiB so the kernel never uses the element-serial vector unit for
`copy_*_user`. (4) GCC auto-vectorizes for Zve64d only with `_zvl512b`.

**RTL.** The all-RTL SoC model `soc_rtl_tb` (main-checkout build of
2026-10-21) boots the same kernel as `Image-initramfs` with
`sigil-sim.dtb` to `SIGIL_LINUX_BOOT_OK` at **261,246,160 cycles**
([`soc-rtl-linux-6.12-boot.log`](linux-debian-73-2026-10-22/soc-rtl-linux-6.12-boot.log);
the 6.6 `defconfig` gate needed 508,905,040 in `soc_tb`). The console
shows the #63 TX-FIFO character drops of that RTL, not of the kernel.
`scripts/qemu_reference_boot.sh` (now on `Image-initramfs`, build stamps
ignored) passes against that log: `QEMU REFERENCE BOOT PASS`.

**Deviations / contract proposals.** QEMU-only: 10 MHz timebase; three
QEMU NUMA sockets lay out the ranges, so QEMU has two extra harts outside
the DT (OpenSBI parks them); virtio-mmio slots; no crypto node.
Proposed for `LINUX_PLATFORM.md`: RTC = PLIC source 11; DTB at
`0x8300_0000` (`FW_JUMP_FDT_ADDR`, kernel ≤ 46 MiB, initrd `0x8400_0000`);
**a finisher reboot must not reload the pmem disk** (today
`sigil_host --on-reboot rerun` reloads every `--load` image); power-off
and reboot via SBI SRST with the D$ write-back; optional host-written
`/chosen/rng-seed`; later: Svnapot/Svadu in the ISA string (`misa`
reports V although the unit is Zve64d — harmless, Linux uses the DT).

## #73 user path: `sigil-linux`, the Sigil Linux user guide, `hbm_touch` (2026-10-22, branch `73-linux-release`)

Logs and harness in [`linux-user-docs-73-2026-10-22/`](linux-user-docs-73-2026-10-22/),
behind `fpga/scripts/sigil-linux`, `docs/LINUX.md` §4–§5 and
`docs/PROGRAMMING.md` §8.1. All on `sigil-fpga-build` (Ubuntu 24.04,
e2fsprogs 1.47.0, zstd 1.5.5, QEMU 8.2.2) with the release files of
`~/os-artifacts/` (sha256 as in `linux-debian-73-2026-10-22/SHA256SUMS`).
**No F2 instance was used; nothing here is an FPGA measurement.**

- **`sigil-linux` logic, 35/35** ([`sigil-linux-tests.log`](linux-user-docs-73-2026-10-22/sigil-linux-tests.log),
  `harness/run_tests.sh`): the real script against a fake `sigil_host`
  (copies the `--load` disk into a 16 GiB window file, changes the ext4
  in it with `debugfs` or `resize2fs`, writes the `--save` file, exits
  with a chosen status) and fake AFI tools, real `sudo`, downloads from a
  `file://` copy of the release. First run (5 downloads, `SHA256SUMS`
  verified, sparse unpack: 917 MiB allocated of 8 GiB, AFI loaded, the
  exact `sigil_host` arguments, guest change saved, `e2fsck -fn` clean);
  rerun with Ctrl-] (exit 4: no download or AFI load, disk unchanged,
  `DISK.unclean` has the change); guest `resize2fs` to 16 GiB (disk file
  follows; superblock size = `dumpe2fs`); `--fresh` with garbage beyond
  the file system (trimmed to 8 GiB, old disk kept); setup error, no ext4
  in the window, unpublished tag (disk untouched); corrupted cache
  (re-downloaded); concurrent run (locked out); a 16 GiB fully written
  window file in `/dev/shm` → sparse copy of the 8 GiB file system in
  8.2 s, 969 MiB allocated, byte-identical. Fixed while testing: `zstd -d
  -f` wrote a fully allocated 8 GiB file (now `--sparse`); a root-owned
  save file may be unreadable for the user (now `chown`ed).
  Rerun after `sigil-linux` and the harness were pointed at
  `agfi-0c8aa56fde1a48495` (script sha256 `5044eed2…a0c175c`): **35/35**
  ([`sigil-linux-tests-agfi-0c8aa.log`](linux-user-docs-73-2026-10-22/sigil-linux-tests-agfi-0c8aa.log));
  the output differs from the first log only in the AGFI, the boot-time
  message (measured 5 min 48 s instead of the estimate), temporary names
  and timings.
- **User-guide commands in QEMU, 10/10** ([`qemu-docs-check.log`](linux-user-docs-73-2026-10-22/qemu-docs-check.log),
  console [`qemu-docs-check-console.log.gz`](linux-user-docs-73-2026-10-22/qemu-docs-check-console.log.gz),
  `harness/docs_check.py`): files in with `debugfs -w` (owned by root;
  `sudo chown` fixes it) and a loop mount (`chown -R 1000:1000`); the
  `LINUX.md` §5.4 `numa_alloc_onnode` program (`harness/hbm.c`) built with
  `-lnuma`, run plain and under `numactl --membind=1`; `numa_hbm`,
  `numactl --membind=1 ./memwhere 64` → `node 1: 64 MiB`; RVV intrinsics
  with `-march=rv64gc_zve64d`, auto-vectorization with
  `-march=rv64gc_zve64d_zvl512b`; `sudo poweroff`; files out with
  `debugfs` `cat` / `rdump` and a read-only loop mount; `e2fsck -fn` clean.
- **`hbm_touch` on the F2 memory map** (`make -C sim fpgatop-f2-examples`,
  `fpga_top_tb_f2`, Verilator 5.048): `SIGIL TEST PASS hbm_touch` at
  5,370,652 cycles built with GCC 16.1 ([log](linux-user-docs-73-2026-10-22/hbm_touch-gcc16.fpgatop-f2.log))
  and at 6,153,385 cycles with Ubuntu's GCC 13.2, the compiler `sigil-run`
  uses ([log](linux-user-docs-73-2026-10-22/hbm_touch-gcc13.fpgatop-f2.log)):
  256 KiB at HBM `0x10_8000_0000`, at the last 256 KiB of HBM and at DDR4
  `0x8_8000_0000`, 0 bad words, first buffer intact after the others.
  Cycle counts reflect the simulated AXI timing. Not yet run on the F2.

## #73 Linux platform on F2: 64 GiB DDR4 + 16 GiB HBM, devices, console (#65 #66 #67 #62 #63, 2026-10-22)

[`f2-platform-73-2026-10-22/SUMMARY.md`](f2-platform-73-2026-10-22/SUMMARY.md).
Public AFI **`agfi-0a1fd54ef68bdc754`** (`afi-035809e576d7ea8d5`; superseded by
`agfi-0c8aa56fde1a48495`, the same CL with the core's walker-race fix #74,
below; do not use it for Linux), core
62.5 MHz (B1), HBM AXI 250 MHz (H0); post-route WNS +0.150 ns, core clock
+0.635 ns. On a real `f2.6xlarge`: full-range engine memory test of DDR4
(64 GiB) and HBM (16 GiB), two seeds, 0 errors; sparse core test over both
(1.3 M lines), 0 errors; refill latency from the core DDR4 729 ns / HBM 813 ns;
#62 reproduced (SLVERR on the refill of a never-written DDR4 line: ECC) and
fixed (DDR4 scrubbed once per AFI load, 17 s); #63 fixed (Linux console lines
intact, 16-byte UART bursts byte-exact); finisher power off / fail code /
reboot keeping the pmem window; RTC at wall-clock time; raw console with
Ctrl-] detach; 4 GiB and 8 GiB load/save round trips (3.6 GB/s load,
1.0 GB/s save); firmware and all SDK examples without `--ignore-mem-err`.
Simulation: Verilator (`fpgatop-f2-quick` with an 80 GiB sparse model,
`axibridge` out-of-window, `fpgaocl` v4 registers, `fpgatop`, `core-test`,
`make test`, `make lint`; CI-parity Verilator 5.020 lint + FPGA targets) and
HDK XSIM (`test_sigil_regs`, `test_sigil_platform`, `test_sigil_hash`,
`test_sigil_host_cosim`) — logs in `sim/` and `xsim/`.

## #73 Linux release branch: gates (2026-10-22)

[`linux-release-73-gates-2026-10-22.log`](linux-release-73-gates-2026-10-22.log)
(`73-linux-release` at `a6051cd`, the merge of `73-f2-memory-platform` and
`73-linux-debian`; fresh clone on `sigil-fpga-build`): lint clean on Verilator
5.048, CI's 5.020 and 5.044; `make core-test` (241 TB PASS, 0 fail, including
`fpgatop-quick`, `fpgatop-f2-quick` and `fpgaocl-quick`), riscv-tests
**123/123**, `make test`, and `socrtl`, `sochash`, `examples` (7/7),
`fpgatop-quick`, `fpgatop-f2-quick` and `fpgaocl-quick` run explicitly.
The released OS artifacts match the branch's `SHA256SUMS` (12/12).
`soc_rtl_tb` built from the release RTL boots Linux 6.12 (`Image-initramfs`,
`sigil-sim.dtb`) to `SIGIL_LINUX_BOOT_OK` at **261,247,447 cycles** (17.5
min). All 825 kernel console lines are intact. The same boot on main's RTL
had 4 lines corrupted by #63. The QEMU acceptance run of the Debian image
passes 23/23. Full ACT was not rerun because `rtl/core` is byte-identical to
`main` (tree `f573234a`, the tree of the #53 ACT run, 2,577/2,578). Later
commits up to `ce9fe97` change no RTL; at that commit lint and
`fpgatop-f2-examples` (`hbm_touch`) pass. The first Debian boot on a real F2
came later (sections below): it oopsed on `agfi-0a1fd54ef68bdc754` (MMU walker
race #74); on `agfi-0c8aa56fde1a48495` with the fix it reached the login
prompt 5 min 48 s after the SoC release and passed 22/22 checks.

## #73 Linux release branch: re-check of the review fixes (2026-10-22)

[`linux-release-73-docs-recheck-2026-10-22.log`](linux-release-73-docs-recheck-2026-10-22.log)
(no F2 used): rerunning `f2_playground_setup.sh` now updates `~/sigil`
(`git pull --ff-only`), keeps `~/hello/hello.c` and does not reload a loaded
AFI (stubbed run). The `LINUX.md` §6 package install through QEMU `--net`
fails: QEMU 8.2.2's `virt` wires virtio interrupts to the PLIC of its second
NUMA socket, whose hart is parked (0 interrupts, 0 packets). The replacement,
a `qemu-user-static` chroot into the disk file on the host, ran verbatim from
`LINUX.md` on Ubuntu 24.04 (installs `sl` in 18 s, `e2fsck` clean), and the
changed disk boots in QEMU from a release-only layout and runs the package.

## #73 First Debian boot on a real F2: kernel oops, MMU race (2026-10-22, AFI `agfi-0a1fd54ef68bdc754`, branch `73-linux-debian`)

Run log and A/B table: [`linux-debian-73-2026-10-22/f2-oops-ab.txt`](linux-debian-73-2026-10-22/f2-oops-ab.txt);
console logs, experiment DTBs and inputs in [`f2-boot/`](linux-debian-73-2026-10-22/f2-boot/).
The published artifacts of the QEMU bring-up section above, booted exactly
per `docs/LINUX.md` §4 on the platform AFI (`f2.6xlarge`, core 62.5 MHz):

- **Worked:** 8 GiB disk loaded in 2.38 s (3.61 GB/s); OpenSBI → Linux
  6.12 with both NUMA nodes (48 GiB DDR4 node 0, 16 GiB HBM node 1),
  `/dev/pmem0` mounted, `Run /sbin/init` at kernel time 8.2 s, systemd
  257 up at 12.2 s, `Queued start job for default target` at 73.5 s
  (kernel time starts only after ~2 min of early memory setup, see the
  fixed-AFI run below).
- **Failed:** kernel oopses from 35–130 s into systemd startup in every
  Debian run — "Unable to handle kernel paging request" at valid
  linear-map addresses (anon_vma_clone, folio_lruvec_lock) and garbage
  pointers `0xcccccccccccccccc` (filemap_fault). No login prompt.
- **Bisection (13 runs):** still fails with no HBM, 2 GiB DDR4, every
  address below 4 GiB (384 MiB RAM + 1.6 GiB pmem at `0x9800_0000`), quiet
  console, a DT ISA of plain rv64imafdc, no jump labels/BPF, ASIDs
  disabled, `transparent_hugepage=never`. Passes: `memstress` (anonymous
  memory, FENCE.I, fork/COW, AMO/LR-SC; 0 bad in 651 s), and no oops in
  minutes of `execstress` (busybox fork/exec) or `pmemstress` (ext4 on
  pmem + dynamic exec from the Debian disk) — stress kernels from
  `scripts/build_stress_kernels.sh`.
- **Cause (RTL hunt, branches `73-oops-mmu` / `73-oops-sim-repro`):** an
  MMU walker race — a data-TLB miss preempting an in-flight fetch walk
  takes the fetch walk's outstanding PTE response as its own first PTE —
  needs code-page-crossing ITLB misses plus DDR-like latency; Debian's
  dynamically linked userland provides both. The Debian boot is re-run on
  the AFI with the fix.
- Platform notes for a later issue: SIGINT'd `sigil_host` runs left the
  SoC running; the following runs' consoles lost bytes until the AFI was
  reloaded; OpenSBI restarted by itself after some oopses.
- F2 time: OS agent 2.15 h (09:26–11:35 UTC); instance
  `i-0172708b8206bb63d` terminated 11:35 UTC.

## #73 Linux oops: fetch-walk preemption fix (2026-10-22, branch `73-oops-fix`)

Root cause, found by the oops hunt (branches `73-oops-mmu`,
`73-oops-sim-repro`, `73-oops-dcache`): `sigil_mmu` lets a data-TLB miss
preempt a fetch walk in `W_VS_READ`/`W_G_READ`, but `sigil_core` dropped a
walker read only on SFENCE.VMA or a trap. The fetch walk's PTE read was
then taken by the preempting data walk as its root PTE. Two triggers: the
read is already in flight (PTE line misses, uncached tables), or it is
issued in the same cycle as the preemption (a D$ hit). The result is a page
fault on a valid VA, or a wrong superpage translation that returns wrong
data without a trap. On F2 these are the two kernel oops signatures.

Fix: `sigil_mmu` reports `walk_abandon_o` when a walk ends without
consuming its PTE read. That covers the preemption and a G-stage
GPA-width fault, which leaves `W_G_READ` in the cycle it may issue its
read. The core drops the response of a walker read in flight or issued in
that cycle. The fix is unconditional. A new simulation-only assertion
(`a_walk_rsp`) checks that the walker only receives the response to its own
request.

[`oops-fix-73-2026-10-22/before_after.log`](oops-fix-73-2026-10-22/before_after.log):
the three new directed tests on the `73-linux-release` RTL (`5458d16`) and
on the fix, with the same binaries, on `core_tb` and on the opt-in checker
build (`make -C sim -f Makefile.oops`):

| test | 5458d16: `--mem-lat 1` / rand / `40:50` / `--no-cache` | fix |
|---|---|---|
| `ptw_preempt_directed` (uncached tables) | FAIL 0x10D (load page fault on a mapped VA), all 4 | PASS, all 4 |
| `ptw_preempt_cached_directed` | FAIL 0x1FF (wrong data, no trap), all 4 | PASS, all 4 |
| `ptw_preempt_twoload_directed` (same-cycle issue) | FAIL 0x11FF / 0x11FF / 0x11FF / 0x1FF (wrong data) | PASS, all 4 |

On the old RTL the checker reports one `stale-walk-rsp` per run. On the fix
it reports none. With `walk_abandon` masked out of the drop condition, the
assertion stops all three tests.

[`oops-fix-73-2026-10-22/gates.log`](oops-fix-73-2026-10-22/gates.log)
(`cb523fa`, fresh clone on `sigil-fpga-build`): lint is clean on 5.048,
5.020 and 5.044. `make core-test` passes with 253 TB PASS, 0 fail and no
assertion failures. That is the 241 of the release gate plus the three
tests in rand, uncached, xinit1 and xinit3, and 40/40 directed runs on
each SRAM-macro build. riscv-tests pass 123/123. `soc_rtl_tb` boots Linux
6.12 (`Image-initramfs`) to `SIGIL_LINUX_BOOT_OK` at 261,247,447 cycles,
the same count as the release gate, so the race did not occur in that
boot.

## #73 Linux oops: root cause, F2 signature analysis and full gates (2026-10-22, branch `73-oops-fix`)

[`linux-oops-fix-73-2026-10-22/`](linux-oops-fix-73-2026-10-22/README.md)
covers the Debian oopses on the F2.

**Root cause.** A data-TLB miss preempts an instruction-fetch walk, and the
data walk takes that walk's PTE response as its own root PTE. The fetch walk
reads kernel-text root entry 510, so the data walk indexes the kernel's PMD
table with a linear-map VA[29:21]. That gives both F2 signatures. All 13
valid-address faults in the F2 logs have VA[29:21] of 12 or more, which are
invalid entries ("Unable to handle kernel paging request" at a valid
address). VA[29:21] 3 and 4 map the freed `__init` region, which is poisoned
with `0xcc`, so the next dependent load faults at `cccccccccccccd1c`. Every
oops PC is the second of two dependent loads.

**Before/after.** The 13 walker race tests under the checkers pass 0/39 on
`5458d16` (30 stale walker responses) and 39/39 on the fix.

**Gates at `31a1568`:**
- lint is clean on Verilator 5.048, 5.020 and 5.044;
- `make test` passes;
- `core-test`: 293 TB PASS, 0 fail;
- riscv-tests: 123/123;
- full ACT: 2577/2578 (only the PA0 waiver fails; Vx/Vls/Vf all pass);
- `socrtl sochash examples fpgatop-quick fpgatop-f2-quick fpgaocl-quick srammacro` pass;
- the Linux 6.12 boot on `soc_rtl_tb` reaches `SIGIL_LINUX_BOOT_OK` with a console byte-identical to the release gate's.

**Linux stress under the checkers** (ptwstress v2, execstress): 0
`stale-walk-rsp`. The unpatched runs also report 0 at identical cycle
counts. In simulated Linux there was at most one fetch-walk preemption per
run, in the benign same-cycle-response corner, so simulation does not reach
the harmful case. The F2 boot with an AFI built from this branch
(`agfi-0c8aa56fde1a48495`, next two sections) passed: no oops, 22/22 checks.

Issues: #74 (the core bug) and #75 (F2 platform problems seen in the same
runs).

## #73 F2 AFI with the MMU walker-race fix: `agfi-0c8aa56fde1a48495` (2026-10-22, branch `73-oops-fix`)

[`f2-platform-73-oopsfix-2026-10-22/vivado/`](f2-platform-73-oopsfix-2026-10-22/vivado/build-steps.txt)
(build steps, manifest, `afi.json`, post-route timing and utilization).

- **Public AFI `afi-059766f9a85c6d39a` / AGFI `agfi-0c8aa56fde1a48495`**,
  us-east-1, shell `0x10212415`, PCI `0x1D0F:0xF054`, available 16:23 UTC;
  `loadPermission` group `all` and `Public: true` checked with
  `aws ec2 describe-fpga-image-attribute` / `describe-fpga-images`.
- Built from `73-oops-fix` commit **`31a1568`** with the script, flow and
  recipes of the platform AFI above: core 62.5 MHz (B1), HBM AXI 250 MHz
  (H0), unencrypted. Its RTL differs from the platform AFI's (`e641930`)
  only in `rtl/core/sigil_core.sv` and `rtl/core/sigil_mmu.sv` (the
  walker-race fix #74 and an atomic Svadu A/D update).
- Post-route: all constraints met, WNS **+0.095 ns** (core clock, 16 ns),
  HBM AXI +0.198 ns, WHS +0.010 ns; **131,259 LUTs (10.08 %)**, 117,030
  FFs, 75 RAMB36, 32 DSP for the CL, 82,201 LUTs for the SoC + OCL block.
  BuildAll 1 h 16 min on the r7iz.8xlarge (16 Vivado threads); a first
  attempt failed in `opt_design` when the build volume filled up.
- DCP tarball `2026_10_22-143914.Developer_CL.tar`, 110,192,640 bytes,
  sha256 `9dd83d291f2bea57026f3eb1d623c89260273fb0c051be318ecbba449a30d246`
  (`s3://sigil-fpga-afi-891612553438/dcp/`, downloaded again and checked);
  its routed DCP hashes to the manifest `dcp_hash` `53eed162…11fe73`.
  Release asset `sigil_f2_linux_cl_dcp_31a1568.Developer_CL.tar`.
- The release branch ships this RTL: `git diff 31a15689 73-linux-release
  -- rtl/ fpga/cl_sigil/` is empty; under `fpga/` only the host helper
  scripts differ (`sigil-linux`, `sigil-run`, `f2_playground_setup.sh`
  name the new AGFI and the measured boot time), which are not part of the
  CL.
- The memory-platform hardware tests ran on the platform AFI and were not
  repeated on this one; Debian on this AFI is the next section.

## #73 Debian on the F2 with the walker-race fix: login, 22/22 checks, disk persists (2026-10-22, AFI `agfi-0c8aa56fde1a48495`, branch `73-linux-debian`)

Logs: [`linux-debian-73-2026-10-22/f2-boot-fixed/`](linux-debian-73-2026-10-22/f2-boot-fixed/)
(`f2-run1.txt` full console of boot + acceptance, `f2-run2.txt` second boot
from the saved disk, `*-summary.txt` check summaries, `f2-instance-info.txt`).
Same published OS artifacts as above (sha256 in `f2-instance-info.txt`),
booted exactly per `docs/LINUX.md` §4 on AFI `afi-059766f9a85c6d39a` /
`agfi-0c8aa56fde1a48495` (branch `73-oops-fix`, RTL `31a1568`: stale MMU
walker response dropped on preempt/abandon, Svadu A/D write-back lock),
`f2.6xlarge` `i-0c58fa4d79908ae8b`, core **62.500 MHz** measured.

- **No oops** in either boot (`Oops`/`BUG:`/`WARNING:` count 0).
- **Boot time** (wall clock from SoC release, 8 GiB disk loaded in 2.42 s
  before it): `SIGIL_LINUX_BOOT_OK` at **337.7 s**, **login prompt at
  347.9 s (5 min 48 s)**; second boot 333.2 s / 343.2 s. Of this, ~129 s
  is OpenSBI + early kernel memory setup for 64 + 16 GiB before the kernel
  clock starts; then kernel 10.6 s (`Run /sbin/init` at 8.2 s) and systemd
  userspace 3 min 25.5 s (`systemd-analyze`; `blame` led by
  `dev-pmem0.device` 2 min 13 s, journald 54 s, logind 48 s, udev-trigger
  47 s). The QEMU icount estimate (≈ 9 min) was pessimistic: an estimated 5 core
  cycles per instruction overall (F2 kernel time divided by the QEMU icount
  instruction count), not 13.
- **Acceptance: 22/22 PASS** (`scripts/qemu_sigil_check.py --label F2
  --scale 40 --no-reboot --release 'SoC released'`): login as `sigil`;
  `uname` 6.12.114-sigil riscv64 + Debian 13; `/proc/cpuinfo` isa with
  zve64d, `uarch sigil,core`, sv39; systemd `running`, no failed units;
  `/` = `/dev/pmem0` ext4 rw; `numactl --hardware` **2 nodes: node 0 48305
  MB (cpus 0), node 1 16110 MB (no cpus)**, distances 10/20; `free -h` 62 GiB;
  `time (gcc hello.c && ./a.out)` **22.9 s**; `make` of the 6 examples
  6 min 23 s; `malloc_test 512` MALLOC OK; `numa_hbm 256` all pages on the
  requested node, dependent load DDR4 1791 ns vs HBM 1878 ns (with TLB
  misses); `memwhere 1024` node 0, **`numactl --membind=1` → node 1: 1024
  MiB**, interleave 512 + 512; `rvv_vadd` RVV OK (VLEN 512); `autovec` 7
  vector instructions; sudo; `python3 -c` **9.9 s**; git/gdb/strace/vim/
  file/man; a stamp file written; `sudo poweroff` → `reboot: Power down`
  → `finisher: power off` → host saved the 8 GiB window (0.81 GB/s).
- **Persistence: PASS** — run 2 loads the saved disk, logs in as root, the
  stamp file is there (`journalctl --list-boots` shows both boots), power
  off.
- F2 time: 0.78 h (16:34–17:21 UTC), instance terminated.

## #73 Linux release branch: final gates at `1d72210` (2026-10-22)

[`linux-release-73-final-gates-2026-10-22.log`](linux-release-73-final-gates-2026-10-22.log)
(`73-linux-release` at `1d72210`, which includes the walker-race fix #74 and
the F2 Debian results; fresh clone on `sigil-fpga-build`, at most 8 jobs):
lint is clean on Verilator 5.048, CI's 5.020 and 5.044. `make test` passes.
`make core-test` gives 293 TB PASS and 0 fail, with each walker race test
passing in rand, nocache, xinit1 and xinit3. riscv-tests pass **123/123**.
`socrtl`, `sochash`, `examples` (7/7), `fpgatop-quick`, `fpgatop-f2-quick`
and `fpgaocl-quick` pass with the release gate's cycle counts. The walker
race checker targets pass: `oops-ptw-preempt` 9/9 and `oops-ptw-walker`
**39/39** with 0 stale walker responses and 0 PTWINV violations, and their
result lines are identical to the fix branch's. The OS artifacts match the
branch's `SHA256SUMS` (12/12). `soc_rtl_tb` boots Linux 6.12 to
`SIGIL_LINUX_BOOT_OK` at **261,247,447 cycles** with a console
byte-identical to the earlier gates and no oops. Full ACT was not rerun:
`rtl/` (tree `c8bafdb2`), `tb/`, `sim/` and the ACT scripts are identical to
`31a15689`, where full ACT gave 2,577/2,578 (only the PA0 waiver fails).

## #73 Linux release branch: checks of the second review's fixes (2026-10-22)

[`linux-release-73-review-fixes-2026-10-22.log`](linux-release-73-review-fixes-2026-10-22.log)
(`73-linux-release`, `1d72210..62370e1`): documentation only. No file
other than Markdown and evidence logs changed since `1d72210`, so its final
gates hold, and `rtl/` and `fpga/cl_sigil/` still equal `31a15689`. The
fixes label the 5 cycles per instruction as an estimate, state that the
walker race (#74) is in every earlier core (the first public AFI
`agfi-035116450e0a0d093` is for bare-metal programs only), point the status
table at the runs on the shipped RTL, and add #75 to `LINUX.md`. No
relative link or anchor is broken. The notes checklist's placeholder grep
prints nothing. The superseded AFI appears only as history.

## #8: riscv-dv random regression vs Spike (2026-10-22)

[`riscv-dv-8-2026-10-22/`](riscv-dv-8-2026-10-22/). Flow, pins and
rules: [`docs/VERIFICATION.md`](../VERIFICATION.md). Random programs
from riscv-dv's Python generator (pygen, `0d71c2b6`, patched: fixes
A-AD in `sim/riscv-dv/patches/pygen-sigil.patch`) run on Spike
(`2c300cd9`, configured as Sigil: [`spike-build.txt`](riscv-dv-8-2026-10-22/spike-build.txt))
and on the core (`build/sim/core_tb`, Verilator 5.048, sim-only retire
trace); every retired instruction and trap is compared. sigil-verify
(c7i.8xlarge, Ubuntu 24.04.5), shared machine.

- **Full regression, 60/60 PASS** (`./scripts/riscv_dv_regress.sh
  --seeds 1-3 --jobs 14`, branch at `384d813`): 18 riscv-dv built-in
  tests + 2 directed programs (Zba/Zbb/Zbs/Zbk*/Zkn/Zicond; RVV) x 3
  seeds, 680,586 records compared incl. 582 traps (441 breakpoints, 84
  illegal instructions, 54 ECALLs, 3 misaligned), boot modes M/S/U:
  [`results-full-seeds1-3.csv`](riscv-dv-8-2026-10-22/results-full-seeds1-3.csv),
  [`coverage-full-seeds1-3.csv`](riscv-dv-8-2026-10-22/coverage-full-seeds1-3.csv),
  1483 s with 14 jobs.
- **Confirmation on the final head, 60/60 PASS** (`make -C sim riscv-dv
  SEEDS=4-6 JOBS=7`, `661c046`): 673,480 records, 542 traps:
  [`results-full-seeds4-6.csv`](riscv-dv-8-2026-10-22/results-full-seeds4-6.csv),
  [`coverage-full-seeds4-6.csv`](riscv-dv-8-2026-10-22/coverage-full-seeds4-6.csv).
- Fields compared (integer/FP/vector register writes, stores, CSR
  writes, fflags): [`compared-fields.txt`](riscv-dv-8-2026-10-22/compared-fields.txt);
  comparator self-check on corrupted traces:
  [`comparator-selfcheck.log`](riscv-dv-8-2026-10-22/comparator-selfcheck.log);
  artifact sample: [`sample-riscv_amo_test-seed21.txt`](riscv-dv-8-2026-10-22/sample-riscv_amo_test-seed21.txt).
- core_tb built with Verilator 5.020 runs the flow: 4/4 PASS,
  [`results-verilator-5.020.csv`](riscv-dv-8-2026-10-22/results-verilator-5.020.csv).
- Gates with the trace probe in the RTL (`661c046`): `make lint` clean on
  Verilator 5.048, 5.020 and 5.044 ([`lint-verilator-5.048.log`](riscv-dv-8-2026-10-22/lint-verilator-5.048.log),
  [`lint-verilator-5.020.log`](riscv-dv-8-2026-10-22/lint-verilator-5.020.log),
  [`lint-verilator-5.044.log`](riscv-dv-8-2026-10-22/lint-verilator-5.044.log));
  `make core-test` rc=0, 0 TB FAIL/TIMEOUT; `make riscv-tests` 123/123:
  [`gates-core-test-riscv-tests.log`](riscv-dv-8-2026-10-22/gates-core-test-riscv-tests.log).
- Findings: no divergence attributable to a Sigil bug. LR/SC of
  different widths has an implementation-defined SC outcome (Sigil fails
  `sc.d` after `lr.w`, Spike succeeds); the generator now pairs widths:
  [`lrsc-width-mismatch-compare.txt`](riscv-dv-8-2026-10-22/lrsc-width-mismatch-compare.txt).
- Not covered: address translation, PMP programming, interrupts, trap
  delegation, sub-programs, random CSR accesses; V/Zk/Zicond only via the
  directed programs; 18 riscv-dv tests excluded with reasons in
  `sim/riscv-dv/testlist.yaml`. Not in CI yet.

## #8: riscv-dv round-1 GEN_FAILs were generator out-of-memory kills (2026-10-22)

[`riscv-dv-8-2026-10-22/pygen-amo-oom/`](riscv-dv-8-2026-10-22/pygen-amo-oom/).
Flow and the fix: [`docs/VERIFICATION.md`](../VERIFICATION.md)
("Generator memory"). sigil-verify (c7i.8xlarge, 61 GiB, no swap,
shared with the perf harness); Spike `2c300cd9`, riscv-dv `0d71c2b6`,
Verilator 5.048, Python 3.12.3.

- **Cause** (round 1, `--tests all --seeds 100000-100009 --jobs 16`,
  runner at `b86bc8d`): 196 PASS, 4 `GEN_FAIL` `pygen rc=-9`
  (`riscv_amo_test` 100000/100001/100002/100006). All ten amo
  generations ran at once at about 8 GiB each; the kernel OOM-killed
  four python3 processes (anon-rss 7.3-8.0 GiB, 10:38-10:40 UTC); each
  killed `gen.log` stops at "Start generating 5000 instruction" with no
  traceback, and no program was written, so the core never ran them.
  Rerun alone they match Spike (4553/4635/4215/4304 records):
  [`round1-gen-fail.txt`](riscv-dv-8-2026-10-22/pygen-amo-oom/round1-gen-fail.txt).
- **Fix** (`9e64bc3`, `d02176b`): `rdv_regress.py` runs pygen under a
  memory budget (`--gen-mem-gb`, default 75% of MemAvailable; per-test
  `gen_mem_gb` in `testlist.yaml`, 9 for `riscv_amo_test`, default 2.5),
  queues jobs seed-major, records pygen's peak RSS (`gen_rss_mb`) and
  labels a SIGKILLed pygen as a likely OOM kill. Later commits
  (`74d5673` comments, `59fd02a` a `%` in the `--help` text) do not
  change what a run does, so the runs below at `d02176b` stand.
- **Peak RSS per test** (one seed each, 20/20 PASS): amo 7.8 GiB, all
  others 0.9-1.9 GiB:
  [`measure-peak-rss.txt`](riscv-dv-8-2026-10-22/pygen-amo-oom/measure-peak-rss.txt).
- **Representative rerun, 10/10 PASS** (`--tests riscv_amo_test --seeds
  100000-100009 --jobs 16`, `d02176b`): budget 44.4 GiB, generations
  ran four at a time (never more than 4 pygen processes above 1 GiB),
  lowest MemAvailable 26.9 GiB; records match the round-1 reruns:
  [`amo10-rerun.txt`](riscv-dv-8-2026-10-22/pygen-amo-oom/amo10-rerun.txt).
- **Round-1 command on the fixed runner, 200/200 PASS** (`d02176b`,
  3209 s): 2,231,764 records compared (the same total as round 1 after
  its rerun), pygen peaks amo 7.8-8.4 GiB and others 0.9-2.0 GiB over 10
  seeds, lowest MemAvailable 37.0 GiB, no new kernel OOM kill:
  [`full-regression.txt`](riscv-dv-8-2026-10-22/pygen-amo-oom/full-regression.txt),
  [`full-results.csv`](riscv-dv-8-2026-10-22/pygen-amo-oom/full-results.csv).

## #8: riscv-dv completeness review: three core bugs, random RVV/privileged/HINT programs, CI (2026-10-22)

Summary of every riscv-dv round, root cause and waiver:
[`riscv-dv-8-2026-10-22/SUMMARY.md`](riscv-dv-8-2026-10-22/SUMMARY.md).
Review files: [`riscv-dv-8-2026-10-22/critic/`](riscv-dv-8-2026-10-22/critic/),
[`riscv-dv-8-2026-10-22/rounds/`](riscv-dv-8-2026-10-22/rounds/). Flow:
[`docs/VERIFICATION.md`](../VERIFICATION.md). sigil-verify (c7i.8xlarge,
Ubuntu 24.04.5, shared), Spike `2c300cd9`, riscv-dv `0d71c2b6` + patches
A-AE, Verilator 5.048 (CI replays: 5.020), GCC 16.1.0, Python 3.12.3.

- **Random RVV program** (`e7a82fe`): `sigil_vector_test` was a fixed
  53-instruction program; it now draws vtype, AVL, vxrm, frm, operands
  and data per seed. Its first run failed 8 of 8 seeds: `viota.m` with a
  mask register not aligned to LMUL trapped, and the SEW=32 `.vf` moves
  did not NaN-box check their scalar (core, fixed in `63a50a5`, directed
  checks `vec_directed` 25 and `fpvec_directed` 11):
  [`core-findings.txt`](riscv-dv-8-2026-10-22/critic/core-findings.txt).
  Vector registers in the retire trace were read too late (probe,
  `862868c`/`e1c4338`): [`trace-snapshot.txt`](riscv-dv-8-2026-10-22/critic/trace-snapshot.txt).
- **Misaligned accesses resume** (patch AE, ~2,000 traps per run) and a
  per-test Spike budget (`a397c78`):
  [`unaligned-and-spike-budget.txt`](riscv-dv-8-2026-10-22/critic/unaligned-and-spike-budget.txt);
  **comparator** checks one-sided vector writes (`34ddf8e`):
  [`comparator-selfcheck-v2.log`](riscv-dv-8-2026-10-22/critic/comparator-selfcheck-v2.log).
- **main merged into the branch** (`adf4c97`, conflicts in `core_tb.cpp`,
  `sim/Makefile`, this file): the full list and a CI replay give the same
  records and cycles as before the merge.
- **Random privileged program** `sigil_priv_test` (`a36305c`, `c98428b`):
  Sv39/Svnapot/2 MiB mappings with random permissions and reserved bits,
  hardware D updates (Spike `svadu`), random PMP (NA4/NAPOT/TOR), random
  delegation, S-level interrupts via `mip`, random mstatus. It found that
  **PMP decided an 8-byte access by its first word** (core, fixed in
  `3ae351d`; new core test `pmp_partial_directed`; `vec_trap_directed`
  test 11 corrected in `37aa1d7`):
  [`pmp-partial-match.txt`](riscv-dv-8-2026-10-22/critic/pmp-partial-match.txt).
  Bring-up against Spike (CLINT MTIP, `medeleg`/`mideleg` WARL choices):
  [`priv/program-bringup.txt`](riscv-dv-8-2026-10-22/critic/priv/program-bringup.txt).
- **Random HINT program** `sigil_hint_test` (`c73c4a6`) in place of the
  excluded `riscv_hint_instr_test` (pygen's solve failure:
  [`hint-test-gen-fail.txt`](riscv-dv-8-2026-10-22/critic/hint-test-gen-fail.txt)).
- **Runs**: [`full-regression.txt`](riscv-dv-8-2026-10-22/critic/full-regression.txt)
  (sections 1-6; results and coverage CSVs next to it). Full list on
  `c98428b`: 105/105 PASS, 3,100,449 records. The four directed programs
  x seeds 1-205 on `37aa1d7`: 820/820 PASS, 97,111,729 records.
- **CI**: `.github/workflows/riscv-dv.yml` (nightly + `workflow_dispatch`,
  never on push or pull_request, not a required check) and
  `scripts/build_spike.sh`; not run on GitHub yet (`workflow_dispatch`
  needs it on `main`); replayed from a fresh clone with apt Verilator
  5.020 on `e1c4338` and `adf4c97`, 20/20 PASS each:
  [`ci-replay.txt`](riscv-dv-8-2026-10-22/critic/ci-replay.txt).
- **Gates** (`37aa1d7`): `make lint` rc=0 on Verilator 5.044 (Mac),
  5.048 and 5.020 (sigil-verify); `make test` rc=0; `make core-test`
  rc=0 (297 "TB PASS", 0 FAIL, 2,609 s); `make riscv-tests` 123/123:
  [`gates/`](riscv-dv-8-2026-10-22/critic/gates/). The first run, on
  `c98428b`, stopped core-test at `vec_trap_directed` test 11 (fixed in
  `37aa1d7`).
- **Full ACT** (`65a48ae`, 2026-10-23, sigil-verify, Verilator 5.048,
  core_tb default config, the 2,578-ELF set of main's gates, fingerprint
  `839ba8be…`): 2,577/2,578, only the `PMPSm_cfg_A_tor_zero-00` PA0
  waiver fails. Main `9da0006` rerun on the same ELFs and machine gives
  the same result with every ELF's verdict and cycle count equal, and
  the waiver's core_tb bus trace is byte-identical on both:
  [`act-full.log`](riscv-dv-8-2026-10-22/act-full.log),
  [`act-full-8-riscv-dv-65a48ae.csv`](riscv-dv-8-2026-10-22/act-full-8-riscv-dv-65a48ae.csv),
  [`act-full-main-9da0006.csv`](riscv-dv-8-2026-10-22/act-full-main-9da0006.csv).

## #8: review round 2 and merge-ready gates (2026-10-23)

Ready-to-merge report:
[`riscv-dv-8-2026-10-22/final/merge-ready.txt`](riscv-dv-8-2026-10-22/final/merge-ready.txt).
The reviews of the three first fixes (branches `8-dvfix-viota`,
`8-dvfix-nanbox`, `8-dvfix-pmp`, `8-dvfix-pmp-w64`, merged into
`8-riscv-dv`) proved four more core defects, all fixed with directed
tests: `vstart` != 0 not illegal for reductions, `vcpop`/`vfirst`,
`vmsbf/sif/sof`, `viota`, `vcompress` (`fd22878`); `viota.m` with vs2
inside the vd group (reserved) not trapped as on Spike (`913bc0a`); the
int16 <-> f32 conversions trapped at SEW=16 (`1eac727`); `vl<n>re64.v`
elements PMP-checked byte by byte (`9bdd552`). Issues: #76, #77, #78.

- **Gates** on RTL `1eac727`: lint (Verilator 5.044, 5.048, 5.020),
  `make test`, `make core-test`, `make riscv-tests`, full ACT
  (2,577/2,578, every ELF's verdict and cycle count as on main), riscv-dv
  vs Spike, Linux RTL boot:
  [`final/gates/`](riscv-dv-8-2026-10-22/final/gates/),
  [`final/act/`](riscv-dv-8-2026-10-22/final/act/),
  [`final/rdv/`](riscv-dv-8-2026-10-22/final/rdv/).
- **New tests on Spike and mutants** of each new fix (each mutant fails
  its test; why the EX hold behind a vector load/store is needed):
  [`final/mutation/mutation.txt`](riscv-dv-8-2026-10-22/final/mutation/mutation.txt).
- **Synthesized logic** vs `f239397` and main: only `sigil_core` and
  `sigil_vec` change, at the new fixes' signals, proven by Yosys in the
  five synthesis define sets:
  [`final/synth/synth-equiv-round2.log`](riscv-dv-8-2026-10-22/final/synth/synth-equiv-round2.log).
- **Port to `53-100mhz-afi`** (FPGA_TIMING parallel PMP): file:line list in
  the report.

## #53 on the #73 oops fix: FPGA_TIMING with the walker race fixes (2026-10-22, branch `53-100mhz-afi`)

- Artifacts: [`fpga-timing-100mhz-afi-53-2026-10-22/`](fpga-timing-100mhz-afi-53-2026-10-22/README.md)
- What: `73-oops-fix` with `53-mem-stage-pipeline` merged in. This is
  the source for the 100 MHz AFI.
  - FPGA_TIMING=0: Yosys proves the RTL equivalent to `73-oops-fix`
    (sigil_csr, sigil_mmu, both caches, and sigil_core in the default
    and `SIGIL_SRAM_OREG` configurations).
  - FPGA_TIMING=1: the walker's A/D lock also masks #53's flop-driven
    data-port select. Without the mask, a FENCE.I in MEM during the lock
    deadlocks; the new `ptw_lock_fencei_directed` reaches that case.
- Gates in both configurations:
  - lint clean on Verilator 5.048, 5.020 and 5.044;
  - walker race set 42/42 under the checkers;
  - walker matrix 133/133;
  - core-test rc 0;
  - riscv-tests 123/123.
- With FPGA_TIMING on:
  - Linux 6.12 boot reaches `SIGIL_LINUX_BOOT_OK`;
  - full ACT is 2577/2578 (only `PMPSm_cfg_A_tor_zero-00`).
- Caveat: with FPGA_TIMING the A/D race tests pass even with the lock
  removed. Each walker grant forces MEM to replay its translation, so
  the write-back always gets the port first. The lock still holds
  FENCE.I back, and it is the guarantee for any case where the
  write-back misses that cycle (README, `fpga_controls.log`).

## #53 on F2: 100 MHz core-clock CL builds meet timing (2026-10-22, branch `53-100mhz-afi`)

- Artifacts: [`f2-100mhz-cl-2026-10-22/`](f2-100mhz-cl-2026-10-22/README.md)
- What: the first full F2 CL builds at 100 MHz.
  - Both use `build_cl_sigil.sh --recipe-b B5 --recipe-hbm H0 --fpga-timing`.
    B5 sets `clk_extra_b1` to 100 MHz.
  - `SIGIL_FPGA_TIMING` and `SIGIL_VRF_OREG` reach CL synthesis (checked
    in the build log and the post-synth netlist).
- Build 2 (`2026_10_22-232507`, from `cf63ab8`) is the AFI
  **`agfi-05cbbdc9f2ee7b87b`** (`afi-090769c4f8c375270`, available, still
  private). It includes the #53 review round 2 fixes (#53 up to
  `d8d5e92`; the later #53 commits `08c607a` and `73c52c7` change no RTL).
  - Design WNS +0.033 ns (Shell-side DDR crossbar IP on `clk_main_a0`),
    WHS +0.005 ns.
  - Core clock: WNS +0.336 ns at 10 ns.
  - Bus skew met. No CL or RTL change was needed for timing.
- Build 1 (`2026_10_22-211218`, from `cb6c1a2`, before those fixes)
  also met timing: WNS +0.049 ns, core +0.460 ns.
- Gates at the head `0deea68` (RTL = `cf63ab8`), in both settings:
  - lint;
  - walker race set 42/42;
  - core-test rc 0, with 74/74 directed runs per family and `fpgatop-f2-quick`;
  - riscv-tests 123/123;
  - the FPGA_TIMING=0 equivalence vs `73-oops-fix`.
- Software for it: `sw/linux/dts/sigil-f2-100.dts` (`sigil-f2-100.dtb`,
  timebase 100 MHz); `sigil_host` reports the core clock, checks the DTB
  timebase against it and has `--info`; `sigil-linux` picks the DTB by
  clock. Tested with the DTB helper tests, two XSIM `sigil_host`
  co-simulations and the `sigil-linux` harness (`sw/`).
- Caveat: static timing and simulation only. Nothing has run on hardware
  at 100 MHz yet.

## Debian on the F2 at 100 MHz — trial on candidate AFI `agfi-05cbbdc9f2ee7b87b` (2026-10-23, branch `53-100mhz-debian-trial`)

**Trial, not release evidence**: the final 100 MHz AFI is rebuilt with three
more core fixes. Details and logs: [`linux-100mhz-trial-2026-10-23/`](linux-100mhz-trial-2026-10-23/)
([`SUMMARY.txt`](linux-100mhz-trial-2026-10-23/SUMMARY.txt), console logs of
both runs, `sigil_host --info`, instance and artifact sha256s).

- Candidate AFI `afi-090769c4f8c375270` / `agfi-05cbbdc9f2ee7b87b` (private,
  `53-100mhz-afi` @ `cf63ab8`, recipe B5): `sigil_host --info` reports
  `core_clk_khz=100000`, measured core clock 100.000 MHz. Unchanged OS
  artifacts plus `sigil-f2-100.dtb` (timebase 100 MHz, sha256 `06925c9a…`).
- **Run 1: 24/24 PASS** (the 22 Debian checks plus two timebase checks),
  **run 2 (save + reload persistence): 2/2 PASS**, no oops.
- **Login prompt 237.5 s after release (3 min 58 s) vs 347.9 s at 62.5 MHz:
  1.46× faster** (clock ×1.6; memory latency in ns does not scale).
  `gcc hello.c` 15.4 s (22.9 s), `python3 -c` 6.9 s (9.9 s), `make` of the
  examples 4 min 24 s (6 min 23 s), `systemd-analyze` 7.3 s + 2 min 16 s.
- **Timebase validated**: `sleep 10` = 10.21 s host wall time; guest `date`
  vs host clock −0.353 s after login and −0.357 s 997.5 s later (4 ppm).
- Harness note: the first attempt with relative `--load` paths failed in
  this `sigil_host` (`cannot open … No such file or directory`); absolute
  paths work. F2: 0.62 h (`i-07522c9e3abec4345`, terminated); the earlier
  attempt `i-0285371bffa2b1270` was cut off by the network outage and ended
  by its cost guard (~2.0 h).

## 100 MHz integration: relative-path root cause, PMP port proof, gates (2026-10-24, branch `53-100mhz-afi`)

Integration step on `53-100mhz-afi` (main 3b7ed1b + #53 4421934 + the 100 MHz
trial tooling). Details: [`fpga-100mhz-final-2026-10-24/`](fpga-100mhz-final-2026-10-24/).

- **Relative `--load` failure of the 100 MHz trial (#75): not `sigil_host`.**
  The trial driver sourced aws-fpga's `sdk_setup.sh` from outside the
  aws-fpga checkout. That fails (it finds the checkout with `git rev-parse`
  in the caller's directory) after `cd`-ing into the checkout, and returns
  without `cd`-ing back, so the driver's relative paths named files in
  `~/aws-fpga`. Replayed on sigil-fpga-build against aws-fpga v2.3.5. Since
  then, `sigil_host` checks every image and `--save`/`--log` directory
  before it touches the FPGA, and its path errors name the working
  directory. `docs/FPGA_F2.md` explains how to source `sdk_setup.sh`.
  New host-side test without an FPGA (`fpga/host/test/`: a mock of the
  SDK and the CL, six cases on the trial's invocation), run by `make -C
  fpga/host test` and `make test`:
  [`host-relative-paths/README.txt`](fpga-100mhz-final-2026-10-24/host-relative-paths/README.txt).
- **`pmp_check_par == pmp_check`** (the FPGA_TIMING port of #78) is proven
  by a Yosys SAT miter generated from `sigil_csr.sv`'s functions; three
  mutants are refuted:
  [`pmp-par-proof/README.txt`](fpga-100mhz-final-2026-10-24/pmp-par-proof/README.txt).
- **Test fix**: on 1892e0e, core-test stopped at `mem53_ctx_directed`
  test 10 in both settings. Its NA4 PMP entry under an 8-byte `ld` now
  fails by #78's partial-match rule. The entry is now NAPOT 8 bytes
  (`ade85a9`).
- **Gates** (RTL at `ade85a9`, `make test` again at `b1a505f`; the RTL,
  sim, sw and tb trees are identical between the two). Both settings
  (define unset; `SIGIL_FPGA_TIMING` + `SIGIL_VRF_OREG`): lint on
  Verilator 5.048, 5.020 and 5.044, `make test`, the oops walker set, `make
  -k core-test` (375 / 372 `CORE TB PASS`, 0 FAIL, all new #8 directed
  tests included), riscv-tests 123/123. All pass:
  [`gates/GATES.txt`](fpga-100mhz-final-2026-10-24/gates/GATES.txt).
