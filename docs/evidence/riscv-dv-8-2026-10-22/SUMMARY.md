# #8 riscv-dv random regression vs Spike: summary (2026-10-22)

Branch `8-riscv-dv`, not merged; code head `1eac727` (the commits after it are documentation and evidence). Ready-to-merge report: [`final/merge-ready.txt`](final/merge-ready.txt).
Flow, configuration and rules: [`docs/VERIFICATION.md`](../../VERIFICATION.md).
Index entries: [`../README.md`](../README.md), the "#8" sections.

For each (test, seed) a program comes from riscv-dv's Python generator
(18 tests) or from one of four seeded random directed programs; it runs
on Spike and on the Verilated core, and the two retire traces are
compared record by record (pc, instruction bits, privilege, integer, FP
and vector register writes, CSR writes, stores, every trap and
interrupt with cause/epc/tval, and the `tohost` exit).

## Versions

| Item | Version |
|---|---|
| Host | sigil-verify, AWS c7i.8xlarge (32 vCPU, 61 GiB), Ubuntu 24.04.5, shared with the perf-harness workflow (16 jobs or fewer) |
| Spike | riscv-isa-sim `2c300cd90eb74bb79f3fcdd58596a6f8d842d01c` (1.1.1-dev), built by [`scripts/build_spike.sh`](../../../scripts/build_spike.sh); `--isa=rv64imafdcbvh_zicsr_zifencei_zicntr_zbc_zbkb_zbkc_zbkx_zkne_zknd_zknh_zicond_zcb_zvl512b_svnapot_svadu --priv=msu --triggers=0 --pmpregions=16 --pmpgranularity=4 --wfi-as-nop` (`_svadu` since `a36305c`) |
| riscv-dv | chipsalliance/riscv-dv `0d71c2b666dec48dde0b804a2138426da56aa252`, Python generator with patches A-AE ([`pygen-sigil.patch`](../../../sim/riscv-dv/patches/pygen-sigil.patch)) |
| Python | 3.12.3; pyvsc 0.9.1.10086043874, pyboolector 3.2.4.20240823.1, pyucis 0.1.3.7162246580 |
| Toolchain | riscv64-unknown-elf GCC 16.1.0 (`g6afcc4f6d`), binutils 2.47 (`deps/`; CI: riscv-collab `2026.08.27`, the same release) |
| DUT simulator | Verilator 5.048 (`deps/`); CI and the CI replays: Ubuntu apt Verilator 5.020 |

## Rounds

Records = reference records compared, equal to the core's in every PASS.
The directed programs are `sigil_bitmanip_crypto_test` and
`sigil_vector_test`, and from `a36305c`/`c73c4a6` also
`sigil_priv_test` and `sigil_hint_test`.

