# Issue #73 Linux oops on F2: root cause, fix and full gates (2026-10-22)

- Branch: `73-oops-fix`.
- Gate SHA: `31a15689bec847a51357d4dcacc361a4986b548a`.
- Base: `73-linux-release` `5458d16` (main plus the F2 platform and Linux).
- Core issue: #74. Platform issue from the same F2 runs: #75.

## Summary

Debian on the F2 oopsed 35-130 s into systemd startup in every run. On the
same AFI, the memory stress, busybox fork/exec and pmem stress initramfs runs
passed. The cause is an MMU race in the core. When a data-TLB miss preempts an
instruction-fetch page walk, the data walk can consume the fetch walk's PTE
response as its own root PTE. The result is a page fault on a valid address,
or a wrong translation that returns wrong data without a trap. Both F2 oops
signatures follow from the kernel's page-table layout (below). The fix makes
the core drop the response of a walk that the MMU abandons. The Svadu A/D
write-back, found in the same review, is now atomic too. All gates pass at
the gate SHA. The 13 walker race tests fail 39/39 on the base RTL and pass
39/39 on the fix. An AFI has been built from the gate SHA:
afi-059766f9a85c6d39a / agfi-0c8aa56fde1a48495, evidence in
[`f2-platform-73-oopsfix-2026-10-22/`](../f2-platform-73-oopsfix-2026-10-22/).
Still to do: the Debian boot on F2 with that AFI.

## Root cause

`sigil_mmu` has one page-table walker. It borrows the core's data port, and
MEM has priority on that port. A data-TLB miss in MEM preempts a fetch walk in
`W_VS_READ` / `W_G_READ` ("an older data miss preempts a fetch walk"): the
walker restarts as a data walk for MEM's address. On the base RTL,
`sigil_core` marked an outstanding walker read stale (`dq_drop_q`) only on
`sfence_fire || trap_take`. A preemption did not mark it, so the fetch walk's
PTE read was still live. Its response became the next `walk_rsp`, which the
data walk took as its own level-2 (root) PTE.

Two triggers:

- **A, read in flight.** The fetch walk's PTE read is already on the port when
  the data miss reaches MEM. This needs a PTE line miss in the D$ or uncached
  tables. On F2 a cold D$ refill takes 45.6 core cycles on
  average from DDR4 (729 ns at 62.5 MHz; `f2-platform-73-2026-10-22/SUMMARY.md`).
- **B, same cycle.** A fetch walk waits in `W_VS_READ` because MEM owns the
  port. `load1` (TLB hit, D$ miss) completes. `load2` (D-TLB miss) enters MEM
  in the same cycle. In that cycle `walk_issue` fires for the fetch walk's
  root read, because MEM no longer needs the port, and the MMU preempts the
  fetch walk. The read hits in the D$ one cycle later, and the data walk takes
  it. Dropping only reads that are already in flight does not cover this
  trigger (`73-oops-dcache`, `ev_ptw_preempt_partial_fix.log`).

## Why it gives exactly the two F2 signatures

Details are in [`f2_signature.txt`](f2_signature.txt): System.map,
disassembly of the oops sites from the released `Image`, and the page-table
index of every fault address in the F2 logs.

1. **Every oops PC is the second of two dependent loads** (trigger B):
   - `anon_vma_clone+0x62`: `ld s11,8(s4); ld a4,0(s11)`
   - `folio_lruvec_lock_irqsave+0x42`: `ld s1,8(a5); ld a5,200(s1)`
   - `filemap_fault+0x2c`: `ld s3,24(s6); ld s5,0(s3); ld a5,80(s5)`
   - `filemap_map_pages+0x58`: `ld a5,0(a4); ...; ld s1,80(a5)`
2. **Kernel text is at `ffffffff80000000`, which is Sv39 root entry 510.**
   That entry points to a PMD table of 2 MiB leaves. With `_end - _start` =
   0xf21000, only entries 0-7 are valid. A kernel fetch walk reads root[510]
   first.
3. **The faulting addresses are linear-map addresses** (`ffffffd6...` = PA
   from `0x8000_0000`, root entries 344-346). A data walk that consumed
   root[510] goes on to index the kernel PMD table with its own VA[29:21]:
   - **VA[29:21] >= 8: invalid entry.** The result is "Unable to handle kernel
     paging request" at a valid address (signature a). All 13 such faults in
     the F2 logs have VA[29:21] between 12 and 34.
   - **VA[29:21] = 3, and the first 143 KiB of 4: freed init memory.** These
     map kernel offsets `0x600000-0x823c08` = `__init_begin..__init_end`.
     `free_initmem()` has filled that region with `POISON_FREE_INITMEM`
     (`0xcc`). The load returns `0xcccccccccccccccc`, and the next dependent
     load (`ld ..,80(reg)`) faults at `cccccccccccccd1c` (signature b,
     `filemap_fault+0x2c` / `filemap_map_pages+0x58`).
   - **Other VA[29:21] < 8: wrong data, no trap.** The load returns kernel
     text or data, and the wrong translation is filled into the TLB. The
     `__list_add_valid_or_report` BUGs and the NULL dereference in
     `folio_batch_move_lru` in `exp-nothp` are consistent with this case,
     but no trace confirms it.
