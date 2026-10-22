# #53 FPGA timing baseline: every failing path on main (2026-10-22)

The whole failing-path picture of `main` in the FPGA configuration
(`SIGIL_VRF_OREG`) at 10 ns, grouped into path families, so #53 can
fix everything that fails rather than one worst path at a time.

- RTL: `main` `eeaa332` (unchanged). Flow: branch `53-mem-stage-pipeline`,
  implementation with `fpga/f0/f0_ooc.tcl` at `2492bec` (2,001 s wall);
  failing-path reports regenerated from the routed checkpoint with
  `fpga/f0/f0_timing_reports.tcl` and `fpga/f0/f0_cuts.tcl` at `1df144d`
  (221 s).
- Vivado v2025.2 (64-bit) SW Build 6299465, out-of-context,
  `xcvu47p-fsvh2892-2-e`, 8 threads, on sigil-fpga-build2 (r7iz.8xlarge,
  FPGA Developer AMI). Date 2026-10-22 UTC.
- Commands (repo root):
  `vivado -mode batch -source fpga/f0/f0_ooc.tcl -tclargs build/f0-53-baseline-10ns 10 SIGIL_VRF_OREG`,
  then `vivado -mode batch -source fpga/f0/f0_timing_reports.tcl -tclargs build/f0-53-baseline-10ns/post_route.dcp build/f0-53-baseline-10ns fpga/f0/f0_cuts.tcl`.
- Full reports (not committed, 140 MB with checkpoints):
  `sigil-fpga-build2:/home/ubuntu/wt/53-main/build/f0-53-baseline-10ns/`,
  with one subdirectory per cut step (`cut1-d_translate` ...
  `cut4-csr_rw`).

## Result

Setup WNS **−4.226 ns**, TNS −46,761 ns, **18,180** of 90,745
endpoints failing; hold clean (WHS +0.024 ns). 79,087 LUTs, 32,695 FFs.
Identical to the 2026-10-21 `SIGIL_VRF_OREG` run (the flow is
deterministic).

No SLR crossing in the 2,000 worst failing paths (the core is placed
in SLR2). Routing is 64–89 % of each family's worst path. Families A
and B are deep (34–68 levels, 2.9–4.4 ns of logic); the others carry
at most 3.8 ns of logic and fail on wire delay.

## Path families

Endpoint counts overlap (one endpoint can fail through several
families). The report script keeps the worst path per endpoint, so
families hidden under a worse one were exposed by cutting
(false-pathing) the worse family's nets, step by step
(`f0_cuts.tcl`). Layer: L0 = as routed, L1 = after `d_translate`,
L2 = after `tlb_lookup`, L3 = after `bext`, L4 = after `csr_rw`. Each
row is taken from the last layer before that family's own cut (or L4
if it is never cut). Logic / net = logic and routing delay of the
worst path (ns).

| | Family (path) | Layer | WNS (ns) | Levels worst (max) | Failing endpoints | Logic / net |
|---|---|---|---:|---:|---:|---:|
| A | MEM data translate: VLS/scalar address → D-TLB CAM → PA mux → PMP(PA) → `mem_exc`/`mem_stall`/trap → all MEM consumers | L0 | −4.226 | 68 (68) | 16,374 | 4.4 / 9.8 |
| B | IF fetch translate: `pc_r` → `fetch_va` → I-TLB CAM → fetch ok/fault → PMP(fetch) → `fetch_stall` → I$ BRAM enable / tag WE, IF/ID CE, `pc_r` | L1 | −3.857 | 34 (42) | 664 | 2.9 / 10.6 |
| D | IF fetch control without the TLB: `virt` (fo 606) → bare-mode PA → PMP(fetch) → `fetch_stall` → same sinks as B | L4 | −2.307 | 27 (35) | 649 | 2.4 / 9.6 |
| G1 | EX: forwarding compare → `ex_rs2` (fo 660) → `alu_b` → Bext (≈6 ns) → EX result mux → `exmem_result_q` | L2 | −2.163 | 22 (30) | 64 | 2.2 / 9.9 |
| H | Vector FP op → shared FPU operand mux (`fp_op1`) → FPU multiplier DSP A/B, unpack | L4 | −1.433 | 18 (20) | 414 | 1.6 / 9.5 |
| C | D-TLB lookup → miss → walker start → TLB entry write enables | L1 | −1.390 | 33 (35) | 1,859 | 2.7 / 8.6 |
| E | PTW response: D$ read (way select) → PTE checks → TLB fill enables (whole `tlb_q` array CE), walker state | L4 | −1.325 | 18 (19) | 3,931 | 1.7 / 9.6 |
| I | CSR read-modify-write: `csr_rdata` mux → `csr_wdata` → CSR registers | L3 | −1.268 | 10 (11) | 631 | 1.2 / 10.0 |
| J | Load data: D$ read → align → VRF write data (BRAM DIN), `v0` shadow, VRF bypass | L4 | −1.033 | 14 (15) | 210 | 1.3 / 9.4 |
| K | Vector unit internal: element datapath (`aw_q` → saturate → `w_d_q`), issue → VRF bypass CE / BRAM EN | L4 | −0.968 | 36 (36) | 143 | 2.5 / 8.5 |
| F | PTW request: walker `pte_addr_q` → `dreq_valid` → D$ tag WE / data BRAM enables | L4 | −0.604 | 14 (14) | 346 | 1.2 / 9.1 |
| L | SHA-512 round: `round` → message schedule → `digest_out`, `h`, `a` | L4 | −0.508 | 26 (26) | 179 | 2.8 / 7.7 |
| G2 | EX: FPU final rounding → EX result mux → `exmem_result_q`; ALU → misalign → `exmem_tval_q` | L4 | −0.483 | 42 (42) | 101 | 3.8 / 6.7 |