| # | Round | Commit (RTL) | Tests x seeds | Runs | Result | Records | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | builder | `384d813` | 20 x 1-3 | 60 | 60 PASS | 680,586 | [`results-full-seeds1-3.csv`](results-full-seeds1-3.csv) |
| 2 | builder, `make -C sim riscv-dv` | `661c046` | 20 x 4-6 | 60 | 60 PASS | 673,480 | [`results-full-seeds4-6.csv`](results-full-seeds4-6.csv) |
| 3 | round 1 | `b86bc8d` | 20 x 100000-100009 | 200 | 196 PASS, 4 GEN_FAIL | 2,231,764 with the 4 regenerated alone | [`rounds/round1-SUMMARY.txt`](rounds/round1-SUMMARY.txt) |
| 4 | round 1 command with the generator memory budget | `d02176b` | 20 x 100000-100009 | 200 | 200 PASS | 2,231,764 | [`pygen-amo-oom/full-regression.txt`](pygen-amo-oom/full-regression.txt) |
| 5 | round 2 | `84974af` | 20 x 200000-200024 | 500 | 500 PASS | 5,487,995 | [`rounds/round2-SUMMARY.txt`](rounds/round2-SUMMARY.txt) |
| 6 | round 3 | `84974af` | 20 x 300000-300039 | 800 | 800 PASS | 8,814,169 | [`rounds/round3-SUMMARY.txt`](rounds/round3-SUMMARY.txt) |
| 7 | review: random RVV program, RTL before its fixes | `84974af` + program | 1 x 1-8 | 8 | 8 MISMATCH (root causes 2, 3) | - | [`critic/core-findings.txt`](critic/core-findings.txt) |
| 8 | review: core fixed, old trace probe | `63a50a5` | 1 x 1-16 | 16 | 16 MISMATCH (root cause 4) | - | [`critic/trace-snapshot.txt`](critic/trace-snapshot.txt) |
| 9 | review: core and probe fixed | `862868c` | 1 x 1-16 | 16 | 16 PASS | 1,313,691 | [`critic/core-findings.txt`](critic/core-findings.txt) |
| 10 | review: misaligned accesses resume (patch AE), old Spike budget | `e7a82fe` + AE | 3 x 1-8 | 24 | 16 PASS, 8 SPIKE_FAIL (root cause 5) | - | [`critic/unaligned-and-spike-budget.txt`](critic/unaligned-and-spike-budget.txt) |
| 11 | review: per-test Spike budget | `a397c78` | 2 x 1-8 | 16 | 16 PASS | 2,272,523 | same |
| 12 | review: full list | `34ddf8e` | 20 x 1-5 | 100 | 100 PASS | 2,535,412 | [`critic/full-regression.txt`](critic/full-regression.txt) section 1 |
| 13 | review: directed programs | `ef27681` | 2 x 6-205 | 400 | 400 PASS | 21,417,310 | section 2 |
| 14 | review: full list | `e1c4338` | 20 x 1-5 | 100 | 100 PASS, same records and cycles as 12 | 2,535,412 | section 3 |
| 15 | CI replay, apt Verilator 5.020, 4 jobs | `e1c4338` | 20 x 1 | 20 | 20 PASS | 523,511 | [`critic/ci-replay.txt`](critic/ci-replay.txt) |
| 16 | after merging `main` (MMU walker-race fix #74, Svadu atomicity) | `adf4c97` | 20 x 1-5 | 100 | 100 PASS, same records and cycles as 14 | 2,535,412 | section 4 |
| 17 | CI replay, apt Verilator 5.020, 4 jobs | `adf4c97` | 20 x 1 | 20 | 20 PASS, same records and cycles as 15 | 523,511 | [`critic/ci-replay.txt`](critic/ci-replay.txt) |
| 18 | review: random privileged program, RTL before the PMP fix | `c98428b` program, `adf4c97` RTL | 1 x 1-8 | 8 | 3 PASS, 5 MISMATCH (root cause 7) | - | [`critic/pmp-partial-match.txt`](critic/pmp-partial-match.txt) |
| 19 | review: full list with the PMP fix and the privileged program | `c98428b` | 21 x 1-5 | 105 | 105 PASS; the 100 earlier runs with the same records and cycles as 16 | 3,100,449 | section 5 |
| 20 | review: the four directed programs on the final RTL | `37aa1d7` | 4 x 1-205 | 820 | 820 PASS | 97,111,729 | section 6 |
| 21 | merge-ready: whole list (18 generated + 12 directed) | `1eac727` | 30 x 1-3 | 90 | 90 PASS | 15,914,152 | [`final/rdv/rdv-final.txt`](final/rdv/rdv-final.txt) |
| 22 | merge-ready: the vector programs | `1eac727` | 7 x 4-16 | 91 | 91 PASS | 38,523,708 | same |
| 23 | merge-ready: the PMP and privileged programs | `1eac727` | 3 x 4-12 | 27 | 27 PASS | 15,402,522 | same |

Rows 1-20: 3,573 runs and 153,988,718 compared records (rows 3 and 4
count round 1's records twice, once per run). Rows 21-23, on the final
RTL with the review-round fixes: 208/208 PASS, 69,840,382 records; the
reviews' own runs (branches `8-dvfix-*`) are in
[`critic/viota-review.txt`](critic/viota-review.txt) and
[`pmp-review/pmp-review.txt`](pmp-review/pmp-review.txt). The 41 runs that did not
pass (4 GEN_FAIL, 8 SPIKE_FAIL, 29 MISMATCH) are all explained by the
root causes below; every round on a commit after the matching fix
passed. On the final RTL (`c98428b`, equal to `37aa1d7` in `rtl/`):
105/105 for the whole list as it stood then (21 tests) and 820/820 for
the four directed programs, `sigil_hint_test` included. In round 20 `sigil_priv_test` took 67,826 traps (17,212 of
them S-level interrupts, 12,209 page faults, 1,060 access faults, 5,216
illegal instructions, 31,320 ECALLs) and the RVV program ran 4,920
iterations over all 22 legal SEW/LMUL pairs.

## Root causes and what was done

Every non-PASS above has one of these causes. All were found and fixed
or waived on this branch and are recorded in #8. The core bugs also have
their own issues (open until the fix ships): #76 (`viota.m` and the `vstart`=0 class: root causes 2, 9, 10), #77 (vector FP: root causes 3, 11), #78 (PMP: root causes 7, 12).

| # | Root cause | Kind | Disposition | Evidence |
|---|---|---|---|---|
| 1 | `pygen-amo-oom-parallel-gen`: ten `riscv_amo_test` generations (8-9.7 GiB each) at once; the kernel OOM killer stopped four (`GEN_FAIL`, `pygen rc=-9`) | harness | fixed: generations run under a memory budget (`9e64bc3`, `d02176b`), amo estimate 10 GiB (`ef27681`); the four programs regenerated alone pass | [`pygen-amo-oom/`](pygen-amo-oom/) |
| 2 | `viota.m` raised illegal instruction when its mask register vs2 was not aligned to LMUL | core | fixed in `63a50a5`; `vec_directed` test 25 | [`critic/core-findings.txt`](critic/core-findings.txt) |
| 3 | `vfmv.v.f`, `vfmv.s.f`, `vfmerge.vfm`, `vfslide1up/down.vf` at SEW=32 used the low half of a non-NaN-boxed f register instead of the canonical NaN | core | fixed in `63a50a5`; `fpvec_directed` test 11 | same |
| 4 | the retire trace logged vector registers after a younger vector load had overwritten them | trace probe (simulation only) | fixed in `862868c`, `e1c4338` | [`critic/trace-snapshot.txt`](critic/trace-snapshot.txt) |
| 5 | Spike charges its `--instructions` budget up to 5,000 per trap | harness | per-test `spike_max_instr` (`a397c78`) | [`critic/unaligned-and-spike-budget.txt`](critic/unaligned-and-spike-budget.txt) |
| 6 | a vector register write logged by one side only was not compared | comparator | it must now leave the register unchanged (`34ddf8e`) | [`critic/comparator-selfcheck-v2.log`](critic/comparator-selfcheck-v2.log) |
| 7 | PMP decided an 8-byte access by its first 4-byte word only: an NA4 entry or a TOR boundary splitting it did not fail it (in M-mode it always passed) | core | fixed in `3ae351d`; new core test `pmp_partial_directed`; `vec_trap_directed` test 11 relied on the old behaviour and was corrected (`37aa1d7`) | [`critic/pmp-partial-match.txt`](critic/pmp-partial-match.txt) |
| 8 | Spike's CLINT raises MTIP after reset (mtimecmp = 0); `core_tb` has no CLINT | platform | `sigil_priv_test` sets mtimecmp to the maximum | [`critic/priv/program-bringup.txt`](critic/priv/program-bringup.txt) |
| 9 | `vstart` != 0 did not make `viota.m`, `vcpop.m`, `vfirst.m`, `vmsbf/vmsif/vmsof.m`, `vcompress.vm` or the reductions illegal (older than `63a50a5`; found by the `viota.m` review, the programs never write `vstart`) | core | fixed in `fd22878` (with an EX hold behind a vector load/store that consumes `vstart`); `vstart_illegal_directed`, `viota_vstart_directed`, `sigil_viota_vstart_test` | [`critic/viota-review.txt`](critic/viota-review.txt), [`final/mutation/mutation.txt`](final/mutation/mutation.txt) |
| 10 | `viota.m` with vs2 inside the vd group (reserved): Spike traps, Sigil ran it (since `63a50a5` in every case) | core, reserved encoding | trapped as on Spike since `913bc0a`; `viota_overlap_directed`, `sigil_viota_overlap_test` | same |
| 11 | the int16 <-> f32 conversions (`vfwcvt.f.x(u).v`, `vfncvt.(rtz.)x(u).f.w`) trapped at SEW=16, where Zve32f defines them (older than `63a50a5`; found by the `.vf` review) | core | fixed in `1eac727`; `vfcvt_sew16_directed`, `sigil_vfcvt_sew16_test` | [`final/mutation/mutation.txt`](final/mutation/mutation.txt) |
| 12 | `vl<n>re64.v` elements were PMP-checked byte by byte: a split element did not fault in M, and S/U reported the first failing byte as `mtval` (Spike and Sail: one 8-byte access per element) | core | fixed in `9bdd552`; `pmp_whole64_directed`, `sigil_pmp_whole64_test`; `vec_trap_directed` test 13 corrected | [`pmp-review/pmp-review.txt`](pmp-review/pmp-review.txt) |
| 13 | Spike prints a commit line for a vector load that faults after writing elements; the DUT logs only the trap | comparator | that line is dropped, the partial contents are compared at the next read (`01995ef`) | same |

Waived (implementation-defined, kept out of the comparison or the programs):

| Behaviour | How |
|---|---|
| which exceptions `medeleg` can delegate (Sigil keeps access faults in M, Spike delegates them) | `sigil_priv_test` draws only bits both delegate ([`program-bringup.txt`](critic/priv/program-bringup.txt)) |
| `mideleg` bit 12 (SGEIP) with GEILEN = 0: Spike reads one, Sigil zero | comparator: `CSR_IMPL_DEFINED = {0x303: 1 << 12}`, that bit only |
| LR and SC of different widths (extent of the reservation set) | patch R pairs the widths ([`lrsc-width-mismatch-compare.txt`](lrsc-width-mismatch-compare.txt)) |
| RVV: fractional LMUL with SEW > LMUL*ELEN, vl for AVL in (VLMAX, 2*VLMAX), unordered reductions and stores, `vstart` != 0 on arithmetic | `sigil_vector_test` stays clear of them |
| speculative A-bit updates, priority of misaligned vs page/access faults, a failing SC to a no-write page, imprecise FS dirtying, WFI in U, ASIDLEN, mixed Svnapot groups | `sigil_priv_test` stays clear of them |
| free-running counters (cycle, time, instret) | not in the generator's CSR list |
| an invalid `frm` (5-7): Spike traps every vector FP instruction, Sigil only the rounding ones (reserved by RVV 1.0 `norm:V_inv_frm_rsv`) | the programs keep `frm` in 0-4 |

## Follow-up: review of the `viota.m` fix (root cause 2)

Branch `8-dvfix-viota`, RTL `65a48ae` (fixed) and the same with the
`viota.m` hunk of `63a50a5` reverted
([`critic/viota-review.txt`](critic/viota-review.txt)):

- `sigil_viota_sweep_test` (all 1,408 combinations of the 22 legal
  vtypes, tu/ta, mu/ma, unmasked/`v0.t`, 8 AVL classes; vs2 mostly an
  odd register) and `sigil_viota_test`, seeds 1-16 each: 32/32 PASS
  ([`critic/viota-flow-results-seeds1-16.csv`](critic/viota-flow-results-seeds1-16.csv));
  the 16 sweep chunks also MATCH through Spike + `core_tb` +
  `rdv_trace.py` directly, and every chunk fails on the reverted RTL.
- Core tests: `viota_sweep_directed` (all 1,408), `viota_directed` and
  `viota_cases_directed` (hand-computed results, Spike-checked) pass with
  random bus timing, uncached and with VRF_OREG; on the reverted RTL
  they fail.
- Found there, older than the fix (the programs never write `vstart`):
  `vstart` != 0 did not make `viota.m`, `vcpop.m`, `vfirst.m`,
  `vmsbf/vmsif/vmsof.m`, `vcompress.vm` or the reductions illegal, as
  RVV 1.0 requires and Spike does (root cause 9, fixed in `fd22878`);
  `viota.m` with vs2 inside the vd group, reserved, ran on Sigil and
  trapped on Spike (root cause 10, trapped since `913bc0a`). The tests
  are in the suite now.

## Follow-up: review of the `.vf` NaN-box fix (root cause 3)

Branch `8-dvfix-nanbox`, RTL `65a48ae`: `fpvec_nanbox_directed` (tests
1-24, every `.vf` class) passes on Spike and on the core (default,
random bus, uncached, and the xinit/oreg/vrforeg/fakeram45/sky130/
mdcomb/ds1 builds) and fails at test 1 with the check reverted;
`sigil_vf_nanbox_test` seeds 1-48 PASS on the default `core_tb` and
49-54 on the SRAM_OREG and VRF_OREG builds (about 178,000 records
each).
`vfmv.s.f` is meant to unbox (the rule covers every f-register scalar),
and does. Found: the int16 <-> f32 conversions at SEW=16 (root cause
11, fixed in `1eac727`); an invalid `frm` (waived above).

## Follow-up: review of the PMP fix (root cause 7)

Branch `8-dvfix-pmp`, RTL `f239397`
([`pmp-review/pmp-review.txt`](pmp-review/pmp-review.txt)):
`sigil_pmp_test` (every access kind in M, M+MPRV, S, U; locked
entries) seeds 1-60 PASS, 12/12 MISMATCH before `3ae351d`;
`pmp_modes_directed` passes on Spike, Sail and the core; the PMP forms
are proven by SAT. Found: whole-register loads with EEW=64 (root cause
12, fixed in `9bdd552`), and the place on `53-100mhz-afi` where the fix
must be ported for FPGA_TIMING (section 6 there; exact lines in
[`final/merge-ready.txt`](final/merge-ready.txt)).

## Not covered (docs/VERIFICATION.md "Limits")

- Interrupts from devices at a given time (`riscv_full_interrupt_test`):
  that needs a lockstep flow; only interrupts made pending by `mip`
  writes are compared.
- The H extension, debug mode, random CSR accesses (`riscv_csr_test`),
  sub-programs (`riscv_rand_jump_test`), locked PMP entries and MPRV;
  randomly generated instruction streams under address translation
  (the pygen tests run with satp Bare; translation is covered by the
  directed `sigil_priv_test`).
- Load addresses and implicit CSR updates are not in the retire trace;
  they are compared where the programs read them back.

## CI

[`.github/workflows/riscv-dv.yml`](../../../.github/workflows/riscv-dv.yml):
`workflow_dispatch` (tests, seeds, instruction count) and nightly
(03:41 UTC, every test with seed 1 and seed 1000 + run number); never on
push or pull_request, not a required check. It builds the pinned Spike
(cached by the build script's hash), the pinned riscv-dv clone and venv
(cached), uses the pinned GCC of `compliance.yml` (cached) and apt
Verilator 5.020, and uploads `results.csv`, the log and every failing
run's directory. It cannot be dispatched before it is on `main`; its
steps were replayed twice on sigil-verify from a fresh clone (rounds 15
and 17).

## Gates

Final, on RTL `1eac727` (the commits after it change only documentation
and evidence), logs in [`final/`](final/); the report is
[`final/merge-ready.txt`](final/merge-ready.txt):

| Gate | Where | Result |
|---|---|---|
| `make lint`, Verilator 5.044 | Mac (macOS 26.6.2) | rc=0, no warning ([`lint-5.044.log`](final/gates/lint-5.044.log)) |
| `make lint`, Verilator 5.048 (`deps/`) | sigil-fpga-build | rc=0, no warning ([`lint-5.048.log`](final/gates/lint-5.048.log)) |
| `make lint`, Verilator 5.020 (Ubuntu apt) | sigil-fpga-build | rc=0, no warning ([`lint-5.020.log`](final/gates/lint-5.020.log)) |
| `make test` | sigil-fpga-build | rc=0, ALL PHASE-0 KATs PASS ([`test.log`](final/gates/test.log)) |
| `make core-test` | sigil-fpga-build, VJOBS=6, 2,714 s | rc=0, 333 "TB PASS" lines (main's 293 plus the branch's ten directed tests in four memory configurations each), 0 FAIL ([`core-test.log`](final/gates/core-test.log)) |
| `make riscv-tests` | sigil-fpga-build | rc=0, 123/123 PASS ([`riscv-tests.log`](final/gates/riscv-tests.log)) |
| Full ACT, 2,578 ELFs (`sim/run_act_core_par.sh`, core_tb default config, Verilator 5.048) | sigil-verify, 12 jobs, 301 s | 2,577/2,578; only the `PMPSm_cfg_A_tor_zero-00` PA0 waiver fails (18,024 cycles). Every ELF has the same verdict and cycle count as main `9da0006` and as `65a48ae` on the same ELFs and machine ([`act-final.log`](final/act/act-final.log), [`act-full-8-riscv-dv-1eac727.csv`](final/act/act-full-8-riscv-dv-1eac727.csv)) |
| riscv-dv vs Spike | sigil-verify, 12 jobs | 208/208 PASS, 69,840,382 records (rows 21-23 above) |
| Synthesized logic vs `f239397` and main (Verilator -E, sv2v, Yosys equivalence) | Mac | only `sigil_core` and `sigil_vec` change since `f239397`, at the new fixes' signals (`vec_illegal`, `vec_ex_stall`, `ex_fp_bad`, `pmp_wide_b_i`; the vector unit's FPU operand and FP result); with the new fixes reverted both are proven equivalent to `f239397`'s in the five define sets ([`synth-equiv-round2.log`](final/synth/synth-equiv-round2.log)) |
| Linux RTL boot (`soc_rtl_tb`, release `Image-initramfs`) | sigil-fpga-build | `SIGIL_LINUX_BOOT_OK` at 261,247,447 cycles, UART log identical to main's (890 lines) ([`linux-boot.txt`](final/linux-boot.txt)) |
| New tests on Spike; one mutant per part of each new fix | sigil-verify | pass on Spike and on the core; every mutant fails its test ([`mutation.txt`](final/mutation/mutation.txt)) |

Earlier, on `37aa1d7` (before the review round), logs in
[`critic/gates/`](critic/gates/):

| Gate | Where | Result |
|---|---|---|
| `make lint`, Verilator 5.044 | Mac (macOS 26.6.2) | rc=0, no warning ([`lint-5.044.log`](critic/gates/lint-5.044.log)) |
| `make lint`, Verilator 5.048 (`deps/`) | sigil-verify | rc=0, no warning ([`lint-5.048.log`](critic/gates/lint-5.048.log)) |
| `make lint`, Verilator 5.020 (Ubuntu apt) | sigil-verify | rc=0, no warning ([`lint-5.020.log`](critic/gates/lint-5.020.log)) |
| `make test` | sigil-verify | rc=0, ALL PHASE-0 KATs PASS ([`test.log`](critic/gates/test.log)) |
| `make core-test` | sigil-verify, VJOBS=4, 2,609 s | rc=0, 297 "TB PASS" lines (main's 293 plus `pmp_partial_directed` in four memory configurations), 0 FAIL ([`core-test.log`](critic/gates/core-test.log)) |
| `make riscv-tests` | sigil-verify | rc=0, 123/123 PASS ([`riscv-tests.log`](critic/gates/riscv-tests.log)) |
| Full ACT, 2,578 ELFs (`sim/run_act_core_par.sh`, core_tb default config, Verilator 5.048) | sigil-verify, 12 jobs, 285 s, at `65a48ae` | 2,577/2,578 PASS; only `PMPSm_cfg_A_tor_zero-00` fails, the known PA0 platform waiver (as on main). Main `9da0006` rerun on the same ELFs and machine: same 2,577/2,578, and every ELF has the same verdict and cycle count on both ([`act-full.log`](act-full.log), [`act-full-8-riscv-dv-65a48ae.csv`](act-full-8-riscv-dv-65a48ae.csv), [`act-full-main-9da0006.csv`](act-full-main-9da0006.csv)) |
| Synthesized logic vs main `9da0006`, the five synthesis define sets of `scripts/synth_view_diff.sh` (Verilator -E, sv2v, Yosys equivalence, ABC) | Mac, at `f239397` | only `sigil_core` and `sigil_csr` differ, and only at the three fixes' signals (`ex_vs2_log2`, the vector unit's `scalar_i`, `pmp_wide_b/c_i` -> `pmp_allow_b/c_o`); with the three fixes reverted, the branch's `sigil_core` is proven equivalent to main's; the trace probe leaves nothing under SYNTHESIS; the PMP change is proven (ABC) to alter only aligned 8-byte data/walker accesses whose deciding entry matches one of their two words, which it denies ([`synth-equiv/synth-equiv.log`](synth-equiv/synth-equiv.log)) |
| Linux RTL boot (`soc_rtl_tb`, `Image-initramfs` + `sigil-sim.dtb`) | sigil-verify, at `f239397` | `SIGIL_LINUX_BOOT_OK` at 261,247,447 cycles, the same as main (release gates, and `9da0006` rerun beside it); UART logs byte-identical (890 lines) ([`synth-equiv/linux-boot-8-riscv-dv-f239397.txt`](synth-equiv/linux-boot-8-riscv-dv-f239397.txt)) |

The first gate run, on `c98428b`, stopped `make core-test` at
`vec_trap_directed` test 11 (root cause 7):
[`core-test-c98428b-vec-trap-11.txt`](critic/gates/core-test-c98428b-vec-trap-11.txt).
Full ACT ran afterwards on `65a48ae` (2026-10-23, the same 2,578-ELF set
as main's gates, fingerprint `839ba8be…`): 2,577/2,578, the same result
as main. No verdict or cycle count moved, so no ACT test appears to
reach the changed paths: ACT neither confirms nor contradicts the three
fixes; the
riscv-dv programs and the directed core tests are what cover them
([`pmp-partial-match.txt`](critic/pmp-partial-match.txt)). The one
failure has the same core_tb output and byte-identical per-cycle bus
trace on both RTLs; it uses only 4-byte probes, which the PMP fix does
not change, and fails because Sail access-faults PA 0 (no memory there)
while core_tb has RAM there ([`act-full.log`](act-full.log)).
