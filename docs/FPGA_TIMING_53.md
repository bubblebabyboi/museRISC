# #53 FPGA timing closure: implementation plan

- Date: 2026-10-22 (UTC). Branch `53-mem-stage-pipeline`. RTL base:
  `main` `eeaa332`.
- Status: steps 1–3 (iteration 1) and 5–7 (iteration 2) implemented
  and measured with the `iter` flow of step 0b; steps 0a/0b in part
  (parameter, lint lines, `fpga` srammacro family, F0 strategies,
  per-module equivalence script). **Iteration 2 meets 10 ns** in the
  F0 flow: WNS +0.614 ns (106.5 MHz) with `iter` and +0.828 ns
  (109.0 MHz) with `closure`, 0 failing endpoints, at `d7e8e41`
  (steps 1–3 and 5–7). Steps 4 and 8–13 are not needed for
  the F0 target and stay planned as margin for the CL build. Results
  per iteration:
  [`evidence/fpga-timing-53-iterations-2026-10-22.log`](evidence/fpga-timing-53-iterations-2026-10-22.log).
  Step 15 gates, round 1 at `116c4a4`: lint, simulation, ACT, riscv-dv
  and the equivalence proofs pass in both settings; Yosys cell counts
  cannot serve as the identity test (see the log); F0 still +0.614 ns
  ([`evidence/fpga-timing-53-gates-2026-10-22.log`](evidence/fpga-timing-53-gates-2026-10-22.log)).
- Baseline: [`evidence/fpga-timing-53-baseline-2026-10-22.md`](evidence/fpga-timing-53-baseline-2026-10-22.md).
  `main` with `SIGIL_VRF_OREG` at 10 ns has WNS −4.226 ns and 18,180
  failing endpoints in 13 path families. Family letters (A–L, G1, G2)
  below refer to that table.
