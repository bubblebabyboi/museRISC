# Sigil — Remaining Work Plan (agent handoff)

- Date: 2026-10-20
- Repo: `bubblebabyboi/sigil` (local checkout: `Sigil/`)
- State at writing: local branch `integrate-prs`, 61 commits ahead of
  `origin/main`, working tree clean. 18 stacked PRs (#33–#50) are open
  upstream and merged locally in that order on `integrate-prs`.
- Purpose: everything left to do, in executable order, so a fresh AI
  agent (or human) can pick up any work package without re-deriving
  project state. Read this file first, then `AGENTS.md`, then the
  issue for the package you take.

## How to use this plan

1. Do **W0 first**. Nothing else in this plan is true on `main` until
   the open PR stack lands. Do not re-implement anything the stack
   already contains.
2. After W0, packages W1–W8 are mostly independent tracks. Respect
   the stated dependencies; otherwise pick one track and finish it.
3. Every package ends the same way: gates green, dated evidence under
   `docs/evidence/`, docs updated in the same change, issue closed
   only with a link to that evidence. A claim without committed
   evidence does not exist in this project.
4. Work in a git worktree on your own branch, never in the main
   checkout (`AGENTS.md`: run `scripts/worktree_setup.sh` inside the
   worktree; never write into symlinked `deps/` or `third_party/`).
5. In every shell: `source deps/env.sh`. First-time setup in the main
   checkout: `./scripts/install_deps.sh --gcc15` and
   `./scripts/setup.sh --fetch-act`.
6. Run anything over ~2 minutes (Verilator builds, `make core-test`,
   riscv-tests, ACT, synthesis, OpenROAD) in the background with
   output to a log under `build/`, and report wall-clock time.
7. Before opening a PR that touches RTL or testbenches, also lint
   with CI's Verilator 5.020 in Docker (exact command in
   `AGENTS.md`). Local `deps/` Verilator is 5.048 and accepts
   constructs 5.020 rejects. Never install 5.020 system-wide.
8. Never commit, push, or open a PR unless the owner asked for that
   exact action in this session.

## Current state (verified 2026-10-20 — do not redo)

- In-house 5-stage RV64 core (`rtl/core/`) is functionally complete:
  IMABC + F/D + B/Zicond/scalar-crypto + H hypervisor + integer and
  FP vector (RVV 1.0, VLEN 512). Stages 1–9 in `docs/CORE.md` are
  done. CVA6/Ara are historical references only, not the product.
- Gates on record: riscv-tests 123/123; ACT 2577/2578 (one
  documented waiver, `PMPSm_cfg_A_tor_zero-00`, a harness/platform
  mismatch at PA 0 — see `docs/evidence/README.md`); ACT integer
  vector 1872/1872; ACT FP vector 162/162; OpenSBI v1.9 + Linux 6.6
  boot to initramfs `/init` (`SIGIL_LINUX_BOOT_OK`, ~509M cycles);
  Linux KVM smoke (VM/vCPU + 4-instruction guest MMIO exit — not a
  guest-OS boot); crypto KATs pass (`make test`).
- Synthesizable SoC exists (`rtl/soc/`): core + L1 I$/D$ behind one
  memory bus, boot ROM, CLINT, PLIC, UART16550, crypto attached at
  `0x2000_0000` via an AXI-Lite bridge. On-core test
  `sw/soc-tests/crypto_soc_test.c` passes `SOC CRYPTO PASS`
  (SHA-256 + field ops + secp256k1 ECDSA verify) in `soc_rtl_tb`.
