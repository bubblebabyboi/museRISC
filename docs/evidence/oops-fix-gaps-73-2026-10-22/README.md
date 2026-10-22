# Issue #73: closing the gaps the fix review found (2026-10-22)

Branch `73-oops-fix`. The review of the walker-race fix (branches
`73-oops-skeptic-patch-correctness`, `73-oops-skeptic-other-preemption-paths`,
`73-oops-skeptic-svadu-atomicity`) tested `experiment-preempt-drop.patch`
on `73-linux-release` and reported these gaps. Status on this branch:

| Gap (review) | Status | Where |
|---|---|---|
| G-stage GPA-width fault leaves `W_G_READ` with a read issued in that cycle and not dropped (V=1 only; fetch, data or redirect consumer) | Already closed by `ae1587c`: `walk_abandon_o` includes `(state_q == W_G_READ) && g_width_fault`. The review's three width-fault tests pass at all timings and with caches off. They fail when that term is removed, so they now guard it in core-test | `ptw_gwidth_directed`, `ptw_gwidth_load_directed`, `ptw_gwidth_redirect_directed` |
| Directed suite never preempts a fetch walk; corners of the drop condition untested (V=1, already-dropped read in flight, trap in the same cycle, back-to-back) | The review's tests are now in core-test. The PTWINV invariant is a core SVA (`a_walk_live`), so every testbench checks it, Linux soc_rtl runs included | `ptw_preempt_b2b/trapdrop/hyp/guest_directed`, `sigil_core.sv` `a_walk_live` |
| Non-atomic Svadu A/D write-back: MEM takes the port between the leaf read and `W_VS_UPD`, so an older SD/SC/AMO to that PTE is overwritten by the stale `pte_q\|A` | Fixed in `69cc541`: `walk_lock_o` lets the walker keep the port from the leaf read to its write-back. For a VS leaf under two-stage translation the lock also covers the G-stage walk of the PTE's own GPA (`W_G_READ`, g purpose 2) | `sigil_mmu.sv`, `sigil_core.sv`; `ptw_ad_store_race_directed`, `ptw_svadu_race_directed`, `ptw_svadu_race_hyp_directed` (new) |

The review's other finding was that the drop-on-preempt patch is
sound for the preemption class (no over-drop, two-stage + HLV
preemption passes). Its `ptw_preempt_guest_directed` cross-check
is now in core-test too.

## Changes

- `69cc541` MMU/core: `walk_lock_o = W_VS_UPD || W_G_UPD || (W_G_READ && g_purpose_q == 2)`.
  While it is set, `mem_issue` waits and `walk_issue`/`walk_skip` ignore
  `mem_needs_port`. The lock starts in the cycle after the leaf read's
  response, when the port is free, so no MEM access can get in between.
  It ends after the write-back, plus the G-stage walk for a VS leaf.
  `a_walk_lock_amo` asserts that the lock never falls between an AMO's
  read and its write.
- `6f15748` core: `a_walk_live`. A walker request that is still live
  (`dq_pend && dq_walk && !dq_drop`) must be the PTE access the walker
  presents now. This is the review's PTWINV invariant, checked in every
  cycle.
- `27a8b76`, `b06ecfb` tests: the review's 9 tests plus
  `ptw_svadu_race_hyp_directed`, a VS-guest variant of the Svadu sweep
  (`PTW_SVADU_HYP`). All 10 are added to `TESTS` and `run_directed.sh`
  (rand, nocache, xinit, SRAM macros). CORE.md is updated.
- `efe871d` `tb/sv/sigil_ptw_inv.sv` (PTWINV/PTWCOV) is bound in the
  oops testbenches. `make -C sim -f Makefile.oops oops-ptw-walker` runs
  all 13 walker race tests at the three oops timings.

## Results (sigil-fpga-build, Verilator 5.048)

Full per-run tables are in `walker_runs.log`. The configs are lat1, rand
(1:6 gap2 ready70) and 40:50, each with core_tb and with oops_core_tb
plus checkers, and nocache with core_tb.

- BEFORE (9265d31 RTL): every preemption and width-fault test passes.
  `ptw_ad_store_race` fails test 496 at all four configs.
  `ptw_svadu_race` and `ptw_svadu_race_hyp` fail test 12 (SC and SD lose
  the marker) at lat1, rand and 40:50. They pass with caches off.
- AFTER (efe871d): 126/126 runs pass (18 tests x 7 configs) with 0
  stale-walk-rsp, 0 PTWINV and 0 assertion failures. The PTWCOV corners
  are reached. At 40:50: trapdrop trap=192 inflight_drp=12
  rsp_drp_same=2, b2b issue_acc=24, hyp inflight=313 rsp_same=8
  issue_acc=8, gwidth gw_issue=558 (redirect 229, load 548).
- Variant `updonly` (lock only in the UPD states): the single-stage
  Svadu tests pass and `ptw_svadu_race_hyp` fails (test 12 at lat1,
  rand and 40:50). The g purpose-2 term is needed.
- Variant `nogw` (width term removed from `walk_abandon_o`): the three
  width-fault tests fail through the `a_walk_rsp` assertion or PTWINV.
  `nogw2_runs.log` shows the same variant on efe871d, where
  `a_walk_live` fires.
- Hunter tests (`make -C sim -f Makefile.oops oops-ptw-preempt`): 9/9
  PASS (`oops-ptw-preempt.log`). `oops-ptw-walker`: 39/39 PASS with
  PTWINV violations=0 (`oops-ptw-walker.log`).
- Gates on the committed head efe871d (`gates.log`):
  - lint is clean with Verilator 5.048, 5.020 and 5.044 (macOS).
  - core-test rc=0: 293 TB PASS lines, 0 FAIL, 0 assertion failures.
    The 10 new tests pass in rand, nocache, xinit1 and xinit3, and each
    SRAM-macro build passes 50/50 directed runs.
  - riscv-tests: 123/123.
- Linux 6.12 initramfs boot on soc_rtl_tb from efe871d, with the same
  artifacts and command as the fix gate: `SIGIL_LINUX_BOOT_OK` in
  17m39s, exit 0, no assertion (`linux_boot_info.txt`,
  `linux_boot.log`).