- Acceptance (#53): Vivado 2025.2 post-route WNS ≥ 0 at 10 ns in the
  F0 out-of-context flow (`xcvu47p-fsvh2892-2-e`), every gate green in
  both settings, ISA bit-exact.

## The FPGA_TIMING rule

- **One define, one parameter.** `SIGIL_FPGA_TIMING` sets
  `localparam bit FPGA_TIMING` in `rtl/core/sigil_cache_pkg.sv`, next
  to `VRF_OREG`. The FPGA build defines
  `SIGIL_FPGA_TIMING SIGIL_VRF_OREG`.
- **Every #53 RTL change sits behind it, cycle-neutral or not.** Each
  change is
  `if (FPGA_TIMING) begin : g_x ... end else begin : g_x_off <origin/main code> end`,
  or a select on the constant parameter. There are no scattered
  `ifdef`s, and both branches are always elaborated and linted.
- **The ASIC configs do not change.** With the define absent, the
  default, SRAM_OREG/sky130 (the #11 GDS in flight) and nangate45
  (107.9 MHz) configs elaborate to the same logic as `origin/main`. An
  equivalence check proves this from the first RTL commit on (step 0),
  not only at the end.
- **Crypto blocks take a parameter.** `sha512_block`,
  `sigil_hash_stream` and `sigil_crypto_top` get
  `parameter bit FPGA_TIMING = 0`, and `sigil_crypto_bridge` passes in
  `sigil_cache_pkg::FPGA_TIMING`. The standalone crypto lint lines and
  TBs, which do not compile the core packages, still build.
- **Simulation cross-checks.** Each new structure is checked against
  the `origin/main` expression, computed in an `ifndef SYNTHESIS`
  block next to it (the style of the existing checks in
  `sigil_core.sv`). Every simulation run with the define compares new
  against old every cycle.
- **ASIC-useful refactors wait.** Changes that would also help ASIC
  timing are listed under "ASIC promotion candidates". None is
  unconditional now.

## How this plan was chosen

Three designs were scored by three judges, each through a different
lens.

| Plan | Timing closure | ISA correctness | Delivered performance | Total |
|---|---:|---:|---:|---:|
| P1 minimal-CPI: registered forwarding, D-TLB lookup in EX (`mt_q`), fetch page register, cycle-neutral fixes | 6.5 | 7.5 | 8 | **22.0** |
| P2 structural: 6-stage IF ID EX M1 M2 WB, L0 ITLB, register boundaries at PTW, CSR write, VLS write-back and vector-FPU request | 7.5 | 5.5 | 5 | 18.0 |
| P3 FPGA implementation: pblock and strategy first (measured), translation reuse registers, parallel PMP, CSR pre-decode | not seen | not seen | 7 | 7.0 |

The timing and ISA judges received a truncated task text without P3.
The performance judge recovered P3 from the workflow journal. Even if
all three judges had scored P3 at 7, its total (21) would stay below
P1's.

**P1 is the base.** Grafts are tagged by source: [P2], [P3],
[J-timing], [J-ISA], [J-perf].

## Conflicts resolved

1. **Taking data translation out of the MEM cycle.**
   - Options: P1 looks up the D-TLB in EX into `mt_q` (0 cycles on
     hits). P2 splits MEM into M1/M2 (+1 per adjacent load-use, +1
     per CSR write, about +1.8 % on Dhrystone). P3 keeps 1-entry
     load and store reuse registers (+1 per page or type change,
     +2–5 % estimated on Linux).
   - Decision: **P1.** It has the best CPI and the best ISA score:
     commit points do not move, and every cached value has a
     same-cycle oracle. P3's reuse registers are the fallback if the
     EX-port lookup cannot close. The M1/M2 split is not used.
2. **Finishing a walk.**
   - Options: P1 loads `mt_q`/`it_q` straight from the walker on the
     completion edge.
   - Decision: **a replay lookup instead, +1 cycle per data walk.**
     - The direct load adds a new D$ data → PTE → permission →
       `mt_q` path about as deep as family E [J-timing].
     - It would also have to lose to a flush on both the capture edge
       and the write edge [J-ISA].
     - With replay, the parked MEM VA stays on the D port from walk
       start until the replay. The recorded walk fault (`wf`) then
       survives under its existing rule [P2].
     - A walk is at least 3 PTE reads of at least 2 cycles each, so +1
       is a small fraction of a walk, and bare-metal code never walks.
3. **Walk request.**
   - Today the walker samples the D port (`miss_d`, `d_va_i`, the
     context) in `W_IDLE` and when a data miss preempts a fetch walk.
     Once the D port serves EX, that would walk the wrong VA.
   - Decision: **a registered MEM-side walk-request port.** A walk
     starts only from a MEM access that is really performed and has
     no older trap [J-ISA, P2].
4. **Fetch translation.**
   - Options: P1 uses a page register `it_q` plus a redirect CAM
     port. P2 uses a 4-entry L0 ITLB on a registered `fetch_va`. P3
     uses one reuse register.
   - Decision: **P1's `it_q`**, holding OK translations only. A fault
     is delivered once from a one-shot record and never cached
     [J-ISA, P2].
   - The redirect port is a third CAM on a late EX input, so it
     becomes a separate optional CPI step after closure (step 16).
     Closure does not depend on it.
5. **Family I (CSR read-modify-write).**
   - Options: P1 distributes the RMW per CSR. P2 registers the CSR
     write port (+1 per CSR write). P3 pre-decodes a registered
     one-hot read select.
   - Decision: **P3 first** (small, checked by assertion), **P1 as the
     fallback**. P2 is rejected for its CPI cost and its hold hazards
     [J-perf, J-ISA].
6. **Family H (vector → FPU operands).**
   - Options: P1 retimes the operand selection into `u_vec`. P2
     registers the request (+1 per vector FP sub-step). P3 measured H
     at −0.011 ns from flow changes alone.
   - Decision: **the flow and `-dsp_register_opt` first, then P1's
     retiming, then P2's register.**
7. **Family G1 (Bext).** **P1's** registered forwarding, operand
   copies and one-hot result select come first. A 2-cycle unit for
   the slow Bext ops [P3, P2] is used only if G1 still fails
   afterwards.
8. **Families C/E (TLB fill).**
   - Options: P1 registers the whole fill (`fill_q`, relying on its
     direct loads). P3 registers only the fill index. P2 registers the
     PTE response (+1 per PTE read).
   - Decision: **P3's registered `fill_idx_q`** (exact and
     cycle-neutral) plus capture-always PTE registers. `fill_q`, then
     the PTE response register, are the fallbacks.
9. **Family F (PTW request).**
   - Options: P1 reads the cache arrays speculatively (cycle-neutral).
     P2 registers the PMP verdict of the next PTE.
   - Decision: **P1.** P2's registered verdict is rejected because a
     `pmpcfg` write could go unseen by a walk in progress [J-ISA].
10. **Family J (load data → VRF).** **P1's single byte rotate first.**
    P2's `vls_wb_q` is the fallback, with element i−1's write
    committing even when element i faults or trims `vl` [J-ISA].
11. **Family K (vector datapath).** P1 and P3 cover only K1. **P2's
    K2 fix is added** (a precomputed "S2 frees next cycle" flag)
    [J-timing].
12. **Flow.**
    - Options: P1 makes synthesis timing-driven and adds directives.
      P3 measured a strategy plus a pblock.
    - Decision: **both**, as the `iter` and `closure` strategies. No
      RTL step depends on the pblock, because it is an OOC proxy that
      the CL build must re-derive [J-perf].
13. **Hidden layers.** P1 would find them at close-out. **They are
    inventoried in step 0** with group-based cuts instead [P2, P3].
14. **Not used:** any contingency that changes ISA-visible timing:
    - fetch PMP after the I$ request [P2 10b];
    - the M1/M2 split;
    - the registered CSR write port;
    - the registered PTE PMP verdict [J-ISA].

## Steps

**How each step is built and measured**

- Every step is one or a few commits on this branch, pushed as they
  land.
- Each step gets its own F0 run at its SHA, then
  `f0_timing_reports.tcl` with the current cuts, then an evidence file
  `docs/evidence/fpga-timing-53-s<N>-2026-10-2x.md`. The evidence
  records the SHA, Vivado 2025.2, Verilator 5.048 (plus the 5.020
  lint), the UTC date and the family table.
- Up to three F0 runs can go at once on sigil-fpga-build2.
- Steps 8–13 touch separate modules (`sigil_mmu` fill, `sigil_vec`,
  `sigil_csr` read, `sha512_block`) and can be developed alongside
  steps 5–7. They land in this order so that each WNS delta can be
  attributed to one step.

**How to read the WNS estimates**

- WNS is the `iter` strategy result unless noted.
- Estimates come from arrival times on the routed baseline: `ex_rs1`
  3.44 ns, `ex_rs2` 4.55 ns, `alu_b` 5.26 ns, scalar PA 6.96 ns, PMP
  verdict 9.36 ns, `fetch_va` 2.11 ns, `branch_taken` 6.88 ns,
  `flush` 8.83 ns. They also use P3's two measured flow runs.
- Allow ±0.5 ns for placement. The families never cut so far (D, E,
  F, H, J, K, L, G2) are the least certain.

**Gates in both settings for every RTL step.** Each step lists the
specific checks that catch its likely mistakes. On top of those, every
RTL step runs the following, in the default setting and in the `fpga`
setting:

- `make lint`
- `make test`
- `make core-test`, including the `fpga` srammacro family
- the step-0 equivalence check

### Step 0: plumbing, flow and hidden-layer inventory (no RTL logic change)

**0a. Plumbing**

- **Parameter:** add `FPGA_TIMING` to `sigil_cache_pkg.sv`, unused for
  now. Add the crypto parameter pass-through.
- **`Makefile` lint lines:**
  - `sigil_soc_top`, `sigil_core` and `sigil_cpu` with
    `+define+SIGIL_FPGA_TIMING +define+SIGIL_VRF_OREG`;
  - `sigil_soc_top` with `SIGIL_FPGA_TIMING` alone;
  - `sha512_block` with `-GFPGA_TIMING=1`.
  - Lint with Verilator 5.048 locally and with CI's 5.020 in Docker.
- **`sim/Makefile`:**
  - An `fpga` family in `SRAM_MACROS`:
    `SRAM_DEF_fpga := +define+SIGIL_VRF_OREG +define+SIGIL_FPGA_TIMING`.
    `srammacro` then runs `vec_tb`, `core_tb` (every directed test,
    random bus latency) and `soc_rtl_tb` (crypto firmware) in the FPGA
    configuration.
  - `_fpga` builds of `dcache_tb`, `icache_tb` and `mmu_tb`, and a
    `-GFPGA_TIMING=1` `sha512_tb`.
  - A `soc_tb` build with both defines for the Linux boot and the KVM
    smoke test.
- **`scripts/fpga_timing_equiv.sh`:**
  - Yosys synthesis of `sigil_soc_top` for three configs: default,
    `SIGIL_SRAM_FAKERAM45`, and `SIGIL_SRAM_SKY130` with the SKY130
    SoC parameters. It uses the sv2v front end, as
    `scripts/synth_caches.sh` does.
  - Each config is built from the branch and from `origin/main`, then
    compared with `eqy` (or `equiv_make`/`equiv_simple`/`equiv_induct`)
    and an identical `stat`.
  - It runs on build2 for every RTL step.
- **New directed test `sw/core-tests/vm_ctx_directed.S`** [P3, J-ISA].
  It is written and passing on `origin/main` before any RTL change.
  Cases:
  - `csrw satp` without SFENCE, then an access;
  - MPRV toggles around loads;
  - SUM/MXR toggles;
  - a store to a D=0 page after a load from it;
  - HLV after a normal access to the same VA;
  - a page-straddling 32-bit fetch that faults on its second half;
  - a VLS crossing a page with a faulting element, then `vstart`
    resume;
  - an interrupt during a refill;
  - an I-walk grant one cycle before `sfence_fire`.
- **Gates:** lint (both versions); `srammacro` `fpga` identical to
  `vrforeg` (nothing reads the parameter yet); equivalence clean; the
  new test passes in both settings.

**0b. Flow** (`fpga/f0` only)

- **Timing-driven synthesis.** Add `fpga/f0/f0_synth.xdc` with
  `create_clock` on `clk_i`, read before `synth_design`. Today
  `create_clock` (f0_ooc.tcl line 24) comes after `synth_design`
  (line 22), so synthesis is not timing-driven. Add
  `synth_design -directive PerformanceOptimized`.
- **A strategy argument for `f0_ooc.tcl`:**
  - `iter` (default): timing-driven synthesis plus today's
    implementation directives, about 35–45 min. Every step's delta
    is measured with it.
  - `closure` [P3 E2], about 65 min:
    - `opt_design -directive ExploreWithRemap`;
    - `place_design -directive ExtraTimingOpt` with a 0.5 ns setup
      uncertainty, removed before routing;
    - `phys_opt_design` and `route_design` with `AggressiveExplore`;
    - a post-route `phys_opt_design`;
    - `-force_replication_on_nets` on the measured high-fanout nets:
      `memwb_exc_q` (fanout 703), the CSR `virt` (606), the `ex_rs2`
      forward select (660), `memwb_rd_q` (408), `walk_grant` (288) and
      `u_vec` `sew_q`/`op_q`;
    - `fpga/f0/f0_floorplan.xdc`: a `u_cpu` pblock at
      `CLOCKREGION_X1Y9:X3Y10` plus a hash-engine pblock next to it.
  - Options to try along the way: `-flatten_hierarchy full` against
    `rebuilt`, and soft `KEEP_HIERARCHY` on `u_mmu`/`u_csr`.
- **Group cuts.** `f0_cuts.tcl` gets group-based `-from`/`-to` cuts
  (the start and end cell groups the family classifier uses) for D,
  E, F, H, J, K, L and G2. These families have no net names that
  survive synthesis.
- **Re-baseline and inventory.** Re-run `eeaa332` + `SIGIL_VRF_OREG`
  with `iter` and with `closure`. Then run `f0_timing_reports.tcl`
  with the group cuts on both checkpoints. The output is an inventory
  of what hides under each family.
- **Expected:**
  - `iter` ≈ −3.9 ± 0.3 (directives alone measured −3.904 [P3 E1]).
  - `closure` ≈ −3.2 or better (pblock + directives measured −3.220
    without timing-driven synthesis [P3 E2]).
  - Watch the two layers E1 exposed: `vsatp` → I-TLB → `pc_r`
    (−1.55, fixed by step 7) and `vtype` → `csr_we` → `ex_illegal` →
    FPU (fixed by step 1).
- **Cycles:** none.

### Step 1: CSR legality from write intent; FPU and M-unit requests without `ex_illegal`

- **Change** (`sigil_core`, `sigil_csr`):
  - `sigil_csr` takes the static write intent,
    `csr && (funct3[1:0] == 01 || rs1 != 0)`, for its read-only-write
    check instead of `wr_en_i`. Today `wr_en_i` is `csr_we`, which
    carries `!mem_exc && !mem_stall && !trap_fire`
    (sigil_core.sv:1087).
  - `fpu_req` is qualified by `fp_illegal` only. `muldiv_req` gets no
    legality term, because the decode classes are disjoint.
  - Audit every consumer of `ex_illegal` that acts in a cycle where
    EX does not advance.
- **Fixes:** the tail of family A:
  `mem_exc`/`mem_stall` → `csr_we` → `csr_illegal` → `ex_illegal` →
  `fpu_req`/`muldiv_req` → FPU or M result → `exmem_result_q`
  (68 levels). Also the `vtype` → `csr_we` → FPU done → `ex_hold`
  path. It removes A's FPU, mul/div, CSR-register and
  `exmem_result_q` sinks, about 4.3k endpoints.
- **Expected:** A's worst path moves to its D$-enable, `pc_r` and
  global-CE sinks. WNS ≈ −3.75.
- **Cycles:** none.
- **Checks:**
  - Simulation: new and old CSR `illegal` agree whenever `ex_advance`;
    the decode classes are disjoint.
  - Tests: `rv64mi-p-csr` and the illegal-CSR tests, ACT Zicsr/priv,
    FP illegal (FS=Off, bad `frm`), `trap_younger_csr`,
    `priv_directed`, `fp_stall_directed`, `md_directed`.

### Step 2: parallel PMP priority

- **Change** (`sigil_csr`): `pmp_check` is a serial 16-entry priority
  loop today. Under `FPGA_TIMING`:
  - per-entry match bits are computed in parallel;
  - the lowest index wins by prefix-OR;
  - the permission bits are combined by AND-OR;
  - TOR reuses entry i−1's `a < pmpaddr` compare, so each port needs
    16 magnitude comparators instead of 32 [P3];
  - this applies to all three ports: A (fetch), B (data) and C
    (walker).
- **Fixes:** the PMP part of A, B, D and F. P3 measured that priority
  chain at 6 LUTs (≈1.9 ns) on B; the parallel form is about 2
  levels.
- **Measured (iteration 1):** the priority mask and the AND-OR must be
  written as vector reductions (`hit[i] && no lower match`,
  `|(first & perm)`). A first version that accumulated the verdict in
  a loop synthesized back into a chain and was slower than the serial
  `pmp_check` (2.6 ns against 2.1 ns from PA to verdict).
- **Expected:** WNS ≈ −2.8 ± 0.4 (A, B).
- **Cycles:** none.
- **Checks:**
  - Simulation: parallel equals serial on all three ports every cycle.
  - A miter of old against new `pmp_check` (SBY/eqy, or 10⁶ random
    vectors in Verilator).
  - Tests: ACT PMP, `trap_pa_load`, `trap_pa_fetch`, Linux boot.

### Step 3: one-hot TLB lookup

- **Change** (`sigil_mmu`): the I-port, D-port and fill-exist lookups
  are restructured as follows:
  - per-entry match bits;
  - a priority mask that keeps today's highest-index-wins rule;
  - an AND-OR select of `ppn`/`level`/`napot`;
  - per-entry `perm_ok`/`g_perm_ok`/A/D checks in parallel, selected
    by the same one-hot.
  - The outputs are the same as `find_entry` + `tlb_q[f]` +
    `perm_ok`.
- **Fixes:** the CAM part of A, B and C. CAM plus select costs
  4.6–4.9 ns today; the target is about 3.5–4 ns.
- **Measured (iteration 1):** as in step 2, the select must be a
  per-bit reduction `|(sel & column)`; the accumulating loop became a
  10+ LUT OR chain (VA → PA 6.1 ns, WNS −5.609). The fill-target
  lookup stays `find_entry` until step 8. With the reduction form, VA
  → PA is 4.6 ns (`base`) and 3.9 ns (`iter`).
- **Expected:** WNS ≈ −2.0 ± 0.5. It is limited by A, B and G1 (G1 is
  about −2.0 after the flow change).
- **Cycles:** none.
- **Checks:**
  - Simulation: every lookup output equals the `find_entry` form,
    every cycle.
  - `mmu_tb` (and `_fpga`).
  - Tests: `vm_directed`, `vm_sfence_cache_directed`, `hyp_directed`,
    riscv-tests `-v-`, ACT Sv39, Linux boot.

### Step 4: EX operand and result network

- **Change** (`sigil_core`, all cycle-neutral):
  - Registered one-hot forwarding selects for rs1, rs2, frs1, frs2
    and frs3.
    - They are computed at the ID→EX edge from the next-state
      pipeline contents, under the same update conditions as the
      pipeline registers: `ex_hold` refresh, `stall`, `flush`,
      `irq_inject` and the `mem_stall` hold.
    - The late `!exmem_exc_q`/`!memwb_exc_q` qualifiers stay as a
      single AND with the registered bits.
  - Separate low-fanout operand copies for the AGU, ALU/Bext, branch
    compare, store/stride/CSR/vset and M/FPU. `ex_rs2` has fanout 660
    today.
  - JAL/JALR link (pc+2/4) precomputed in ID. This removes the 64-bit
    CARRY8 chain that synthesis merged into the result mux.
  - The EX result becomes an AND-OR over one-hot class selects
    decoded in ID.
    - The decode keeps today's priority, because `vset` also sets
      `vec` (sigil_decoder.sv:628–629) [J-ISA].
    - `fp_op` enters last [P3].
  - A dedicated 3-bit rs1+imm misalignment adder replaces the use of
    the ALU result. P3 measured misalign → `exmem_tval_q` at −0.709
    in E1.
- **Fixes:**
  - G1 (−2.163) and G2 (−0.483);
  - `csr_rdata` → `exmem_result_q` (+0.003 today);
  - branch redirect → `pc_r` (+0.14);
  - the EX start of A (`alu_result` → `exmem_addr_q` at 8.61 ns).
- **Expected:** the G1 path drops to about 8.4 ns (+1.6) and G2 to
  +0.3 or better. WNS ≈ −1.9 (A, B).
- **Cycles:** none.
- **Checks:**
  - Simulation, every cycle:
    - precomputed selects equal the compare-based selects;
    - the decoded result selects are `$onehot0`, and `ex_result`
      equals the old mux;
    - the precomputed link and misalign bit equal the old values.
  - Tests: `pipeline_directed` with random bus latency,
    `md_directed`, `fp_stall_directed`, `fp_hold_cache_directed`,
    `irq_exc_race_directed`, `fp_irq_directed`, `trap_misalign`,
    `trap_store_misalign`.
  - riscv-tests rv64ui/um/uf/ud/uc, ACT, the CoreMark/Dhrystone
    result checks, and hazard-dense riscv-dv streams once #8 is
    available.
- **Contingency** (only if G1 is still below 0): move `aes64*`,
  `clmul*` and `xperm*` onto the EX multi-cycle handshake
  (`ex_mc_busy`), at +1 cycle each [P3].

### Step 5: registered data translation (`mt_q`)

The largest step. It lands as three commits, with the simulation
checks on from the first.

**5a. D-port lookup in EX, and `mt_q`**

- **AGU.** A dedicated AGU computes `ex_rs1_agu + idex_imm_q`. This
  equals `alu_result` for every memory op: the decoder uses `ALU_ADD`
  with `alu_src_imm`, and `imm = 0` for AMO/LR/SC/HLV and the vector
  base.
- **Lookup in EX.** The D-port lookup moves to EX with EX's context:
  `idex_ctrl_q.hlv`/`hlvx`/`mem_write`, `eff_priv`/`virt`, the
  satp/vsatp mux, SUM/MXR.
  - The result {`pa[55:12]`, `ok`, `fault`, `page`, `guest`, `gpa`,
    `miss`} is captured in `mt_q` at the EX→MEM edge.
  - `mt_valid` is set only if the port served EX in that cycle and no
    TLB write or flush lands on that edge.
- **MEM reads `mt_q`.** MEM uses `mt_q` everywhere it used `mmu_d_*`:
  - PMP port B and the 56-bit PA check;
  - `dreq_addr`;
  - the LR/SC `res_pa` and `sc_success`, and `store_end`;
  - the cause, tval and gpa;
  - `mem_stall`.
- **Why this is safe** [J-ISA]. Translation context changes only in
  three ways:
  - at the EX→MEM edge of an older instruction (`csr_we`);
  - by xRET/SFENCE/HFENCE in EX, which flush younger instructions;
  - by a trap at WB, which also flushes.
  - The only CSR write from MEM (`fp_dirty_mem`) touches FS only.

**5b. Replay and the walker request port**

- **D-port input select, from flops only:**
  - the MEM VA while MEM is parked (`mt_q.miss` or `!mt_valid`,
    until the replay lookup is captured);
  - the VLS VA in the VLS phases (5c);
  - otherwise the EX AGU.
- **Replay.** While MEM is parked, `mt_q` reloads every cycle from the
  lookup of the MEM VA.
  - After a fill, the next lookup hits.
  - After a walk fault, the recorded `wf` still matches, because the
    port still presents the faulting VA.
  - Cost: +1 cycle per data walk compared with today.
- **Registered walk-request port** in `sigil_mmu`: {`va`, `acc`,
  `priv`, `virt`, `d_satp`/ASID, VMID, root PTE}, loaded from MEM
  flops.
  - Data walks, and data-miss preemption of a fetch walk, start from
    `mt_q.miss && data_access && !trap_fire`.
  - That trigger is masked for one cycle after any TLB write, `wf`
    set, flush or abort, so a stale miss never starts a duplicate
    walk.
  - Walk start no longer runs combinationally through the CAM, which
    fixes C.

**5c. Vector LS**

- **Port sharing.** The same D-port CAM serves VLS element addresses,
  selected from registered state:
  `vls_is && ((ph == RD && vls_in_range) || ph == XL)`. The port
  therefore always serves EX in the cycle a VLS finishes.
- **Unit-stride, strided, segment, whole-register and mask forms.**
  The element VA comes from `vls_ea_q`/`exmem_addr_q` plus the field
  offset. It is looked up in `VLS_RD` and held through `VLS_RW` into
  `VLS_ACC`, at 0 extra cycles.
- **Indexed forms.** A new `VLS_XL` phase after `VLS_RW` takes the
  index from the VRF output register, at +1 cycle per active element.
  A later index prefetch on the idle VRF port A, during element i's
  ACC, could remove that cycle.

**Step 5 as a whole**

- **Fixes:** A (16,374 endpoints) and C (1,859).
- **Expected:**
  - MEM side: `mt_q` → parallel PMP → consumers ≈ 6.5–7 ns (+3).
  - EX port: operand copy ~1.0 + AGU ~0.8 + one-hot CAM ~3.5–4 +
    setup ≈ 6–7 ns (+3).
  - WNS ≈ −1.6 (B). About 2–3k endpoints still failing.
- **Cycles:**
  - 0 on D-TLB hits and on faults;
  - +1 per data walk;
  - +1 per active indexed VLS element;
  - +1 in the rare case where a TLB write lands on the `mt_q` capture
    edge.
- **Checks:**
  - Simulation:
    - (i) the AGU equals `alu_result` on every memory op;
    - (ii) whenever MEM uses `mt_q`, it equals the `origin/main`
      lookup of the MEM VA in MEM's context, unless a TLB write or
      flush happened since capture. This shadow lookup reads the
      walk-request port inputs.
    - (iii) `mt_q` is captured on an EX→MEM advance only when the port
      served EX;
    - (iv) a data walk starts only when `data_access && !trap_fire`,
      so A/D bits are never set speculatively;
    - (v) satp, vsatp, hgatp, `mstatus` MPRV/MPP/MPV/SUM/MXR,
      `hstatus.SPVP` and `vsstatus` are never written while EX/MEM
      holds a memory op whose `mt_q` came from the EX lookup.
  - Directed tests:
    - `vm_directed` (A/D), `vm_sfence_cache_directed`,
      `ptw_drop_directed`;
    - `hyp_directed` (HLV/HSV/HLVX, two-stage);
    - `trap_pa_load`, `trap_misalign`, `trap_store_misalign`,
      `trap_younger_store`;
    - `amo_directed`, `amo_cache_directed`, `mmio_bypass_directed`;
    - `vec_trap_directed` (fault-only-first, `vstart`), `vec_directed`;
    - `vm_ctx_directed`.
  - Suites: riscv-tests `rv64*-v-*`; ACT priv/Sv39/PMP/misaligned/A;
    vector ACT; Linux boot; KVM smoke.
- **Measured (iteration 2, `ab643d3` + `7ab4af3`):**
  - As built, `mt_q` lives in `sigil_mmu` (`g_dreg`): the core drives a
    new `dl_*` lookup port (EX or MEM, select from flops) and loads it
    with `dl_ld`; the MMU's `d_*` outputs become the register, so every
    MEM consumer keeps its code. The `d_*` inputs stay MEM's access and
    feed the walker unchanged; a data walk starts from a live miss in
    `mt_q` (the registered walk request).
  - `chg_q` (a walker grant, flush, abort or data G-stage width fault
    on the last edge) invalidates the capture for one cycle; MEM then
    replays. No TLB update can land while MEM's own access is in
    flight, so the replay never abandons an issued access (`a_mem_kept`).
  - Indexed elements: the RD/RW capture is marked not valid
    (`dl_vld`), so ACC replays once; no separate `VLS_XL` phase.
  - A misaligned element can now be seen while its translation is
    still pending. Main's sequencer resets on `vls_fault` even while
    MEM stalls (it restarts at element 0); with the replay that
    never ended (`vec_trap_directed` test 3), so under `FPGA_TIMING`
    the sequence ends on a fault or trim only once the translation
    resolves (`vls_end`).
  - F0 `iter` at `ab643d3` (step 5 alone): **WNS +0.055 ns**, 0
    failing; the worst paths are all fetch (`pc_r` → `pc_r`, I$ tag
    WE), then VLS `vl` → port select → CAM → `mt_q` (+0.39) and PMP →
    D$ BRAM enable (+0.40).
- **Contingency** if the EX-port path fails:
  1. A carry-free (sum-addressed) VPN compare of rs1+imm against each
     entry, which takes the 64-bit AGU out of the CAM path.
  2. Otherwise P3's 1-entry reuse registers: lookup in MEM,
     registered, +1 per page or access-type change.

### Step 6: speculative cache array reads

- **Change** (`sigil_icache`, `sigil_dcache`): in `S_IDLE`:
  - the tag/data read enables no longer depend on `req_valid` or
    `req_cacheable`;
  - `r_addr_q` loads every `S_IDLE` cycle, and in the D$ so do
    `r_op`/`r_wdata`/`r_be`/`sc_*`;
  - only `state_q` still depends on `req_valid`.
  - Reads have no side effects, and `S_LOOKUP` sees the read taken at
    the accept edge.
- **Fixes:**
  - F (−0.604: walker `pte_addr_q` → `dreq_valid` → D$ tag WE / BRAM
    enables);
  - the I$ BRAM ENARDEN, tag WE and `rd_q` CE sinks of B and D;
  - the D$ enable sinks of A.
- **Expected:** F at +1 or better. WNS ≈ −1.4. B's remaining IF/ID CE
  and `pc_r` sinks are now level with H, E and I.
- **Cycles:** none.
- **Checks:**
  - Simulation: the `S_LOOKUP` data equals a read of the accepted
    request.
  - `dcache_tb`/`icache_tb` (and `_fpga`), the `srammacro` `fpga`
    family, and every `core_tb` directed test with random bus latency.
  - Tests: `amo_cache_directed`, `smc_fencei_directed`,
    `mmio_bypass_directed`.
- **If the D$ request registers still fail:** select
  `dreq_addr`/`op`/`be` with a translation-only "MEM claims the port"
  term (`data_access && mt_q.ok`, or FENCE.I) [P3]. The walker then
  waits one cycle while MEM holds a PMP-denied access.
- **Measured (iteration 2, `d7e8e41`):** built together with that
  payload select (`mem_port_sel`), since the D$ BRAM address also
  came through `mem_issue`. F0 `iter` with steps 5–7: **WNS +0.614
  ns** (+0.401 without step 6); the D$/I$ enable sinks leave the
  near-critical list. `dcache_tb_fpga`/`icache_tb_fpga` run in
  `srammacro`.

### Step 7: fetch page register (`it_q`)

- **Change** (`sigil_core`, `sigil_mmu`):
  - **What `it_q` holds.** `it_q` {`valid`, `va[63:12]`, `pa[55:12]`,
    `guest`} holds the last OK fetch translation. It reloads from the
    I-port lookup of `fetch_va` when that lookup is OK, and it never
    holds a fault.
  - **IF path:**
    - `page_hit = it_q.valid && fetch_va[63:12] == it_q.vpn`;
    - PA = `if_trans ? {it_q.pa, fetch_va[11:0]} : fetch_va`;
    - `if_trans` comes from CSR/privilege flops only. The MMU exports
      it at about 2 levels, and it is replicated.
    - Fetch PMP (parallel) runs on that PA.
    - The I-TLB CAM, the ASID/VMID compares and the `virt_q` mode
      logic leave the `fetch_stall` path.
  - **Page miss.** IF stalls one cycle while the I-port lookup is
    registered.
    - A fault from that lookup goes into a one-shot record {`va`,
      `page`, `guest`, `gpa`}. It is consumed as the fetch fault the
      next cycle and cleared on use or redirect [J-ISA, P2].
    - An I-TLB miss starts the fetch walk from the registered miss,
      at +1 per I-walk.
  - **Invalidation.** `it_q` is cleared on `trap_take`, xRET,
    SFENCE/HFENCE fire, and `csr_we` to satp/vsatp/hgatp.
    - Fetch permissions ignore SUM/MXR, and MPRV does not apply to
      fetch [J-ISA].
    - A TLB fill does not invalidate it: a cached OK translation
      stays legal until SFENCE.
  - **Straddled parcels.** A 32-bit parcel that straddles a page still
    translates its second half separately, with tval naming it.
- **Fixes:** B (−3.857), D (−2.307), and the `vsatp` → I-TLB →
  `pc_r` path that E1 exposed (−1.55).
- **Expected:**
  - Fetch path: `fetch_va` 2.1 → page compare/PA mux ~0.6 → parallel
    PMP ~1.5–2 → `fetch_stall` → IF/ID CE, `pc_r`, I$ ≈ 7–7.5 ns
    (+2.5).
  - WNS ≈ −1.4 (H, I, E).
- **Cycles** (translated fetch only; bare and M-mode are 0):
  - 0 on the same page;
  - +1 per page change (a sequential crossing, or a cross-page
    redirect until step 16);
  - +1 after a trap, xRET, SFENCE/HFENCE or satp/vsatp/hgatp write;
  - +1 per I-walk;
  - +1 on a fetch page fault.
- **Checks:**
  - Simulation:
    - (i) whenever IF uses `it_q` and the full I-TLB lookup of
      `fetch_va` is OK, the PA and guest bits are equal, unless `it_q`
      was loaded before the last TLB change (a re-walk may re-read a
      PTE changed without SFENCE; either translation is legal);
    - (ii) `it_q` is invalid in the cycle after any satp, vsatp or
      hgatp write, trap, xRET or SFENCE/HFENCE [P2, J-ISA].
  - Tests: `vm_directed`, `hyp_directed`, `trap_pa_fetch`,
    `smc_fencei_directed`, `irq_exc_race_directed`, and the
    straddle cases in `vm_ctx_directed`.
  - Suites: ACT C, riscv-tests `-v-`, Linux boot, KVM smoke.
- **Measured (iteration 2, `4e2b8d8`):** `it_q`, the one-shot fault
  record (`ir_q`, which also carries misses for the walk start) and
  the invalidation live in `sigil_mmu` (`g_ireg`); no core change.
  Instead of explicit invalidation on satp/vsatp/hgatp writes and
  xRET, `it_q` and `ir_q` are tagged with the TLB's own match key
  (privilege, V, satp/vsatp mode and ASID, hgatp mode and VMID) and
  dropped on SFENCE and traps. F0 `iter` with steps 5 and 7: **WNS
  +0.401 ns**, 6 endpoints under +0.5 ns (all VLS `vl` → `mt_q`); the
  fetch paths of step 5's run are gone from the list.
- **Contingency** if B or D still fails: a registered `fetch_va`
  loaded from `pc_d` [P2]. Its D input is
  `straddle_enter ? (pc_q + 2 precomputed from flops) : {pc_d[63:2], 2'b00}`,
  so no adder sits after `pc_d` (`pc_r` slack is +0.14 today)
  [J-timing].

### Step 8: TLB fill select and PTE capture

- **Change** (`sigil_mmu`):
  - `fill_idx_q = exist_f hit ? index : fill_ptr_q`, registered every
    cycle from `req_*`. `req_va_q` is stable for the whole walk, only
    this walker writes the TLB, and a flush aborts the walk. So at
    every fill the registered value equals today's [P3].
  - `pte_q`/`g_pte_q` capture `walk_rdata` every cycle while the
    walk's request is pending. They are data-only registers, so their
    CE no longer depends on the grant [P1].
- **Fixes:**
  - E (−1.325, 3,931 endpoints: D$ hit → PTE checks → CE of the 32 ×
    ~140-bit `tlb_q`);
  - the walker-state residuals (`fill_ptr_q` −0.636, `g_gpa_q`
    −0.420, `wf_gpa_q` −0.324).
- **Expected:** E at about 0 to +0.5. P3's E2 measured E at −0.321 and
  C at −0.445 before this change. WNS ≈ −1.3 (H, I).
- **Cycles:** none.
- **Checks:**
  - Simulation: `fill_idx_q == fill_idx` at every fill.
  - `mmu_tb` (and `_fpga`).
  - Tests: `ptw_drop_directed`, `vm_directed`,
    `vm_sfence_cache_directed`, `hyp_directed`, and the SFENCE race
    case in `vm_ctx_directed`; Linux boot.
- **Fallbacks** if E is still below 0:
  1. `fill_q`: register {`valid`, one-hot select, entry} at the grant
     and write `tlb_q` one cycle later from flops. A flush clears
     `fill_q` and wins over its write, as a flush wins over the fill
     today (sigil_mmu.sv:518). The walk completes one cycle later,
     so +1 per walk [P1, J-ISA].
  2. The walker consumes a registered D$ response, at +1 per PTE read
     [P2, P3].

### Step 9: vector → FPU operand path (H)

- **Change**, in order, stopping as soon as H ≥ 0:
  1. Flow: `phys_opt_design -dsp_register_opt`, or keep
     `ua_q`/`ub_q` in fabric (no AREG/BREG absorption). The long
     `u_vec` → FPU route then no longer ends on DSP pins [P3, P1].
  2. RTL, cycle-neutral [P1]: retime the vector unit's
     `fp_a`/`b`/`c`/`op`/`fmt`/`rm`/`aux` selection into flops loaded
     on the same edges as their S2/fa/fb/acc sources, so the
     `vfpu_*` signals leave `u_vec` straight from flops.
  3. Fallback [P2]: register the vector FPU request
     (`vfpu_req && vfpu_req_q`), at +1 per vector FP sub-step. This
     is safe because `vfpu_req` drops for at least one cycle between
     sub-steps (`fr_v_q`).
- **Fixes:** H (−1.433, 414 endpoints, 9.5 ns of routing).
- **Expected:** H at +0.3 to +1. P3's E2 measured −0.011 with the
  flow and pblock alone. WNS ≈ −1.27 (I).
- **Cycles:** 0 for options 1 and 2; +1 per vector FP sub-step for
  option 3.
- **Checks:**
  - Simulation: `fp_*_q == fp_*` whenever `fpu_req_o` [J-ISA], plus
    the existing `fp_eval` cross-checks in `sigil_vec`/`sigil_fpu`.
  - `vec_tb` in the `fpga` family, `fpvec_directed`, vector ACT FP
    (162), TestFloat, `fp_irq_directed`.

### Step 10: CSR read-select pre-decode (I)

- **Change** (`sigil_core`, `sigil_csr`) [P3]:
  - ID decodes `ifid_instr_q[31:20]` into one-hot CSR read selects.
  - They are registered with ID/EX as `idex_csr_sel_q` (about 90 FFs,
    loaded wherever `idex_imm_q` is).
  - The read mux becomes an AND-OR over those selects, which
    `phys_opt` can replicate.
- **Fixes:**
  - I (−1.268: `idex_imm_q` → `csr_rdata` → `csr_wdata` → CSR
    registers), including the hidden `mtinst` layer (−0.419);
  - margin on `csr_rdata` → `exmem_result_q`.
- **Expected:** I at +0.1 to +0.5 with `iter`, more with `closure`.
  WNS ≈ −1.0 (J).
- **Cycles:** none.
- **Checks:**
  - Simulation: the select equals `decode(idex_imm_q[11:0])` every
    cycle.
  - `csr_tb`, `irq_seip_rmw`, `irq_mip_rmw_variants`,
    `counter_time_directed`, ACT Zicsr/priv, rv64mi/si.
- **Fallback** [P1]: distributed RMW.
  - Each CSR computes op(its own view, src); `mip` uses its software
    SEIP/STIP bits, as `rmw_rdata` does today.
  - The 80-way read mux then feeds only the EX result.
  - A simulation check compares every CSR register's next value with
    the old path [J-ISA].
  - Not used: the registered CSR write port [P2].

### Step 11: load data → VRF (J)

- **Change** (`sigil_core`) [P1]: the VLS write data becomes a single
  byte rotate by a registered amount,
  `el_off(vls_i, eew) − addr[2:0]`, taken from registered VLS and
  `mt_q` state. `wbe` does the masking.
- **Fixes:** J (−1.033: D$ data → way select → `>> addr` → mask →
  `<< el_off` → VRF DIN / v0 shadow / bypass).
- **Expected:** J at +0.3 to +0.6; E2 already passes J. WNS ≈ −0.95
  (K).
- **Cycles:** none.
- **Checks:**
  - Simulation: the written bytes equal the old `wd` under `wbe`. The
    VRF bypass is full-word only, and the v0 shadow honours `wbe`
    [J-ISA].
  - `vec_tb`, `vec_directed`, `vec_trap_directed`, vector ACT
    load/store.
- **Fallbacks:**
  - `vls_wb_q` [P2], cycle-neutral. Element i−1's write must commit
    even in the cycle element i raises `mem_exc`/`vls_fault` or trims
    `vl`. RD waits one cycle on a row collision with the pending write
    (indexed load with vd == vs2) [J-ISA].
  - Alternatively, a one-hot late hit-way select in the D$.

### Step 12: vector element datapath (K1, K2)

- **Change** (`sigil_vec`):
  - **K1** [P1, P3]: register sign-extended operands in S1 (`a_s`,
    `b_s`). Saturating add/sub/average/clip work at SEW+1 bits, with
    overflow taken from the carry and sign bits instead of 128-bit
    chains. The `r_int` class selects are one-hot and pre-decoded.
  - **K2** [P2]: a flop precomputes "S2 frees next cycle" from the
    mul/div/estimate step counters (`fr_v_q` already registers FP
    completion). `s0_issue` is then about 2 levels from flops.
- **Fixes:**
  - K1: `aw_q` → sext → saturate → `w_d_q` (−0.968, 36 levels).
  - K2: `sew_q` → `s2_done` → `s1_adv` → `s0_issue` → VRF EN /
    `byp_data_q` CE (−0.564, about 136 endpoints).
- **Expected:** K at +0.5 to +1. WNS ≈ −0.5 to −0.8 (L).
- **Cycles:** none.
- **Checks:**
  - Simulation: the S2 result equals the old result.
  - `vec_tb` with `vxrm`/`vxsat` sweeps, vector ACT integer (1872),
    Ara rv64uv.
- **Fallback, last resort:** 2-cycle fixed-point S2 elements, at +1
  per element for that class.

### Step 13: SHA-512 message schedule (L)

- **Change** (`sha512_block`) [P1, P2, P3]:
  - Replace `w[80]` and its four round-indexed 80:1 muxes with a
    16-word shift window using fixed taps at t−2, t−7, t−15 and t−16.
  - `w_cur` comes from a flop.
  - K[t]+W[t] (+h) is precomputed one round ahead, so t1 becomes a
    3-operand add.
  - Blocks still take 80 rounds. `FPGA_TIMING` arrives as a parameter
    through the crypto chain (bridge → top → hash stream → block).
- **Fixes:** L (−0.508; −0.78 in P3's E1/E2, where L sits outside the
  pblock). The `closure` strategy adds a hash pblock.
- **Expected:** L at about +1.5, and 4,096 fewer FFs. WNS ≈ −0.3 to 0,
  set by residues and newly exposed layers.
- **Cycles:** none. Fallback: +1 finalization cycle per block for the
  digest add [P2].
- **Checks:** `sha512_tb -GFPGA_TIMING=1`, the `make test` KATs,
  `crypto_soc_test` in `soc_rtl_tb` (`fpga` family), and the hash
  stream firmware.

### Step 14: closure

- **Builds.** Run the `closure` strategy at the step-13 SHA, plus a
  sweep of the pblock (`X1Y8:X3Y10`) with at most 3 variants in
  parallel.
- **Remaining layers.** Run `f0_timing_reports.tcl` with all cuts to
  expose them. Fix with replication or `max_fanout` first, then with
  the contingencies above.
- **Watch list**, each targeted at +0.3 ns or better in `closure`:
  - D$ response → global CE (+2.75 today);
  - I$ hit → IF/ID (+0.86);
  - `csr_rdata` → `exmem_result_q` (+0.003);
  - FPU `d_q` → `fp_round` → result (G2);
  - the EX-port and VLS CAM paths;
  - the replay select;
  - the `it_q` page compare.
- **Target:** post-route WNS ≥ +0.1 ns (aim for +0.2 to +0.4) at
  10 ns with hold clean, in `closure`.
  - Record the `iter` WNS without the pblock next to it. That is the
    margin the CL floorplan has to keep.
- **G2 FPU fallback** if needed: register the `S_ROUND` result in
  `sigil_fpu`, at +1 per rounded scalar or vector FP op [P2].

### Step 15: full gates and evidence, both settings

Run everything below twice: in the default setting, and in the `fpga`
setting (`SIGIL_VRF_OREG` + `SIGIL_FPGA_TIMING`).

- **Lint:** `make lint` with Verilator 5.048 and 5.020.
- **Unit and core tests:** `make test` (including the `_fpga` unit
  TBs and `sha512_tb -GFPGA_TIMING=1`) and `make core-test` (every
  directed test, random bus latency, `srammacro` all families).
- **ISA suites:** `make riscv-tests` with the `-v-` variants; ACT on
  the core (`sim/run_act_core_par.sh`); vector ACT integer and FP;
  TestFloat; riscv-dv (#8) where available.
- **System:** crypto SoC firmware; the OpenSBI + Linux RTL boot to
  `SIGIL_LINUX_BOOT_OK`; KVM smoke.
- **ASIC invariance:** `scripts/fpga_timing_equiv.sh` clean for
  default, FAKERAM45 and SKY130. The perf-harness default, sky130,
  oreg and vrforeg cycle counts must be bit-identical to the `main`
  baseline.
- **Bare-metal CPI gate** (once #56 lands) [P3, J-perf]: perf-harness
  cycle counts in `fpga` equal `vrforeg`, except for +1 per active
  indexed vector element, which is counted from the harness counters.
- **Translated CPI:** Linux boot cycle count, `fpga` against
  `vrforeg`. Report the delta.
- **Evidence:** `docs/evidence/fpga-timing-53-final-2026-10-2x.md` plus
  a README entry, and a `docs/CORE.md` section on `FPGA_TIMING`
  behaviour.
- **Review round 2 (fixes, FPGA_TIMING only).** Three ISA
  divergences from `main`, found by directed review tests:
  - An EX capture (`dl_mem` = 0) matched the walk-fault record by VA
    alone, so an HLV/HSV/HLVX right after a trimmed `vle*ff` of the
    same VA took a spurious page fault: `main` drops the record
    before that access reaches MEM. Such a capture is now not valid
    and MEM replays its own lookup (+1 cycle, rare). The `mt_q`
    simulation check exempts only MEM's own captures whose record
    dropped afterwards.
  - The fetch guest flag left `g_ireg` without the fault, so a fetch
    access fault right after a fetch guest-page fault lookup wrote a
    stale GPA to `mtval2`/`htval`. It is now gated with the fault.
  - The `it_q` simulation check fired on a legal stale translation
    (a code page remapped without SFENCE, then re-walked for a D-bit
    update); it now skips the cycle after a TLB change until `it_q`
    reloads.
  - Tests: the review's directed tests that pass on `main` (21
    programs; `vm_irq_directed` at 152 timer-IRQ offsets) run in
    `sim/run_directed.sh`.

### Step 16 (optional, after closure): redirect port for translated fetch

- **Change** [P1]:
  - An R-port CAM looks up `redirect_pc`, and its result is captured
    in `it_tgt_q`.
  - A registered `redirected_q` selects it the next cycle. `flush`
    arrives at 8.8 ns, which is too late to steer a CAM result.
  - It is used only when `pc_r` actually takes the redirect: the same
    `!freeze`, `!mem_stall` and `!trap_take` conditions.
- **Effect:** cross-page EX redirects (branch, JAL, JALR, FENCE.I) cost
  0 cycles in translated mode.
- **Lands only if** WNS stays ≥ +0.1 ns and the Linux boot cycle count
  shows the gain.

## Summary

All WNS values are estimates in ns, except the measured results in
the Status column.

| Step | Change | Families | Cycle cost with FPGA_TIMING | WNS after (`iter`) | Limited by | Status |
|---|---|---|---|---:|---|---|
| 0 | plumbing, flow, inventory | all (flow) | 0 | −3.9 ± 0.3 (`closure` ≈ −3.2) | A | in part (iteration 1) |
| 1 | CSR write intent, FPU/M request | A tail | 0 | ≈ −3.75 | A | done: −4.052 (`base`) |
| 2 | parallel PMP | A, B, D, F | 0 | ≈ −2.8 | A, B | done, with step 3 |
| 3 | one-hot TLB lookup | A, B, C | 0 | ≈ −2.0 | A, B, G1 | done: −3.913 (`base`), −2.298 (`iter`) |
| 4 | EX operand/result network | G1, G2 | 0 | ≈ −1.9 | A, B | planned (not needed for F0) |
| 5 | `mt_q`, replay, walk port, VLS port | A, C | +1 per data walk, +1 per indexed VLS element | ≈ −1.6 | B | done: +0.055 (`iter`, steps 1–3 + 5) |
| 6 | speculative cache reads | F, B/D/A enable sinks | 0 | ≈ −1.4 | B, H, E, I | done: +0.614 (`iter`, steps 1–3 + 5–7) |
| 7 | `it_q` fetch page register | B, D | +1 per translated fetch page change | ≈ −1.4 | H, I, E | done: +0.401 (`iter`, steps 1–3 + 5 + 7) |
| 8 | `fill_idx_q`, PTE capture | E, C residual | 0 | ≈ −1.3 | H, I | planned |
| 9 | H (flow, then retiming) | H | 0 (fallback +1 per vector FP sub-step) | ≈ −1.27 | I | planned |
| 10 | CSR read pre-decode | I | 0 | ≈ −1.0 | J | planned |
| 11 | VLS write-data rotate | J | 0 | ≈ −0.95 | K | planned |
| 12 | K1 + K2 | K | 0 | ≈ −0.5 to −0.8 | L | planned |
| 13 | SHA-512 window | L | 0 | ≈ −0.3 to 0 | exposed layers | planned |
| 14 | `closure` strategy + residual fixes | residual | 0 | ≥ +0.1 (`closure`) | none | planned |
| 15 | full gates, evidence | | | | | round 1 at `116c4a4`: all pass but the cell-count check; review round 2 at `08c607a`: all pass, F0 +0.799 |
| 16 | redirect port (optional) | CPI | removes the cross-page redirect cost | stays ≥ +0.1 | | optional |

## CPI impact

**FPGA_TIMING off** (default, sky130, nangate45): identical to
`origin/main`.

**FPGA_TIMING on**, by instruction class:

| Class | Extra cycles |
|---|---|
| Integer ALU, branches, JAL/JALR, M, CSR, F/D, B/Zbk/Zkn, vector arithmetic, SHA-512 engine | 0 |
| Scalar load/store/AMO/LR/SC/HLV/HSV, FP load/store: D-TLB hit or fault | 0 |
| Same, D-TLB miss | +1 per data walk (replay) |
| Vector LS: unit-stride, strided, segment, whole-register, mask | 0 |
| Vector LS: indexed | +1 per active element (4 → 5 cycles; an index prefetch could recover it) |
| Fetch, bare or M-mode | 0 |
| Fetch, translated | 0 on the same page. +1 per page change, including cross-page redirects until step 16. +1 after trap, xRET, SFENCE/HFENCE or satp/vsatp/hgatp write. +1 per I-walk. +1 on a fetch page fault. |
| Rare | +1 when a TLB write lands on the `mt_q` capture edge. +1 when EX's access matches the recorded data walk fault (MEM replays its own lookup; review round 2) |

**Fallback costs**, each measured and documented if it is used:

| Fallback | Cost |
|---|---|
| Slow Bext as 2-cycle ops (G1) | +1 each |
| `fill_q` (E) | +1 per walk |
| PTE response register (E) | +1 per PTE read |
| Vector FPU request register (H) | +1 per vector FP sub-step |
| 2-cycle fixed-point S2 (K) | +1 per element of that class |
| SHA finalization cycle (L) | +1 per block |
| FPU `S_ROUND` register (G2) | +1 per rounded FP op |

**Expected aggregate:**

- 0 on the bare-metal perf harness, apart from indexed vector
  accesses.
- About +0.5–2 % on Linux before step 16, and under 0.2 % with it.
- Clock: 70.3 → 100 MHz (×1.42).

**Measured (iteration 2, `d7e8e41`, steps 1–3 and 5–7):** with
random bus latency, every directed test and riscv-tests ELF runs
cycle-identical to `main` in the default setting. In the `fpga`
setting against `main` `vrforeg`: the riscv-tests `-p-` ELFs are
identical except `rv64si-p-dirty` (+8, it turns paging on), and the
directed tests are identical except `vm_directed` +26 (+0.13 %),
`hyp_directed` +33 (+0.87 %), `vec_directed` +10 (indexed elements)
and `ptw_drop_directed` +231 (+0.61 %). The Linux boot was not
measured: in both settings the RTL `soc_tb` ran OpenSBI and was still
in the kernel's silent early phase after 30–46 min (a boot needs more
than 500M cycles; an earlier record measured about 17k cycles/s for
this model), so it was stopped.

## ASIC impact and promotion candidates

**ASIC impact.** None, by construction. The step-0 equivalence check
runs at every RTL step; since step 15 it covers `sigil_core` too
(hierarchical, both the default and SRAM_OREG configs). Generic Yosys
cell counts are not used as the identity test: they differ for
byte-identical RTL depending on what else is read. The flow changes
touch only `fpga/f0`. Nothing needs to rerun on the sky130 or nangate45
flows.

**Promotion candidates.** These are refactors that would also help
ASIC timing. Making any of them unconditional needs an owner decision
and new GDS runs.

- **The `mt_q` EX-port lookup (step 5).** The nangate45 worst path is
  family A: `vls_i_q` → `vls_index` → `mmu_d_pa` → D$ data macro, with
  0.74 ns slack at a `period_min` of 9.26 ns (see
  `evidence/soc-pnr-nangate45-11-2026-10-21`). It costs 0 cycles on
  hits.
- **Parallel PMP with shared TOR compares (step 2).**
- **One-hot TLB lookup (step 3).**
- **CSR legality from write intent, and FPU/M requests without
  `ex_illegal` (step 1).** A pure fix.
- **The EX network (step 4):** registered forwarding selects, operand
  copies, one-hot result select, precomputed link, misalignment
  adder.
- **CSR read pre-decode (step 10) and `fill_idx_q` (step 8).**
- **K1 and K2 (step 12).**
- **SHA-512 16-word window (step 13).** It is also an area win, with
  about 4,096 fewer flops on sky130.

**Not candidates:**

- speculative `S_IDLE` array reads (SRAM macro read power);
- `it_q` and the redirect port (area for little ASIC gain);
- every flow item.

## Follow-up IPC levers (outside #53)

- **A VIPT D$ probe in EX** with the VA index; index plus offset is
  under 4 KiB. The D$ hit freeze is 12.7 % of Dhrystone cycles
  (perf56) [P2].
- **Reusing the fetched word for a second RVC parcel.** The fetch gap
  is 40.6 % of cycles, at 1.45 fetches per instruction [P2].
- **Index prefetch for indexed VLS**, which removes `VLS_XL`.
- **Static load-use accounting.** P2's analysis script can do the CPI
  accounting once #56 lands.

## Inputs

- **Baseline reports.** `sigil-fpga-build2:/home/ubuntu/wt/53-main/build/f0-53-baseline-10ns/`.
- **P3's flow experiments E1/E2.** `sigil-fpga-build2:/home/ubuntu/tmp/d53impl/{e1,e2}/`.
  Each holds `post_route.dcp`, the full report set and the cut layers.
- **P1's read-only arrival-time probes.** On build2 under `/tmp/d53cpi`.
- **The three designs and three judgements.** Workflow journal
  `wf_13c4a2b5-fba` (design and judge results).
