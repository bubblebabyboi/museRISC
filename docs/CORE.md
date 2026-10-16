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
writes. The M-unit divider was combinational in stage 2 (a
correctness vehicle); the multi-cycle `muserisc_muldiv_mc` with
an EX stall has since replaced it (see "M unit" below).
Pipeline performance
beyond correctness is not yet a goal at this stage.

## EX-stage multi-cycle units (fpu-multicycle)

The scalar FPU (`rtl/core/muserisc_fpu.sv`) is a multi-cycle
unit: the FP instruction stays in EX until the unit completes.
The handshake is generic so other EX units (the multi-cycle M
unit, see "M unit" below) reuse it unchanged:

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

## Memory interface and L1 caches

The stage-1..9 core read memory combinationally (same-cycle
`imem_rdata_i`/`dmem_rdata_i`). That contract is retired: the
core now has two latency-tolerant request/response ports, and
`rtl/core/muserisc_cpu.sv` wraps it with a blocking L1 I$, a
blocking write-back L1 D$ and a two-master bus arbiter behind
one memory-bus master port. Synchronous SRAM/BRAM and DDR can
now sit behind the caches (#32 F2 gap 2, #11, #4).

```text
 muserisc_cpu
 +---------------------------------------------------------------+
 | muserisc_core                                                 |
 |   IF --ireq/irsp--> muserisc_icache --+                       |
 |   MEM/PTW --dreq/drsp--> muserisc_dcache --+-> muserisc_bus_arb --> mbus master
 |   FENCE.I --icache_inval--> I$        |                       |
 +---------------------------------------------------------------+
```

### Core ports (core <-> L1)

Instruction port: `ireq_valid_o`, `ireq_ready_i`, `ireq_addr_o`
(PA of an aligned 32-bit word), `irsp_valid_i`,
`irsp_rdata_i[31:0]`, plus `icache_inval_o` (FENCE.I pulse).
Data port: `dreq_valid_o`, `dreq_ready_i`, `dreq_addr_o` (exact
byte PA), `dreq_op_o` (`DOP_LOAD`/`DOP_STORE`/`DOP_CLEAN`,
`muserisc_cache_pkg`), `dreq_wdata_o` (lane-replicated store
data), `dreq_be_o` (accessed lanes, for loads too),
`drsp_valid_i`, `drsp_rdata_i` (the aligned 64-bit word).

Rules: at most one request in flight per port; a request is
accepted in the cycle `valid && ready`; every accepted request
gets exactly one response, no earlier than the next cycle. The
core may change or withdraw a request that has not been
accepted (e.g. a fetch whose PC was just redirected), so an L1
must decide acceptance in the cycle itself (the caches accept
whenever idle).

Pipeline behaviour:

- **IF** holds `pc_q` until its fetch word arrives
  (`fetch_stall`), buffering a word that arrives while ID is
  stalled (`ifw_q`). A flush, trap, or a consumed fetch fault
  marks an outstanding fetch stale (`ifq_drop_q`) and its
  response is dropped. Translation and its faults are
  unchanged (combinational TLB in IF; walker on a miss).
- **MEM** issues its access only when no older instruction is
  trapping (`!trap_fire`), so a MEM access is never abandoned;
  the whole pipeline holds (`mem_stall`) until the final
  response. Stores, SC and AMO write phases are therefore
  non-speculative when they reach the D$. A failing SC makes
  no access. AMOs are a LOAD then a STORE of the combined
  value, with the port held by MEM in between (single hart:
  atomic). LR/SC reservations stay physical-address based in
  the core and survive D$ evictions.
- **Page-table walker** requests share the data port and go
  through the D$ (coherent with PTE stores by construction;
  A/D updates are D$ stores). MEM has priority; an MMU
  flush/abort (SFENCE.VMA, trap) while a walker request is out
  drops its response. PMP-denied PTE accesses complete without
  a memory access.
- **FENCE.I** (MISC-MEM funct3=001) serializes in EX like
  SFENCE (redirect to pc+4, younger instructions flushed), then
  in MEM issues `DOP_CLEAN` (D$ writes back every dirty line)
  and, on its response, pulses `icache_inval_o`. Fetch is
  blocked while FENCE.I is in MEM. A refill in flight when the
  I$ is invalidated does not leave its line valid.
- **SFENCE.VMA** needs nothing from the caches: both are
  physically indexed and tagged, so TLB invalidation is the
  whole job (as before).
- Misaligned accesses still trap in EX and never reach a port.
  Vector loads/stores issue one element access per response.
- The vector load/store sequencer in MEM issues one D$
  request per active element (or segment field) and completes
  that element only on its response (`vls_elem_done` waits for
  `mem_port_done`); MEM is frozen while it waits. Vector
  accesses to I/O addresses go out as single uncached beats
  like scalar ones.
- Front-end holds: IF consumes its word only when ID can
  accept it (`!stall && !ex_hold` and no MEM stall), so a word
  that arrives while EX is held stays buffered. `ex_hold` is
  the generic EX hold (vector unit and every multi-cycle EX
  unit: FPU, M unit), so a new unit on that handshake is
  covered automatically.

### Caches

| | I$ | D$ |
|---|---|---|
| Default geometry | 64 sets x 2 ways x 64 B = 8 KiB | 64 sets x 4 ways x 64 B = 16 KiB |
| Policy | read-only, blocking | write-back + write-allocate, blocking |
| Replacement | first invalid way, else round-robin | same |
| Arrays (per way) | data 512 x 64 b, tag 64 x 44 b | data 512 x 64 b (8 byte lanes), tag 64 x 44 b |
| Flops | valid bits | valid + dirty bits, 1-line write-back buffer |

Parameters on `muserisc_cpu`: `IC_SETS`, `IC_WAYS`, `DC_SETS`,
`DC_WAYS`, `LINE_BYTES` (power of two, 16..2048), and the
cacheable windows below. Arrays are `muserisc_sram_sp`
instances: single-port, synchronous read (data the cycle after
the address), per-lane write mask, no read-during-write
forwarding needed — i.e. an SRAM macro or a BRAM in NO_CHANGE
mode. Hit latency is one cycle after acceptance; a miss adds a
line refill (one burst) plus, for a dirty victim, a line
write-back (one burst) before it, then a one-cycle replay.
Uncached responses are registered in the cache (one extra
cycle), so no bus input reaches the core combinationally: the
core sees only cache state and SRAM outputs.

Write-back was chosen over write-through because every store
would otherwise be a bus transaction (and, with blocking
caches, a pipeline stall of a full DDR round trip on F2); the
costs are a dirty-victim buffer and a clean-all walk on
FENCE.I: it visits every line (SETS x WAYS = 256 cycles at
least for the default D$) and adds a line write-back burst per
dirty line; Linux issues FENCE.I when it maps new executable
pages.

### Cacheability (PMA)

A PA is cacheable iff `cache_en_i` (a strap; 0 makes every
access uncached) and it lies in `[C0_BASE, C0_BASE+C0_SIZE)` or
`[C1_BASE, C1_BASE+C1_SIZE)` (size 0 disables a window).
Defaults: C0 = DRAM `0x8000_0000..0xFFFF_FFFF`, C1 off, so the
`soc_tb`/DT boot ROM (`0x1000`), CLINT, PLIC and UART are I/O.
`core_tb` adds C1 = `[0, 0x1000_0000)` for the directed tests
at PA 0, leaving the exit address `0x1000_0000` and the test
device at `0x2000_0000` uncached. Uncached accesses are single
bus beats with the exact byte address and lanes, issued once,
in program order (device side effects happen exactly once);
uncached instruction fetches are also single beats.

### Memory bus (mbus)

One master port; one transaction on the bus at a time.
Request channel (valid/ready; the master never withdraws a
presented beat): `req_addr`, `req_write`, `req_len` (beats-1),
`req_wdata`, `req_be`, `req_last`, `req_inst` (instruction
fetch, like AXI `ARPROT[2]`). A read is one request beat
answered by `len+1` response beats; a write is `len+1` request
beats (each with its own address) answered by one response
beat. Response channel: `rsp_valid` (no ready — the master is
always waiting), `rsp_rdata`, `rsp_last`. Line transfers are
`LINE_BYTES/8` incrementing 64-bit beats from the line base.
This maps 1:1 onto AXI4 (AR/R; AW+W/B with RREADY=BREADY=1) or
directly onto a BRAM controller; there is no error response
yet (no bus-fault pin on the core, as before).

### SoC integration

`rtl/soc/muserisc_soc_top.sv` instantiates `muserisc_cpu`.
`muserisc_soc_fabric` sends RAM-window requests (PA >=
`0x8000_0000`, the only cacheable window) unchanged to the
SoC's external memory-bus port and turns every other request
into one device access: the access is presented to the
selected device (boot ROM, CLINT, PLIC, UART, crypto bridge)
for one cycle, or until the crypto bridge stops stalling,
with the read-enable/byte-enables asserted exactly once, and
the captured data is returned as a single response beat one
cycle later. Boot-ROM instruction fetches use the same path
without a read-enable. The core's former `dmem_stall_i` input
is gone; the request/response data port covers it.

### Performance expectations

Correctness first: both caches are blocking and the core issues
a new request only after the previous response, so a hitting
fetch or load/store costs two cycles (request, response) —
roughly half the IPC of the old combinational model with a
perfect memory. Misses add the bus latency plus a 8-beat burst
(and a write-back burst for dirty victims). Obvious next steps:
accept a new request in the response cycle (pipelined hits),
next-word fetch prefetch, a store buffer, critical-word-first
refills. Recorded cycle counts are in `docs/evidence/`.

### Test harness

`core_tb` and `soc_tb` instantiate `muserisc_cpu` and model the
bus slave (`tb/cpp/mbus_model.h`) with seeded random latency,
inter-beat gaps and request backpressure (`--mem-lat A:B`,
`--mem-gap N`, `--mem-ready PCT`, `--mem-seed S`) and can turn
the caches off (`--no-cache`). `core_tb` observes stores at the
core's data port (`dbg_st_*`) for the exit/HTIF protocol,
because `tohost` is cacheable and may never be written back.
`make core-test` runs every directed test with caches on and
random latency, and again uncached.

Unchanged from stage 1: the reset PC is `boot_pc_i` (`0` for
the directed binaries, the ELF entry in HTIF mode); `trap_o`
pulses with `trap_cause_o`/`trap_pc_o` when a trap is taken,
and `trap_halt_i` freezes on the first trap for the
`--expect-trap` tests. Directed tests run from PA 0 and end
with a store to `0x1000_0000` (0 = pass, nonzero = failing
test number).

## M unit: `muserisc_muldiv_mc` (multi-cycle)

`rtl/core/muserisc_muldiv_mc.sv` is the RV64M unit in EX
(`u_muldiv`), on the generic multi-cycle handshake above:
`muldiv_req = idex_valid && muldiv && !idex_exc && !ex_illegal`,
its `req && !done` term is ORed into `ex_mc_busy`, `ack =
ex_advance`, `kill = trap_take`. Operands are sampled in the
issue cycle, so later forwarding changes are ignored;
`done_o`/`result_o` come only from unit registers. The unit
returns to IDLE on ack, kill or a dropped `req`, and nothing is
registered in a done state, so a done result can never be seen
by the next op (which always starts from IDLE). The M unit and
the FPU are asserted (simulation) never to be in flight together,
and an M op never shares EX with an FP or vector op. Vector
integer mul/div (in `muserisc_vec`) are unaffected. An interrupt
waits for a held M op like any EX hold
(it is injected on a younger instruction). An older instruction's
exception kills it (`kill = trap_take`) and it re-executes after
the handler returns. That kill can come at any cycle of the op: an
older access parked in MEM by `mem_stall` (a page-table walk, or a
vector load/store that faults on a later element) keeps the M op
running in EX for as long as the stall lasts. A result finished
during the stall is acked in the cycle the stall ends with the
fault and then flushed from EX/MEM by the trap; a trap firing in
the done cycle itself kills the unit in its done state. Covered by
`md_kill_directed.S` (vector load faulting on element 8 behind
long divides, multiplies and x/0; x/0 behind a misaligned load)
and `md_irq_directed.S`.

| op | cycles in EX, default `COMB=0` (minimum 2: every M op stalls EX) |
|----|------------------------------------------------------------------|
| MUL, MULH, MULHSU, MULHU, MULW | 3 |
| DIV/REM(U)(W) by zero, signed overflow | 2 |
| other DIV/REM(U)(W) | 3 + n, n = max(0, ceil((clz\|b\| − clz\|a\| + 1)/2)) |

n is 0..32 (0..16 for W forms): |a| < |b| with a different MSB
position takes 3 cycles, a full 64-bit quotient 35 (the unit's
`done` is in cycle 2 / 1 / 2 + n counting the issue cycle as 0). Multiplier: 65×65
signed (per-op sign/zero extension) as four 33×33 signed partial
products registered in MUL1 (2×2 DSP48 tiles on FPGA, Booth arrays on
ASIC), summed in MUL2. Divider: radix-4 restoring recurrence on
magnitudes (compare against d, 2d, 3d in parallel), normalized by
leading-zero counts so only significant quotient digits iterate;
FIX applies signs and the W sign extension. `COMB=1` keeps the legacy
single-cycle behaviour behind the same handshake (`done_o = req_i`);
the core selects it with `+define+MUSERISC_MULDIV_COMB`
(`make -C sim core-mdcomb` runs the directed suite on that build).
Simulation builds cross-check every completion against
`muserisc_muldiv`.

Verification (`make -C sim muldiv_mc`, `tb/cpp/muldiv_mc_tb.cpp`,
golden `tb/cpp/muldiv_golden.h`): edge-operand cross product and
exhaustive −20..20 operands for every op and W form, every divider
step count, and 1M randomized ops with handshake stress (done held
without ack, operands scrambled while busy, ack noise, back-to-back
issue, kill / req drop / asynchronous reset at every cycle of an
operation including the done hold); exact latency is checked on
every op. Verilator line and toggle coverage of
`muserisc_muldiv_mc.sv` is 100% (COMB=0 and COMB=1 builds merged).

Block synthesis (`scripts/synth_unit_nangate45.sh`, Yosys `synth
-booth` + ABC, OpenSTA at 10 ns, no placement/buffering; evidence in
`docs/evidence/muldiv-multicycle-upstream-2026-10-16.log`):

| unit | cell area | flops | worst path |
|------|-----------|-------|------------|
| `muserisc_muldiv` (combinational) | 49,787 µm² | 0 | 115.8 ns in→out (1,758 cells) |
| `muserisc_muldiv_mc` | 28,566 µm² | 274 | 4.69 ns reg→reg (MUL1 partial products, 70 cells); 4.25 ns reg→`result_o` (MUL2 sum); divider ITER step 3.3 ns |