4. **Why the small stress loads did not oops in minutes: not established.**
   The race needs a fetch walk that is waiting or in flight at the moment a
   dependent load misses the D-TLB. A plausible reason is that Debian's
   systemd startup spreads kernel execution over many more code and data
   pages (fork/exec, mmap, page cache, many processes) than the busybox
   loops do.

## Fix

| commit | change |
|---|---|
| `ae1587c` | `sigil_mmu`: `walk_abandon_o` = a fetch walk preempted in `W_VS_READ`/`W_G_READ` by a data miss, or a G-stage GPA-width fault ending `W_G_READ`. `sigil_core`: the drop condition becomes `(sfence_fire \|\| trap_take \|\| walk_abandon) && ((dq_pend_q && dq_walk_q && !drsp_valid_i) \|\| (walk_issue && dreq_ready_i))`. |
| `882e440`, `6f15748` | Simulation assertions `a_walk_rsp` (the walker takes only its own response) and `a_walk_live` (a live walker request belongs to the current walk), checked in every testbench. |
| `69cc541` | Atomic Svadu A/D update. `walk_lock_o` keeps the port from the leaf read to the write-back, and for a VS leaf under two-stage translation also across the G-stage walk of the PTE's GPA. Without it, an older store to the PTE is overwritten by the stale `pte_q\|A`. The hunt rated this "unconfirmed, low"; `ptw_ad_store_race` and `ptw_svadu_race{,_hyp}` confirm it on the base RTL. |
| `d2946b9`, `27a8b76`, `b06ecfb` | 13 walker race tests in core-test (rand, nocache, xinit, SRAM macros). |
| `cb523fa`, `efe871d` | Simulation-only checkers (`tb/sv/sigil_oops_chk.sv`, `tb/sv/sigil_ptw_inv.sv`) and the `sim/Makefile.oops` runners. |

The change is unconditional; it is not behind `SIGIL_FPGA_TIMING`.

## Before and after (this gate)

From [`before_after.log`](before_after.log): the 13 walker race tests on
`oops_core_tb`, the `core_tb` harness with both checkers. The same binaries
ran at `--mem-lat 1`, rand (`1:6`, gap 2, ready 70) and `40:50` on the base
RTL and on the gate SHA.

| test | 5458d16 (lat1 / rand / 40:50) | 31a1568 |
|---|---|---|
| `ptw_preempt_directed` (A, uncached tables) | FAIL 0x10D (load page fault on a mapped VA) x3 | PASS x3 |
| `ptw_preempt_cached_directed` (A, cacheable tables) | FAIL 0x1FF (wrong data, no trap) x3 | PASS x3 |
| `ptw_preempt_twoload_directed` (B, same cycle) | FAIL 0x11FF (wrong data) x3 | PASS x3 |
| `ptw_preempt_{b2b,trapdrop,hyp,guest}_directed` | FAIL x12 | PASS x12 |
| `ptw_gwidth{,_load,_redirect}_directed` | FAIL x9 | PASS x9 |
| `ptw_ad_store_race`, `ptw_svadu_race{,_hyp}` (A/D atomicity) | FAIL x9 (lost store; no stale response) | PASS x9 |
| **total** | **0/39 pass; 30 `stale-walk-rsp`, 271 PTWINV reports** | **39/39 pass; 0, 0** |

On the fix, PTWCOV shows the drop corners being reached:
- `ptw_preempt_twoload`: `issue_acc=16` (trigger B) at every timing;
- `ptw_preempt_trapdrop` at 40:50: `trap=192 inflight_drp=12 rsp_drp_same=2`;
- `ptw_preempt_hyp` at 40:50: `inflight=313 rsp_same=8 issue_acc=8`.

## Gates at 31a1568

From [`gates.log`](gates.log): a fresh clone on `sigil-fpga-build`, with
worktrees of it for the boot, oops and ACT steps. The macOS lint used a
worktree at the same SHA.

