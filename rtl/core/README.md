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
(`fp_eval`, the combinational chain the vector unit uses), so
scalar and vector FP share one definition. Build with
`-I rtl/core` (the Makefiles do). Synthesis check:
`scripts/synth_fpu.sh` (sv2v + Yosys + OpenSTA, Nangate45).
