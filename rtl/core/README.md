# In-house core (issue #18)

This directory holds museRISC's own RV64 core, written in
SystemVerilog and developed in verified stages (design, staging
plan, interface contract, and requirements carried from the
CVA6+Ara characterization: [`docs/CORE.md`](../../docs/CORE.md)).

The earlier integration plan for this directory — a CVA6 host
(`cv64a6_imafdc_sv39` / `cv64a6_imafdcv_sv39`) with an Ara vector
unit, fetched via `scripts/setup.sh` — has been superseded. The
third-party system remains in `third_party/` as the characterized
reference the merged B1/B2/#9 evidence was gathered on; it is not
the shipping core.

Stage 1 (landed on the #18 branch): single-cycle RV64I
(`muserisc_pkg`, `muserisc_regfile`, `muserisc_alu`,
`muserisc_decoder`, `muserisc_core`) verified by C++ Verilator
unit testbenches per module plus directed self-checking assembly
(`tb/cpp/`, `sw/core-tests/`, run via `make core-test`).

FPU (fpu-multicycle): `muserisc_fpu.sv` is a multi-cycle,
synthesizable F/D unit behind the generic EX-stage
req/done/ack/kill handshake (`docs/CORE.md`, "EX-stage
multi-cycle units"). Its arithmetic lives in
`muserisc_fpu_ops.svh`, which is `include`d both by the module
(registered stage by stage) and by `muserisc_fpu_pkg.sv`
(`fp_eval`, the combinational chain used as the simulation
reference). The vector unit runs its FP element sub-steps on
the same FPU instance, so scalar and vector FP share one
definition and one datapath. Build with
`-I rtl/core` (the Makefiles do). Synthesis check:
`scripts/synth_fpu.sh` (sv2v + Yosys + OpenSTA, Nangate45).

M unit (muldiv-multicycle): `muserisc_muldiv_mc.sv` is the
multi-cycle RV64M unit on the same handshake (2-cycle pipelined
multiplier, radix-4 early-terminating divider). The
combinational `muserisc_muldiv.sv` stays as its `COMB=1` mode and
as the simulation cross-check reference. Block synthesis:
`scripts/synth_unit_nangate45.sh`.

L1 caches (memory-interface stage): the core's memory ports are
request/response (one request in flight per port, response no
earlier than the next cycle). The integration top is
`muserisc_cpu` = `muserisc_core` + `muserisc_icache` (8 KiB,
2-way) + `muserisc_dcache` (16 KiB, 4-way, write-back +
write-allocate) + `muserisc_bus_arb`, exposing one memory-bus
master port; the arrays are `muserisc_sram_sp` single-port
synchronous SRAMs (macro/BRAM friendly) and
`muserisc_cache_pkg` holds the data-port opcodes and the
cacheability (PMA) function. Protocol, cacheable windows and
FENCE.I/SFENCE.VMA/atomics/walker rules:
[`docs/CORE.md`](../../docs/CORE.md#memory-interface-and-l1-caches).
Unit TBs: `tb/cpp/icache_tb.cpp`, `tb/cpp/dcache_tb.cpp`; bus
slave model: `tb/cpp/mbus_model.h`; synthesis check:
`scripts/synth_caches.sh`.