Failing endpoints per layer: L0 18,180 (WNS −4.226) → L1 7,000
(−3.857) → L2 6,620 (−2.307) → L3 6,604 (−2.307) → L4 5,973 (−2.307).
Families D, E, F, H, J, K, L and G2 were not cut; whatever fails under
them is not yet visible.

### Family A in detail

Arrival times along the worst path (`exmem_ctrl_q[bext_op]` →
`exmem_result_q[63]`): VLS indexed address (VRF bypass → index shift →
64-bit add) 2.66 ns → D-TLB CAM + PA mux (`mmu_d_pa`) 7.59 ns → PMP on
the PA (`pmp_allow_data`) 10.00 ns → fault-only-first `vl` trim / VLS
state → vector CSR write enable (`csr_we`) → `ex_illegal` → vector
`done` → FPU/mul-div result → EX result mux 14.21 ns. Scalar accesses
(from `exmem_addr_q`) reach `mmu_d_pa` at 6.96 ns and `pmp_allow_data`
at 9.36 ns: translation plus PMP alone does not fit one 10 ns cycle
even before any consumer.

Where family A's 16,374 endpoints are (L0, worst path per endpoint):

| Sink | WNS (ns) | Levels | Endpoints |
|---|---:|---:|---:|
| `exmem_result_q` D | −4.226 | 68 | 128 |
| D$ (BRAM enables, tag LUTRAM WE, request regs) | −4.093 | 52 | 1,972 |
| `pc_r` (redirect) | −4.004 | 59 | 127 |
| Pipeline registers, CE (global advance: `mem_stall`/trap) | −3.943 | 56 | 1,684 |
| Pipeline registers, D | −3.901 | 56 | 899 |
| FPU | −3.883 | 57 | 710 |
| MMU (TLB entries, walker) | −3.768 | 45 | 4,745 |
| Vector unit / VRF | −3.648 | 56 | 2,295 |
| Mul/div | −3.628 | 53 | 244 |
| CSR registers | −3.547 | 47 | 3,274 |
| IF-stage state (`straddle`, `ifw`, `ifq`, `boot`) | −3.484 | 56 | 6 |
| Vector LS sequencer (`vls_*`) | −2.628 | 44 | 221 |
| Data-port controller (`dq_*`) | −2.238 | 44 | 3 |
| LR/SC reservation (`res_*`) | −1.806 | 43 | 66 |

Family B's worst path: `fetch_va` 2.11 ns → I-TLB match 4.66 ns →
entry select 6.52 ns → PMP on the fetch PA and fetch fault/stall logic
12.27 ns → `ireq_valid` 12.40 ns → I$ BRAM enable 13.52 ns. Arrival
times were read from `report_timing` on the routed checkpoint.

## Report files (per directory)

`impl_fail_paths.rpt` (worst path to each failing endpoint, first
500), `impl_fail_endpoints.tsv` (every failing endpoint: slack, levels,
delays, start/end pin and register group, hierarchies and RTL-named
nets on the path), `impl_fail_groups.rpt` (by end register group and
pin, by start → end group pair, `report_timing -from/-to` summaries
for the 100 worst pairs), `impl_fail_hier.rpt` (by owning hierarchy,
depth 1–4), `impl_design_analysis.rpt` (`report_design_analysis
-timing`, 100 paths), `impl_logic_levels.rpt` (logic-level
distribution over all failing paths).

## Not covered

- Families were assigned from the endpoint TSVs, first match wins:
  path through `mmu_d_*`/`pmp_allow_data` → A, through `fetch_va` → B,
  through `entry_match`/`perm_ok` → C, through `bext_result` into
  `exmem_*` → G1; otherwise by end and start register group (I$ and
  IF/ID or `pc_r` from `virt_q` → D, `u_mmu` from D$/MMU → E, D$ from
  `u_mmu` → F, other `exmem_*` → G2, `u_fpu` from `u_vec` → H, `u_csr`
  → I, VRF from D$ → J, other `u_vec`/VRF → K, crypto → L). The
  classifier itself is not committed.
- The cut steps only remove paths through nets whose names survive
  synthesis, so the fetch PMP / fetch control (D) and TLB fill (E)
  paths could not be cut by name.
- No RTL change, no functional gates (nothing to gate), no ASIC run.
