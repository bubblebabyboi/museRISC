# In-house core (issue #18)

Clean-slate SystemVerilog RV64 core replacing the integrated
third-party CVA6+Ara. Target ISA: **RV64GCV** (the configuration the
CVA6+Ara evidence was gathered against), built and verified in stages.
Each stage lands only with its own C++ Verilator testbenches green and
coverage reported; ACT (riscv-arch-test) and Spike tandem runs — which
take far longer — are stage gates, not per-commit checks.

## Verification strategy

- **Per-module C++ Verilator testbenches** (`tb/cpp/`) with C++ golden
  models and randomized stimulus are the fast inner loop. Every new
  module ships with one; `sim/Makefile` builds with
  `--coverage-line --coverage-toggle` and reports merged coverage
  under `build/sim/coverage/`. Line coverage of `rtl/core/` from the
  committed tests is reported in evidence, never asserted by eye.
- **Directed self-checking assembly** (`sw/core-tests/`, riscv-tests
  style: nonzero exit = failing test number) runs on the core harness
  for end-to-end ISA semantics per stage.
- **Upstream suites as stage gates**: riscv-tests and ACT4 with a
  museRISC DUT config (reusing the flow proven on CVA6), Spike tandem
  once the core retires instructions observably.

## Stages

| Stage | Scope | Gate | Status |
|---|---|---|---|
| 1 | RV64I base integer, single-cycle, Harvard SRAM ports | unit TBs (ALU, decoder via directed asm), directed RV64I asm, coverage report | done |
| 2 | M extension + 5-stage pipeline (hazards, forwarding) behind the stage-1 module boundaries | directed M asm (incl. div/rem edges), stage-1 directed suite still green on the pipelined core | done |
| 3 | Privileged M/S/U, CSRs, traps/interrupts, Sv39+Svnapot MMU, PMP | riscv-tests `rv64ui/um` (needs CSR/trap state), ACT I/M + priv suites, Linux boot attempt | Done (riscv-tests 64/64, ACT 180/181 with 1 waiver; OpenSBI/Linux attempt blocked on A — needs stage 4, see evidence log) |
| 4 | A, F/D (IEEE-754, all rounding modes), Zba/Zbb/Zbc/Zbs, Zcb, Zicond, Zkn | ACT suites per extension, TestFloat vectors (flow exists) | **Done**: A + F/D + B/Zicond/Zkn (ACT 494/495). Zcb needs C (stage 5) |
| 5 | C (Zca/Zcb/Zcd) — fetch realignment | ACT C suites, misaligned-fetch probes | **Done**: decompressor + fetch realignment/page-straddle, IALIGN=16 (riscv-tests 123/123, ACT 543/544 with the same 1 waiver) |
| 6 | Linux/OpenSBI boot bring-up — harness CLINT/PLIC/UART/DTB models, OpenSBI + kernel boot (no new CPU extension; S-mode/Sv39 already verified) [#21](https://github.com/bubblebabyboi/museRISC/issues/21) | Boot log to init/shell recorded in `docs/evidence/`; riscv-tests + ACT gates stay green | **Done**: OpenSBI v1.9 + Linux 6.6 to embedded `/init` (`SOC TB PASS`, 508,905,040 cycles); riscv-tests 123/123 and ACT 543/544 stay green |
| 7 | H hypervisor — VS-mode, hypervisor CSRs, two-stage Sv39x4 translation (needed for KVM, **not** for single-level Linux) [#22](https://github.com/bubblebabyboi/museRISC/issues/22) | Own Verilator TBs + directed guest tests; KVM guest smoke (no ACT H suite exists in the pinned tree) | **Done**: 7a CSR/trap skeleton, 7b two-stage translation, 7c HLV/HSV/HLVX/HFENCE, 7d VS interrupts; Linux KVM creates a VM/vCPU and a 4-instruction guest exits via MMIO (`SOC TB PASS`, 502,972,620 cycles); riscv-tests 123/123 and ACT 543/544 stay green |
| 8 | Integer V (RVV 1.0 Zve32x/Zve64x), VLEN 512, ELEN 64 [#23](https://github.com/bubblebabyboi/museRISC/issues/23) | ACT vector suites via `sw/act4-core` (`scripts/build_act4_core.sh`) | **Done** (integer subset): ACT Vx/Vls 1872/1872 self-checking ELFs pass (43 tests not generated/selected, documented in evidence); FP vector (Zve32f/64f/64d) not implemented |

Priority order set 2026-10-14: Linux boot first, then H,
then V. Note on terminology: **V is the Vector (SIMD)
extension; H is the Hypervisor extension.** A normal OS
needs neither — it needs S-mode + Sv39, which stages 3–5
already provide with ACT evidence. The CLINT/PLIC/UART/DTB
+ OpenSBI work is part of stage 6 (the platform Linux boots
on), not a step after it.

Single-cycle in stage 1 was deliberate: ISA semantics (decoder,
ALU, load/store datapath) got verified with zero hazard noise, and
stage 2 reused the same modules inside a classic 5-stage pipeline
— full forwarding to EX (EX/MEM and MEM/WB) plus a WB→ID bypass,
one load-use bubble, all control transfers resolved in EX
(predict not-taken, two flushed slots), and exceptions carried to
WB so a trapping instruction and everything younger perform no
writes. The M-unit divider is combinational in stage 2 (a
correctness vehicle; an iterative divider with an EX stall
replaces it before any synthesis target). Pipeline performance
beyond correctness is not yet a goal at this stage.

## EX-stage multi-cycle units (fpu-multicycle)

The scalar FPU (`rtl/core/muserisc_fpu.sv`) is a multi-cycle
unit: the FP instruction stays in EX until the unit completes.
The handshake is generic so other EX units (an iterative
`muldiv` next) reuse it unchanged:

| Signal | Driver | Meaning |
|---|---|---|
| `req_i` | core | level: the instruction in EX uses this unit and is not already excepting (`idex_valid && uses_unit && !idex_exc && !ex_illegal`) |
| `done_o` | unit | `result_o`/`flags_o` valid this cycle; may be in the issue cycle (fast ops) |
| `ack_i` | core | `ex_advance`: EX moves to EX/MEM this cycle (`!trap_take && !freeze && !mem_stall && !ex_hold`), consuming the result |
| `kill_i` | core | `trap_take`; dropping `req_i` also squashes |

Core side (`muserisc_core.sv`):

- `ex_mc_busy = OR over units of (req && !done)`; `ex_hold =
  vec_wb_stall || ex_mc_busy`. While `ex_hold`, PC, IF/ID and
  ID/EX keep their contents, a bubble enters EX/MEM, and the
  older instructions in MEM/WB drain normally. `irq_inject` is
  suppressed, so an interrupt is taken on the next instruction
  boundary after the held op completes (precise, never mid-op).
- Held-EX operand refresh: every held cycle copies the
  forwarded `ex_rs1/rs2/frs1-3` back into ID/EX, because the
  producers keep draining through MEM/WB and would otherwise
  fall out of the forwarding window. (This also fixed a latent
  stale-operand bug on the pre-existing `vec_wb_stall` hold:
  `fp_stall_directed.S` test 4 fails on the previous core.)
- Side effects of the EX instruction (fflags accrual, FS dirty)
  commit only in its `done` cycle under the usual
  `!trap_fire && !mem_exc && !mem_stall` gating, so a squashed
  op leaves no architectural trace.
- The unit samples its operands and the resolved rounding mode
  when it accepts the op (idle and `req_i`), so later changes
  of the forwarding network or of `frm` cannot affect it; a
  `done` without `ack` (e.g. `mem_stall` from an older vector
  load) parks the result in a HOLD state until EX advances.
- Adding a unit: compute its `req`, OR `req && !done` into
  `ex_mc_busy`, drive `ack_i` from `ex_advance` and `kill_i`
  from `trap_take`, select its result into `ex_result`, and
  gate any EX-committed side effect with its `done`.

FPU structure: every operation is a chain of stage functions in
`muserisc_fpu_ops.svh` (unpack, special cases, align, add,
normalise, round; radix-2 restoring divide/sqrt steps; float/int
conversions). `muserisc_fpu` puts a register after each stage
and runs `FPU_DS_BITS` (= 2) divide/sqrt steps per cycle; the
vector unit calls `fp_eval`, which chains the very same
functions combinationally, so scalar and vector results are
identical by construction (simulation additionally asserts
every multi-cycle completion against `fp_eval`). Normalisation
uses log-depth leading-zero shifters; there are no
data-dependent loops. The vector FP path itself remains
combinational (out of scope for this change).

Latency (cycles the instruction occupies EX; 1 = no stall):

| Operation | Cycles |
|---|---|
| `fsgnj*`, `fmv.x.*`, `fmv.*.x` | 1 |
| `feq/flt/fle`, `fmin/fmax`, `fclass`, any special-operand shortcut (NaN/Inf, 0×Inf, x/0, 0/x, √±0, √−x) | 2 |
| `fcvt.int.fp`, `fcvt.fp.int`, `fcvt.s.d`/`fcvt.d.s` | 3 |
| `fadd`/`fsub`/`fmul` (S and D) | 5 |
| `fmadd`/`fmsub`/`fnmsub`/`fnmadd` | 7 |
| `fdiv.s`/`fsqrt.s` | 17 |
| `fdiv.d`/`fsqrt.d` | 32 |

## Requirements carried from the CVA6+Ara characterization

These are measured third-party deviations the in-house core must not
repeat; each needs a directed test before the corresponding stage is
called done:

1. `vfirst.m`/`vpopc.m` examine only active elements (index < `vl`),
   and mask-result tails follow `vma` (`mu` = undisturbed). Ara
   violates both at small `vl`
   (`docs/evidence/act-vector-vfirst-probe-2026-10-13.log`).
2. LR/SC and AMO fault causes use the load-side cause class the
   privileged spec requires; CVA6 reports store-side causes for LR
   (waived in the merged evidence, issue #20).
3. PMP `pmpcfg` readback does not silently set bits the software
   cleared (CVA6 G=1 readback waiver, issue #20).
4. Misaligned scalar accesses: decide trap-vs-emulate before stage 3
   and test the declared behavior (stage 1 traps; Zicclsm is not
   claimed).

## Stage-1 interface contract

`muserisc_core` presents one instruction port and one data port,
both combinational-read (the TB SRAM responds in the same cycle):

- `imem_addr_o[63:0]`, `imem_rdata_i[31:0]`
- `dmem_addr_o[63:0]`, `dmem_wdata_o[63:0]`, `dmem_be_o[7:0]`
  (byte enables, nonzero = write), `dmem_re_o`, `dmem_rdata_i[63:0]`

Reset PC is the `boot_pc_i` input (`0x0000_0000` for the directed
binaries, the ELF entry point in HTIF mode). Traps assert `trap_o` with
`trap_cause_o` (RISC-V mcause encoding) and freeze the PC; full trap
handling state arrives in stage 3. The core harness
(`tb/cpp/core_tb.cpp`) maps RAM at 0 and treats a store to
`0x1000_0000` as test exit (value 0 = pass, nonzero = failing test
number), matching the `sw/core-tests/` convention.