- Synthesis (not P&R): whole SoC synthesizes with all 15 large
  arrays on SRAM macros. Nangate45: 0.66 mm², 162 MHz unrepaired.
  Sky130hd: 8.59 mm² synthesized, ~11.8–13.5 mm² placed estimate,
  12.3 MHz unrepaired (OpenRAM half-cycle reads dominate). Detail:
  `docs/SOC_AREA.md`. Standalone `sigil_crypto` macro has an older
  full OpenROAD P&R + GDS (nangate45, issue #3, closed).
- Stale docs warning: `docs/TASKS.md` and `docs/ROADMAP.md` predate
  the in-house core. They still show B3/B4 pending and Ara-era
  items. Trust `README.md`, `docs/CORE.md`, `docs/evidence/`, and
  GitHub issue state over those two files until W0 fixes them.

## Goal

Close the remaining distance between "verified in simulation" and
"usable": land the finished RTL on `main`, close the last baseline
gate, complete the crypto feature set under a security review,
harden verification with random regression, and produce at least
one physical proof (full-SoC OpenROAD closure and/or FPGA Linux
boot) with honest, dated evidence for every claim.

## Success criteria (whole plan)

- `main` contains the full #33–#50 stack; all four CI workflows
  green; branch protection enabled.
- Issue #4 (B4) closed with committed on-core evidence including
  Ed25519 verify.
- Each finished track (W1–W8) has its acceptance evidence committed
  under `docs/evidence/` and its issue closed against that evidence.
- No new claim (ISA, frequency, area, boot, security) appears in
  `README.md` or `docs/COMPLIANCE.md` without a reproducing gate.
- No private-key handling anywhere before W4 (issue #12) closes.

## Approach and key decisions

- **Land before building.** The PR stack is already reviewed-shaped
  as 18 separate units. Preserve that split: merge in numeric
  order, one PR at a time, re-running its stated gates. Do not
  squash the stack into one mega-merge; the per-PR evidence files
  are the audit trail.
- **Simulation evidence before spend.** No AWS F2 hours (W8/F4) and
  no MPW commitment (W7) until the cheap simulation/synthesis gates
  for that track pass.
- **Security gates usage, not development.** W2/W3 crypto features
  may be built and KAT-tested before W4, but no real keys, no
  "production" wording, and no README warning removal until W4.
- **Performance is not a goal yet.** Blocking L1 caches and the
  element-serial vector unit are correctness-first by design
  (`docs/CORE.md`). Do not optimize IPC unless a package says so;
  if you touch timing/area, keep ISA semantics bit-exact and
  re-run the full gates.
- **Sky130 size needs an owner decision** (see Open questions)
  before W7 P&R: current caches do not fit Caravel. The default
  assumption in this plan is "shrink L1 to 4 KiB + 4 KiB for the
  sky130 config only" — reversible, parameter-only — unless the
  owner chooses otherwise.

## Work packages

### W0 — Land the PR stack and refresh tracking docs (do first)

Issues: PRs #33–#50; epics #18, #24, #26. Depends on: nothing.

1. For each PR in order #33 → #50: confirm CI green, confirm its
   evidence files are in the diff, merge to `main`. If a PR
   conflicts after its predecessor merges, rebase only that PR,
   re-run `make lint` (5.048 + Docker 5.020), `make test`,
   `make core-test`, `make riscv-tests`, then merge. Full ACT
   (`scripts/build_act4_core.sh`, then `sim/run_act_core_par.sh`)
   at least after #38, #41, #43, #44, #47, #50 and at the end.
2. After #50: run the full local gate set on clean `main` (see
   Validation) and confirm the four workflows in
   `.github/workflows/` are green on the merge commits.
3. Delete or retire the local `integrate-prs` branch once `main`
   matches it (`git diff main..integrate-prs` empty). Report any
   commit left behind instead of force-pushing.
4. Update `docs/TASKS.md` and `docs/ROADMAP.md` to reality: B1–B3
   closed, B4 status per W1, in-house core stages 1–9 done,
   remaining work = this plan's W1–W8 with issue links.
5. Reconcile issue checkboxes with reality (notably #4, #32):
   tick only items backed by committed evidence; leave the rest.

Acceptance: `origin/main` tip includes #50; full gates green on
`main`; TASKS/ROADMAP no longer contradict `README.md`.

### W1 — Close B4: on-core crypto proof incl. Ed25519 (issue #4)

Depends on: W0 (SoC + caches on `main`). Unblocks: W6 (benchmark
accelerator path), W7 (SoC closure input), W8/F5 crypto step.

Current gap: `sw/soc-tests/crypto_soc_test.c` covers SHA-256,
field mul, `2*G`, and secp256k1 ECDSA verify on the RTL SoC.
Ed25519 verify on-core is missing; issue #4 requires both curves.

1. Extend `sw/soc-tests/crypto_soc_test.c` (or a sibling test) with
   Ed25519 verify of the RFC 8032 vectors already used by
   `sw/ec_ops.py`, driving field ops through the accelerator at
   `0x2000_0000` (Curve25519 `p`, `MODSEL=1`; register map in
   `docs/SPEC.md`, driver constants in `sw/sigil_crypto.h`).
   Include a tampered-signature reject case, mirroring the
   existing secp256k1 tamper check. Note: Ed25519 needs SHA-512;
   until W3 lands, compute the hash in software on-core or use
   precomputed digests from `sw/ec_ops.py` — state which in the
   test header. Do not silently fake the hash step.
2. Run on the RTL SoC: `make -C sim socrtl` (see `sim/Makefile`
   for the firmware build; `tb/cpp/soc_rtl_tb.cpp` is the
   harness). Expect `SOC CRYPTO PASS` / `SOC RTL TB PASS`.
   Record cycle count. Also run cached and uncached
   (`--no-cache`) configurations.
3. Commit a dated log under `docs/evidence/`, add its section to
   `docs/evidence/README.md`, tick issue #4's boxes, close #4.

Acceptance: a C program on the in-house core in the RTL SoC
verifies Ed25519 + secp256k1 via the accelerator; tampered
inputs reject; log committed; #4 closed. This is a functional
proof only — the firmware field sequences are not constant-time
(that is W2/W4).

### W2 — Hardware scalar-multiply sequencer (issue #5)

Depends on: W1 (driver path proven). Related: W4 must audit this
before any key use.

Goal: move Ed25519/secp256k1 point ops from `sw/ec_ops.py`
firmware sequences into a constant-time hardware sequencer over
`rtl/crypto/ec_field.sv`.

1. Design first, in the PR description: FSM/micro-sequencer
   issuing field add/sub/mul; Montgomery ladder for Curve25519;
   fixed-schedule ladder for secp256k1; inversion by fixed
   addition chain. Hard rules: no secret-dependent branches, no
   secret-indexed tables, fixed memory-access pattern, constant
   cycle count for every scalar.
2. RTL in `rtl/crypto/` + engine hookup in
   `rtl/crypto/sigil_crypto_top.sv` (new engine select / registers;
   update `docs/SPEC.md` register map + `sw/sigil_crypto.h` in
   the same change).
3. Testbenches in `tb/cpp/`: RFC 8032 vectors + Wycheproof-style
   ECDSA vectors (same frozen vectors as `sw/ec_ops.py`); a
   constant-time check that asserts identical cycle counts
   across scalars (all-zero, all-one, random, edge values).
4. Re-run `make test`, `make lint` (both Verilators), and the
   W1 SoC test against the new engine.

Acceptance: RTL sign/verify paths pass the `sw/ec_ops.py`
vectors in simulation; cycle-count independence asserted in TB;
issue #5 closed with evidence. Still no production keys (W4).

### W3 — Streaming SHA-512 + Keccak/SHA3 (issue #6)

Depends on: W0. Independent of W2. Unblocks: full on-core
Ed25519 hashing without the W1 workaround; W6 completeness.

Current gap: `rtl/crypto/sigil_crypto_top.sv` exposes only
SHA-256 (one 512-bit block) + field ops. `sha512_block.sv` and
`keccak_f1600.sv` are verified standalone only; engine select 1
is reserved. Software cannot hash arbitrary-length messages
through the accelerator.

1. Add SHA-512 engine select (1024-bit block registers or a
   streaming FIFO — choose FIFO streaming if DMA is in scope,
   block registers if not; record the choice in `docs/SPEC.md`).
2. Add Keccak sponge wrapper around `keccak_f1600.sv` (rate 1088;
   SHA3-256 + Keccak-256; multi-block absorb/squeeze).
3. Add DMA or FIFO streaming so software is not limited to one
   block per MMIO burst. Keep the AXI-Lite register interface
   backward-compatible for existing SHA-256/field users.
4. Multi-block KATs vs `hashlib` (SHA-512, SHA3-256, Keccak-256)
   in `tb/cpp/`, plus boundary lengths (0, rate-1, rate, rate+1,
   multi-rate). Update `sw/sigil_crypto.h` + `docs/SPEC.md`.
5. Re-run W1 SoC test; optionally switch its Ed25519 step to
   accelerator SHA-512 and note the change in evidence.

Acceptance: arbitrary-length hashing from software passes KATs
in RTL simulation for all three digests; issue #6 closed.

### W4 — Security review before any key handling (issue #12)

Depends on: W2 design exists (audit the real sequencer, not a
sketch). Gates: any key storage/use, any "hardened" claim.

1. Constant-time audit of the W2 sequencer + `ec_field` usage:
   enumerate every secret-dependent path; verify fixed access
   patterns and absence of secret-indexed tables by RTL
   inspection + the W2 cycle-count TB.
2. Fault-injection review for signature verify: decide
   double-check vs infective countermeasure; file follow-up
   issues for anything not fixed in this package.
3. Document key-storage/TRNG requirements as requirements only
   (building them is out of scope here).
4. Write the review as a dated doc under `docs/`; link it from
   `README.md` and `docs/SPEC.md`. Remove the Phase-0 warning
   only for the exact scope the review actually covers.

Acceptance: written review in `docs/` with findings filed as
follow-up issues; issue #12 closed. Anything less keeps the
"not side-channel-hardened" boundary in force.

### W5 — Verification hardening: riscv-dv + follow-ups (#8, #20)

Depends on: W0. Can run parallel to W1–W4 and W6–W8.

1. riscv-dv random-instruction regression vs Spike for the
   in-house core config (issue #8): pin tool versions, seed
   strategy, and mismatch-triage flow; start as nightly/manual
   CI, promote to required check only when stable. File every
   real mismatch as its own issue with a minimized reproducer;
   do not waive silently.
2. Enable branch protection on `main` with the stable checks
   required (issue #8 acceptance: failures block merges).
3. Issue #20 leftovers, each with stored evidence before any
   wider compliance claim: TestFloat level-2 density for
   `mulAdd` (`roundToInt` stays unclaimed without Zfa); ACT
   `Zalrsc-sc` case-level probe (directed LR/SC passes; the ACT
   harness case hangs — find which side is wrong). Sv48: only
   if a future config enables it; otherwise leave unclaimed.
4. Keep `docs/COMPLIANCE.md` honest: update rows only with the
   evidence file that proves them.

Acceptance: riscv-dv runs in CI with logs; branch protection
on; #20 items either evidenced or explicitly left unclaimed.

### W6 — Benchmark: scalar vs vector vs accelerator (issue #10)

Depends on: W1 (accelerator driver). Scalar/vector legs need
only W0. Do after W3 if Keccak/SHA-512 numbers are wanted too.

1. Scalar SHA-256 chain benchmark on the in-house core
   (bare-metal, `sw/` + core/SoC harness; cycles from CSR
   counters, not wall time).
2. RVV multi-buffer SHA-256 on the in-house vector unit
   (VLEN 512; note the element-serial cost model in
   `docs/CORE.md` — report cycles/hash honestly, including if
   vector loses).
3. Accelerator SHA-256 chain via the W1 driver.
4. Publish cycles/hash + hashes/sec at stated clocks in a doc
   under `docs/` with the exact configs and binaries named.

Acceptance: three reproducible numbers with method + configs;
issue #10 closed. No extrapolation to clocks not measured.

### W7 — Physical: full-SoC OpenROAD + MPW decision (#11, #13)

Depends on: W0, W1. Owner decision needed first (Open
questions): sky130 cache size / fit strategy.

Starting point: synthesis only (`docs/SOC_AREA.md`). Known
blockers, in order:

1. RTL prep: register SRAM macro outputs (VRF first, then all
   15) to break OpenRAM half-cycle paths — costs +1 cycle on
   VRF reads and cache hits; re-run full gates + `srammacro`
   (`make core-test` includes it) and re-measure fmax. Add the
   missing reset synchronizer in `sigil_soc_top` (flagged in
   `docs/SOC_AREA.md`). Confirm the OpenRAM hold-time signoff
   assumption with macro characterization or timed gate-level
   sim (`vendor_model_check.sh` documents the gap).
2. Apply the owner's cache/config decision for sky130
   (parameters on `sigil_cpu`: `IC_SETS/WAYS`, `DC_SETS/WAYS`
   — see `docs/CORE.md`). Re-run synthesis for the chosen
   config before P&R.
3. Hierarchical ORFS flow: hardened `sigil_crypto` macro + core
   subsystem (`flow/designs/sky130hd/sigil_soc/`,
   `scripts/openroad_docker.sh`). Clock/reset strategy, IO
   plan. Iterate floorplan → place → CTS → route to timing /
   DRC / antenna clean. Record die area honestly at each step.
4. Caravel go/no-go with real placed numbers (issue #13):
   if RV64GCV+crypto still exceeds the user area, the recorded
   fallback is crypto macro + RV64GC host, vector deferred to
   FPGA/ASIC-v2. Wrapper, padring, DFT/scan decision only
   after a "go".
5. Final DRC/LVS/antenna-clean GDS + efabless precheck +
   shuttle checklist/costs, all dated under `docs/evidence/`.

Acceptance: #11 closes with SoC-level timing/DRC reports +
GDS; #13 closes with a dated go/no-go backed by those reports.
"Place-and-route complete" never means taped out.

### W8 — FPGA: AWS EC2 F2 bring-up (issue #32, `docs/FPGA_F2.md`)

Depends on: W0. F1/F2 are partly done by the PR stack
(synthesizable SoC, L1 caches, multi-cycle FPU/M, element-
serial vector). Owner decisions needed before F4: AWS region
+ F2-hours budget cap. Vivado is Linux-AMI only (not macOS).

Execute `docs/FPGA_F2.md` stages in order; do not skip:

1. F0 (no F2 spend): Vivado out-of-context synthesis of core +
   crypto for VU47P @ 100 MHz on a Developer-AMI compute
   instance. File LUT/FF/DSP/BRAM/WNS + top critical paths in
   `docs/evidence/`. Gate: elaborates; real numbers recorded.
2. F1: confirm the RTL SoC (`rtl/soc/`, same memory map/DTS as
   `soc_tb`) boots bare-metal directed tests in Verilator via
   `soc_rtl_tb`. FPGA-specific top only if the SoC top cannot
   serve (BRAM RAM wrapper behind the memory bus).
3. F2: timing closure ≥ 100 MHz post-route in Vivado, driven
   by F0 paths. Re-run riscv-tests/ACT/unit TBs after every
   RTL refactor. Any interim "lite" bitstream must be labelled
   with its exact config; the Linux claim needs the full
   verified config or an explicit label otherwise.
4. F3: AWS CL wrapper (pin aws-fpga HDK commit + shell version
   in `docs/FPGA_F2.md` when chosen): 100 MHz core clock, OCL
   AXI-Lite control + virtual-UART FIFOs, Shell DDR4 ≥ 128 MiB,
   host loader for OpenSBI/Image/DTB, free-running cycle
   counter readable over OCL to *measure* runtime clock.
5. F4: DCP on compute AMI → S3 → `create-fpga-image` → run on
   `f2.6xlarge`. Stop/terminate the instance in the same
   workflow; list live instances before claiming anything is
   running; never leave F2 idle.
6. F5 evidence, in order, each a dated log: bare-metal hello +
   directed tests + benchmark cycle counts; crypto KATs via
   the SoC accelerator; OpenSBI + Linux to
   `SIGIL_LINUX_BOOT_OK`; static user binary marker.

Acceptance: issue #32 closes with AFI id, HDK/shell versions,
Vivado timing summary, measured (not inferred) ≥ 100 MHz
runtime clock, and host UART captures for each F5 step.

## Explicitly not in scope / not claimed

Do not implement or claim any of these unless the owner opens
a new issue for it:

- Full V beyond Zve32x/64x + Zve32f/64f/64d; FP16 (`Zvfh`);
  the 43 ACT vector tests Sail/ACT did not generate.
- Sv48, Zfa, Zicbo, Svadu, Svinval, Svpbmt, misaligned-access
  emulation (core traps; `Zicclsm` not claimed).
- SMP/multi-hart, block/network devices, distro Linux, guest-OS
  boot under KVM (current KVM result is an MMIO-exit smoke).
- IPC/performance work (prefetch, store buffer, pipelined
  cache hits — listed as ideas in `docs/CORE.md` only).
- Key storage, TRNG, secure boot (W4 documents requirements).
- Tape-out, fabrication, or silicon claims of any kind.

## Validation plan (standard gate set)

Run from the repo root after `source deps/env.sh`. Long
commands: background + log under `build/` (see How to use).

| Gate | Command | Expected |
|---|---|---|
| Crypto KATs | `make test` | `ALL PHASE-0 KATs PASS` |
| Lint (local) | `make lint` | clean (Verilator 5.048) |
| Lint (CI parity) | Docker command in `AGENTS.md` | clean (5.020) |
| Core unit + directed | `make core-test` | all PASS, incl. `srammacro` |
| riscv-tests | `make riscv-tests` (or `bash sim/run_riscv_tests.sh`) | 123/123 |
| ACT (core) | `bash scripts/build_act4_core.sh` then `bash sim/run_act_core_par.sh` | 2577/2578, only the PA0 waiver |
| RTL SoC crypto | `make -C sim socrtl` | `SOC CRYPTO PASS`, `SOC RTL TB PASS` |
| Linux boot (long, not per-commit) | commands in `sw/linux/README.md` | `SIGIL_LINUX_BOOT_OK`, ~509M cycles |

Package-specific gates are stated inside W2–W8. The
highest-risk validation step in this plan is the ACT re-run
after W7.1 (registered SRAM outputs change cache/VRF timing):
treat any new ACT failure there as a real regression, not a
waiver candidate, until root-caused.

## Risks and open questions

Risks:

- PR-stack bit-rot: the longer #33–#50 stay unmerged, the more
  W0 rebases cost. Mitigation: W0 before any new RTL work.
- Sky130 fmax/area may still miss after W7.1–W7.2 (unrepaired
  numbers are fanout-dominated; placed results will differ).
  Mitigation: decide go/no-go on placed data, keep the
  RV64GC+crypto fallback real.
- riscv-dv (W5) will likely find real core bugs. That is its
  purpose; budget triage time, do not gate other tracks on a
  fully clean random regression.
- F2 cost/region availability (W8): builds on compute AMIs,
  F2 only for load/test, always stopped in-workflow.

Open questions (owner must answer; defaults assumed above):

1. Sky130 fit strategy for W7: shrink L1 to 4 KiB + 4 KiB
   (assumed default), denser SRAM/DFFRAM, fewer VRF replicas,
   or RV64GC-without-V for MPW?
2. W8 before F4: AWS region and F2-hours budget cap?
3. Track priority after W0+W1: crypto (W2–W4), physical (W7),
   or FPGA (W8) first? This plan is executable in any order
   after W1; it does not choose for the owner.

## Appendix — starter prompt for the next agent

Copy-paste, filling in the package:

> You are working in the Sigil repo. Read
> `docs/REMAINING-WORK-PLAN.md` first, then `AGENTS.md`, then
> the GitHub issue for work package W__ (§___). Confirm W0 is
> done (`main` includes PR #50) or stop and report. Work in
> your own git worktree/branch via `scripts/worktree_setup.sh`;
> `source deps/env.sh` in every shell; run long commands in
> the background logging to `build/`. Implement only that
> package, run its stated gates plus the standard gate set,
> commit dated evidence under `docs/evidence/`, and update
> the docs named in the package. Do not widen any claim in
> `README.md`/`docs/COMPLIANCE.md` without a reproducing gate.
> Do not commit/push/open a PR unless I ask. Report: what
> changed, gate results with wall-clock times, evidence paths,
> and anything left unverified.
