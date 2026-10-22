# #53 on the #73 oops fix: FPGA_TIMING with the walker race fixes (2026-10-22, branch `53-100mhz-afi`)

Branch `53-100mhz-afi` is `73-oops-fix` (the F2 Linux platform, the
Linux/Debian work and the walker race fixes) with `53-mem-stage-pipeline`
(the FPGA timing structures behind `SIGIL_FPGA_TIMING`) merged in. It is
the source for a 100 MHz core-clock AFI.

| Commit | What |
|---|---|
| `b1c0c44` | Merge 53-mem-stage-pipeline (`116c4a4`) into 73-oops-fix |
| `4293184` | `scripts/fpga_timing_equiv.sh`: sigil_core proof, `REF=origin/73-oops-fix`, macOS bash 3.2 |
| `378f4f1` | `ptw_lock_fencei_directed` (new test; `sigil_core.sv` comment only) |
| `c8f7bcd` | Merge 73-oops-fix `2968b6d` (evidence only) |
| `a67e932` | Merge 53-mem-stage-pipeline `db7e759` (script only): one sigil_core proof |
| `990c5de` | Equivalence script: `-ignore-unknown-cells` for the cache proofs (Yosys 0.69) |

From `b1c0c44` to `990c5de` the RTL changes by one comment, so the
gates run at `b1c0c44` (ACT, Linux boot) and at `a67e932` hold for
`990c5de`.

## Merge resolution

- **FPGA_TIMING=0.** The walker race fixes are `73-oops-fix`'s logic
  exactly: stale walker responses are dropped on preempt/abandon
  (`walk_abandon_o`), MEM waits during the Svadu A/D write-back lock
  (`walk_lock_o`), and the SVAs `a_walk_live` and `a_walk_lock_amo`
  are in place. `walk_issue` gains #53's `!(FPGA_TIMING && mem_port_sel)`,
  which is constant 1 in this configuration. Yosys proves it (below).
- **FPGA_TIMING=1: drop.** The walker FSM is the same in both
  configurations. Preemption reads `miss_d`, which here is the miss
  from #53's registered data-port match (`mt_q`). `walk_preempt`,
  `walk_abandon_o` and `walk_lock_o` decode MMU state flops and
  `miss_d` in the same cycle as the FSM transition. So the core's drop
  condition covers both cases as before: a read already in flight, and
  a read issued in the preempting cycle.
- **FPGA_TIMING=1: lock.** `mem_issue` carries `!walk_lock` in both
  configurations. #53 drives the data-port payload from flops
  (`mem_port_sel`): it is MEM's whenever MEM holds a translated access
  or FENCE.I, and the walker waits while it is. The merge masks
  `mem_port_sel` with `walk_lock`, so the walker owns the payload for
  the whole lock while MEM waits.
  - Without the mask, a FENCE.I in MEM during a fetch walk's A/D
    write-back deadlocks: MEM waits for the lock and the walker waits
    for the payload.
  - `ptw_lock_fencei_directed` (new) reaches this case. On the
    unmasked merge (`naive.diff`) it times out at all three oops bus
    timings. The existing A/D race tests pass there with identical
    cycle counts (`lock_fencei.log`).

### Why the A/D race tests do not catch a missing lock with FPGA_TIMING

`fpga_controls.log` has the two FPGA-configuration mutations and a
lock probe. The probe adds sim-only counters over the cycles in which
`walk_lock` is set.

- **No drop** (the drop condition without `walk_abandon`): `a_walk_live`
  fires in all 18 runs (6 preemption / GPA-width tests x 3 timings).
- **No lock in the core at all:** the three A/D race tests still pass,
  with the gate's cycle counts.
- **What the probe shows.** "Block" counts the cycles where MEM would
  issue (port free, a data access or FENCE.I ready, no trap) and only
  the lock stops it.

  | Test | FPGA_TIMING off | FPGA_TIMING on |
  |---|---|---|
  | `ptw_ad_store_race` | 64 | 0 |
  | `ptw_svadu_race` | 32 | 0 |
  | `ptw_svadu_race_hyp` | 96 | 0 |
  | `ptw_lock_fencei` | 32 | 32 (all FENCE.I) |

  The walker never waits inside its own lock ("wwait" = 0 everywhere).
- **The reason.** With FPGA_TIMING, every walker grant invalidates
  `mt_q` (`chg_d`). MEM's translated access therefore replays its
  lookup in the cycle after the leaf PTE read's response, and the
  walker's write-back issues in that same cycle. The probe confirms
  that MEM is in this replay state during the lock ("unxl" > 0, "needs"
  only while the write is in flight).
- **What this means.** With FPGA_TIMING, the replay cycle closes the
  race window in these tests. The lock is still the guarantee for any
  case where the write-back misses that cycle. Of the walker race
  tests, only FENCE.I, which has no translation, is held back by it.