| gate | result |
|---|---|
| `make lint`: Verilator 5.048 / 5.020 (Ubuntu package) / 5.044 (macOS) | PASS: 19 lint runs, 0 warnings, on each |
| `make test` | PASS (ALL PHASE-0 KATs) |
| `make core-test` | PASS: 293 `TB PASS`, 0 FAIL, 0 assertion failures. The 13 walker race tests pass rand / nocache / xinit1 / xinit3; 50/50 directed runs on each SRAM-macro build |
| `make riscv-tests` | PASS: 123/123 |
| full ACT, 2578 ELFs | 2577/2578. Only `PMPSm_cfg_A_tor_zero-00` fails, the known PA0 waiver. Vx 821/821, Vls 1051/1051, Vf 162/162 |
| `make -C sim socrtl sochash examples fpgatop-quick fpgatop-f2-quick fpgaocl-quick srammacro` | PASS, 0 failures |
| Linux 6.12 boot on `soc_rtl_tb` (`Image-initramfs`, `sigil-sim.dtb`) | PASS: `SIGIL_LINUX_BOOT_OK` at 261,247,447 cycles. The UART log is byte-identical to the `73-linux-release` gate's |
| `make -C sim -f Makefile.oops oops-ptw-preempt` / `oops-ptw-walker` | PASS: 9/9 and 39/39; 0 `stale-walk-rsp`; PTWINV violations 0 |

The first attempt hit a full root disk on the build host at 14:27Z.
`core-test` writes about 20 GB of coverage files. The affected steps were
rerun from the same clean clone; see note 1 in `gates.log`.

## Linux stress under the checkers, fixed vs unpatched

From [`linux_stress.log`](linux_stress.log). The fixed RTL ran on
`oops_soc_rtl_tb`, which carries `sigil_oops_chk`, `sigil_ptw_inv` and the
core SVA. The unpatched runs are the dcache hunter's, from the 5458d16 RTL
with the same checker, in `~/oops/dcache/runs/`.

| image, timing | fixed 31a1568 | unpatched (hunter) |
|---|---|---|
| ptwstress v2, `--mem-lat 40:50` | PASS: `PTWSTRESS DONE` at 689,559,153 cycles; 400 passes, bad=0; stale 0 | `PTWSTRESS DONE` at 689,559,153 cycles; stale 0 |
| ptwstress v2, `--mem-lat 1` | PASS at 308,934,879 cycles; stale 0 | 308,934,879 cycles; stale 0 |
| `Image-execstress`, `--mem-lat 40:50` | 2G-cycle budget reached (TIMEOUT by design, 8102 s), past `execstress: start 76.87`; stale 0, PTWINV 0, no oops; PTWCOV `pre=0` | still running at 16:49Z (5.5 h CPU); past `execstress: start 76.87`, no worker progress line; stale 0 |
| `Image-execstress`, `--mem-lat 1` | 2G-cycle budget reached (8237 s), past `execstress: start 36.70`; stale 0, PTWINV 0, no oops; PTWCOV `pre=1 rsp_same=1` | still running at 16:49Z (5.5 h CPU); past `execstress: start 36.70`, no progress line; stale 0 |
| `Image-initramfs` boot, lat 1 | (plain `soc_rtl_tb` above) 261,247,447 cycles | 261,247,447 cycles; stale 0 |

Zero `stale-walk-rsp` on the fixed RTL is expected. It is not a
discriminating result, because the unpatched runs report zero too. PTWCOV on
the fixed RTL counts fetch-walk preemptions:
- both ptwstress runs and execstress at 40:50 end with `pre=0`;
- execstress at lat 1 ends with exactly one preemption. In it the fetch
  walk's response arrives in the same cycle (`rsp_same=1`), the corner where
  nothing is left in flight. The fix handled it with no stale response and
  no PTWINV violation.

Where both RTLs ran, the cycle counts are identical. In simulation these
workloads do not reach the harmful case (a fetch-walk read in flight, or
issued in the preempting cycle); the directed tests above do. The
remaining check is the F2 Debian boot on an AFI built from this branch.

## Files

- `gates.log`: the gate log (tools, commands, results, Linux runs, before/after).
- `before_after.log`: the 13 walker race tests x 3 timings on the base and fixed RTL under both checkers.
- `f2_signature.txt`: the kernel layout, disassembly and fault-address table behind the signature analysis.
- `linux_boot.log`: the `soc_rtl_tb` Linux 6.12 boot console at the gate SHA.
- `linux_stress.log`: the checker summaries and console tails of the Linux stress runs on the fixed RTL, next to the hunters' unpatched runs.
- `act_summary.txt`: per-suite ACT counts and the failing row.

Earlier evidence for this fix is in `oops-fix-73-2026-10-22/` (first
before/after, `cb523fa` gates) and `oops-fix-gaps-73-2026-10-22/` (the
review's gaps, the A/D lock, variant runs). The hunters' evidence is on
`73-oops-dcache` (`docs/evidence/oops-dcache-73-2026-10-22/`), and the F2 A/B
runs are on `73-linux-debian` (`docs/evidence/linux-debian-73-2026-10-22/f2-oops-ab.txt`).
