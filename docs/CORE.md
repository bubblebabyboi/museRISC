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
| 8 | Integer V (RVV 1.0 Zve32x/Zve64x), VLEN 512, ELEN 64 [#23](https://github.com/bubblebabyboi/museRISC/issues/23) | ACT vector suites via `sw/act4-core` (`scripts/build_act4_core.sh`) | **Done** (integer subset): ACT Vx/Vls 1872/1872 self-checking ELFs pass (43 tests not generated/selected, documented in evidence); FP vector (Zve32f/64f/64d) added in stage 9 (#29, Vf32/Vf64 162/162). Reworked element-serial for synthesis/timing (#32, see "Vector unit" below) |

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

## Vector unit (element-serial, #32)

The original vector unit evaluated whole register groups
combinationally (up to 64 elements, each with its own adder,
multiplier, divider and `fp_eval`, over 4096-bit group ports
from a 32x512 flop VRF). It is now element-serial over a
64-bit datapath, so its logic does not grow with VLEN and it
can close timing.

**VRF** (`muserisc_vregfile.sv`): 32 x 512 bits stored as 256
64-bit words (`{reg, word}` addressing). Three identical 1R1W
256x64 RAM replicas with byte-write enables and *synchronous*
read (address sampled when `re` is high, output held while
low), one per read port: A (vs2 / index), B (vs1), C (old vd
/ store data); every write goes to all three. Each replica
maps to one SDP BRAM (or LUTRAM) on FPGA or a 1R1W
byte-masked SRAM macro on ASIC. A one-cycle write bypass
gives write-first behavior so the RAM collision mode never
matters. v0 is mirrored in a 512-bit shadow register so any
element's mask bit is available without a read port. The
port mux gives the MEM vector load/store sequencer the ports
while a vector memory op is in MEM, the vector unit
otherwise (they never overlap).

**Vector unit pipeline** (`muserisc_vec.sv`), one element
per cycle in steady state:

| Stage | Work |
|---|---|
| S0 | slot sequencer over `[vstart, vl)` (plus a seed and a final-write slot for reductions, one word per slot for `vmv<nr>r`); issues the three word reads, samples `v0[i]`; slide/gather-by-scalar source indices are computed here |
| S1 | extracts each operand element from its word (byte shift + width mask); `vrgather.vv`/`vrgatherei16` spend a second S1 cycle turning the vs1 element into a vs2 read |
| S2 | single-cycle integer ALU, compares/mask bits, fixed-point rounding (`vxrm`) and saturation (`vxsat`), reduction/iota/compress/cpop/first accumulators; or a multi-cycle sub-unit (below); mask-destination ops accumulate 64 bits in a word register seeded from the old vd word |
| S3 | write-back register: places the element in its word with byte enables (or writes a whole word) |

Multi-cycle elements hold S2 and back-pressure S1/S0:
radix-2^16 iterative multiplier on magnitudes (prep, 1/1/2/4
partial-product steps for SEW 8/16/32/64, sign, post, write),
radix-2 restoring divider (prep, SEW iterations, sign/special
cases), and FP elements through one shared `fp_eval` /
`fp_estimate` call per cycle (widening forms: convert vs2,
convert vs1, operate; `vfwred*`: convert, fold). The FP path
still calls the combinational `fp_eval` and will be re-pointed
at the multi-cycle FPU.

Read-ahead safety: S0 reads up to three elements ahead of
the write in S3. For every source/destination overlap RVV
allows (identical groups, widening into the high half,
narrowing or mask results into the low part) destination
element j only overwrites source elements <= j, which have
already been read, so in-order processing is exact; the
randomized TB exercises each allowed overlap. Prestart,
tail and masked-off elements are never written (agnostic =
undisturbed).

**Core integration** (`muserisc_core.sv`): a vector
arithmetic op holds EX (IF/ID frozen, bubbles into EX/MEM)
from the cycle it reaches EX until `done`. It *starts* only
when no older instruction can still trap (`!trap_fire`,
`!mem_exc`, `!mem_stall`) and no vector load/store is in
MEM, so its element writes are precise; its CSR side effects
(`vxsat`, `fflags`, VS/FS dirty, `vstart := 0`) commit in the
cycle it leaves EX. Interrupts are injected in ID and so are
taken at the instruction boundary after the op (latency
bound = the op's cycle count, at most 5,124 cycles for
`vdiv` e8 m8 vl=512). The MEM sequencer steps one element/field
at a time through the MMU/PMP/data port: RD cycle (VRF
reads for index and store data), ACC cycle (held across TLB
misses), load elements written to the VRF as they complete
(gated by `!trap_fire`); segment loads buffer one element's
fields and write them after the last field, so a fault never
leaves a partial segment. A fault sets `vstart` to the
element index (earlier elements committed); fault-only-first
trims `vl` for a fault on any element other than element 0
(only an element-0 fault traps). Whole-register loads/stores
and `vmv<nr>r.v` honor `vstart` (in elements of the encoded
EEW, resp. SEW). A CSR access or vset in EX is held for as
long as a vector load/store is in MEM (the pipeline is
frozen by `mem_stall` for all but its last cycle anyway), so
it observes that instruction's `vstart`/`vl` updates.

Interrupt latency: a vector arithmetic op delays an
interrupt by at most its own cycle count (max 5,124 cycles,
`vdiv` e8 m8 vl=512). A vector load/store in MEM also blocks
interrupt injection while it runs: 2 cycles per active
element or segment field, 1 per skipped element, *nf* per
segment element for write-out, plus page-table walks on TLB
misses. Without misses the worst case is 1,537 cycles (a
segment load moving 512 fields: 2 cycles per field plus 1
write-out cycle per field, plus the final cycle); an
unmasked `vle8.v` with vl=512 takes 1,025.

**Cycle counts** (vector unit, from `start` to `done`
inclusive; `vec_tb` prints these probes; N = elements in
`[vstart, vl)`):

| Op class | Cycles |
|---|---|
| integer ALU, compare, mask, fixed-point, shift, slide, merge, gather .vx/.vi, iota, id, compress, cpop/first | N + 4 (e.g. `vadd.vv` e8 m8 vl=512: 516; e64 m1 vl=8: 12) |
| `vrgather.vv` / `vrgatherei16` | 2N + 4 (e32 m1 vl=16: 36) |
| reductions | N + 6 (e32 m1 vl=16: 22) |
| multiply family (incl. widening, MAC, `vsmul`) | (k+4)N + 4, k = 1/1/2/4 for SEW 8/16/32/64 (e8 vl=64: 324; e64 vl=8: 68) |
| divide/remainder | (SEW+2)N + 4 (e8 vl=64: 644; e64 vl=8: 532) |
| FP single-step / widening / `vfwred` | N + 4 / 3N + 4 / 2N + 6 |
| `vmv<nr>r.v` | 8*nr + 4 (68 for nr=8) |
| `vmv.x.s`, `vfmv.f.s` | 4 |
| masked-off element | 1 (no sub-unit) |

The core adds no further cycles: the op occupies EX for
exactly these cycles. MEM vector loads/stores take 2 cycles
per active element (or field), 1 per skipped (masked-off or
below `vstart`) element, plus *nf* write-out cycles per
element for segment loads and 1 final cycle.