## Equivalence (FPGA_TIMING=0 vs `origin/73-oops-fix` `2968b6d`)

`REF=origin/73-oops-fix scripts/fpga_timing_equiv.sh` at `990c5de`,
Yosys 0.69 and sv2v 0.0.13 on macOS (`equiv.log`):

| Module | Result | `$equiv` proven / unproven |
|---|---|---|
| sigil_csr | EQUIVALENT | 3936 / 0 |
| sigil_mmu | EQUIVALENT | 5128 / 0 |
| sigil_dcache | EQUIVALENT | 2076 / 0 |
| sigil_icache | EQUIVALENT | 768 / 0 |
| sigil_core (default) | EQUIVALENT, 12 paired submodules | 10537 / 0 |
| sigil_core (`SIGIL_SRAM_OREG`) | EQUIVALENT, 12 paired submodules | 10537 / 0 |

The sigil_core proof uses #53's `core_eq`: the whole core, with its
submodules as paired black boxes. Yosys 0.69 needs
`-ignore-unknown-cells` on `equiv_simple`/`equiv_induct` for black
boxes; 0.33 only warned. Two mutations of the FPGA_TIMING=0 path each
leave 1 unproven `$equiv`:

- `walk_issue` without the A/D lock term;
- the stale-response drop without `walk_abandon`.

## Gates

Gates ran on sigil-fpga-build (Verilator 5.048, riscv64 GCC 16.1.0).
Lint also ran on Verilator 5.020 (Ubuntu package) and 5.044 (macOS).

- In the **on** column every Verilator build gets
  `+define+SIGIL_FPGA_TIMING +define+SIGIL_VRF_OREG`.
- All builds use `--assert`, so `a_walk_live` and `a_walk_lock_amo`
  are live in every run.
- The oops runs also have the stale-walk-rsp checker and PTWINV.

| Gate | SHA | FPGA_TIMING off | SIGIL_FPGA_TIMING + SIGIL_VRF_OREG |
|---|---|---|---|
| `make lint` + FPGA lint lines, 5.048 / 5.020 / 5.044 | a67e932 | clean / clean / clean | `sigil_fpga_top` (x2), `sigil_fpga_ocl` (x2, incl. 80 GiB + HBM), `sigil_mmu`/`sigil_csr` `FPGA_TIMING=1'b1`: clean on all three |
| `oops-ptw-walker` (14 tests x 3 timings) | a67e932 | 42/42, PTWINV 0, stale 0 | 42/42, PTWINV 0, stale 0 |
| Walker matrix (18 race tests + `ptw_lock_fencei`, 7 configs each) | c8f7bcd | 133/133 | 133/133 |
| `make core-test` | a67e932 | rc 0: 304 TB PASS, 0 FAIL; SRAM families 5 x 51/51 | rc 0: 295 TB PASS, 0 FAIL; vrforeg, fpga 51/51 |
| `make riscv-tests` | a67e932 | 123/123 | 123/123 |
| Linux 6.12 boot (`soc_rtl_tb_fpga`) to `SIGIL_LINUX_BOOT_OK` | b1c0c44 | (73-oops-fix gate: 261,247,447 cycles) | PASS at 262,556,808 cycles; console = fix gate's apart from timestamps |
| Full ACT (`core_tb_fpga`) | b1c0c44 | (73-oops-fix gate: 2577/2578) | 2577/2578: only `PMPSm_cfg_A_tor_zero-00`; Vx 821/821, Vls 1051/1051, Vf 162/162 |
| Mutations caught (FPGA config) | 990c5de | (Yosys, above) | no drop: 18/18 `a_walk_live`; unmasked lock: `ptw_lock_fencei` 3/3 timeouts |

The walker matrix configs are: core_tb at rand (1:6, gap 2, ready
70), 40:50, lat 1 and no-cache; oops_core_tb at lat 1, rand and 40:50.

Logs:
- `gates.log`: per-chain summaries;
- `walker_matrix.log`: every run with its stale/PTWINV/`%Error` counts and PTWCOV corners;
- `lock_fencei.log`: the FENCE.I lock test and the unmasked-merge control;
- `fpga_controls.log`: the mutations and the probe;
- `equiv.log`;
- `act_fpga.csv`;
- `linux_boot.log`, `linux_boot_info.txt`.

## Not covered here

The CL synthesis does not pass `SIGIL_FPGA_TIMING` or `SIGIL_VRF_OREG`
yet. `fpga/cl_sigil/build/scripts/synth_cl_sigil.tcl` defines only
`SYNTHESIS`, the core clock and the HBM recipe. The 100 MHz AFI build
must add both defines and select a 100 MHz group-B recipe.
