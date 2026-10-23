# #8 riscv-dv random regression vs Spike: summary (2026-10-22)

Branch `8-riscv-dv`, not merged; code head `37aa1d7` (the commits after it are documentation and evidence).
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

Altogether 3,573 runs and 153,988,718 compared records (rows 3 and 4
count round 1's records twice, once per run). The 41 runs that did not
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
or waived on this branch and are recorded in #8; no separate issue was
opened, as none is left open.

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

Waived (implementation-defined, kept out of the comparison or the programs):

| Behaviour | How |
|---|---|
| which exceptions `medeleg` can delegate (Sigil keeps access faults in M, Spike delegates them) | `sigil_priv_test` draws only bits both delegate ([`program-bringup.txt`](critic/priv/program-bringup.txt)) |
| `mideleg` bit 12 (SGEIP) with GEILEN = 0: Spike reads one, Sigil zero | comparator: `CSR_IMPL_DEFINED = {0x303: 1 << 12}`, that bit only |
| LR and SC of different widths (extent of the reservation set) | patch R pairs the widths ([`lrsc-width-mismatch-compare.txt`](lrsc-width-mismatch-compare.txt)) |
| RVV: fractional LMUL with SEW > LMUL*ELEN, vl for AVL in (VLMAX, 2*VLMAX), unordered reductions and stores, `vstart` != 0 on arithmetic | `sigil_vector_test` stays clear of them |
| speculative A-bit updates, priority of misaligned vs page/access faults, a failing SC to a no-write page, imprecise FS dirtying, WFI in U, ASIDLEN, mixed Svnapot groups | `sigil_priv_test` stays clear of them |
| free-running counters (cycle, time, instret) | not in the generator's CSR list |

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

Run on the final code (`37aa1d7`; the commits after it change only
documentation and evidence), logs in [`critic/gates/`](critic/gates/):

| Gate | Where | Result |
|---|---|---|
| `make lint`, Verilator 5.044 | Mac (macOS 26.6.2) | rc=0, no warning ([`lint-5.044.log`](critic/gates/lint-5.044.log)) |
| `make lint`, Verilator 5.048 (`deps/`) | sigil-verify | rc=0, no warning ([`lint-5.048.log`](critic/gates/lint-5.048.log)) |
| `make lint`, Verilator 5.020 (Ubuntu apt) | sigil-verify | rc=0, no warning ([`lint-5.020.log`](critic/gates/lint-5.020.log)) |
| `make test` | sigil-verify | rc=0, ALL PHASE-0 KATs PASS ([`test.log`](critic/gates/test.log)) |
| `make core-test` | sigil-verify, VJOBS=4, 2,609 s | rc=0, 297 "TB PASS" lines (main's 293 plus `pmp_partial_directed` in four memory configurations), 0 FAIL ([`core-test.log`](critic/gates/core-test.log)) |
| `make riscv-tests` | sigil-verify | rc=0, 123/123 PASS ([`riscv-tests.log`](critic/gates/riscv-tests.log)) |

The first gate run, on `c98428b`, stopped `make core-test` at
`vec_trap_directed` test 11 (root cause 7):
[`core-test-c98428b-vec-trap-11.txt`](critic/gates/core-test-c98428b-vec-trap-11.txt).
ACT was not rerun (not installed on sigil-verify); the PMP fix only
changes accesses that an entry matches in part, which would have failed
ACT against Sail before ([`pmp-partial-match.txt`](critic/pmp-partial-match.txt)).
