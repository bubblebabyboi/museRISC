# #56: where the cycles go and what to upgrade (2026-10-22)

This is the analysis behind `docs/PERFORMANCE.md` sections 12 to 14: where
the cycles go on main `eeaa332`, and a ranked list of upgrade
candidates. It uses two sources:

1. **The measured counters** of the #56 baseline,
   [`perf-baseline-56-2026-10-22`](../perf-baseline-56-2026-10-22/README.md)
   (branch `56-perf-harness` at `de21e4b`, `rtl/` tree `89b98cb227c6`,
   with no #53 pipelining), together with
   [`perf-f2-56-2026-10-22`](../perf-f2-56-2026-10-22/README.md) for the
   F2 hardware.
2. **A trace-driven cycle model** of the `eeaa332` front end. It answers
   what-if questions about fetch and branch prediction, which the
   counters alone cannot answer. Before any what-if run, the model was
   checked against the RTL counters (see below).

Every figure in PERFORMANCE.md sections 12 to 14 comes from one of the
files here or from the baseline evidence. Figures marked *estimate* in
PERFORMANCE.md are arithmetic on the counters with a stated assumption.
None of them has been built or simulated.

## Files

| Path | What |
|---|---|
| `counters/derive.py`, `counters/derived.md` | The counter-derived quantities that PERFORMANCE.md quotes, for the headline regions (default and sky130, `soc`): I$ port occupancy, fetches per instruction, instruction size, redirects, D$ hit cycles per access, uncached cycles per access, vector LS cycles, bus occupancy, and the per-kernel accounting. Run with `python3 counters/derive.py ../perf-baseline-56-2026-10-22`. |
| `counters/fetch_occupancy.py`, `counters/vector_whatif.py`, `counters/dump_counters.py` | Helpers used by the execution-unit analysis: I$ occupancy and idle cycles; vector what-ifs (FPU pipelining, LS packing, vector multiply) as counter arithmetic; a dump of the non-zero counters of selected regions. Each takes the baseline directory as its argument. |
| `frontend-model/fe.cpp` | The analyzer and cycle model (C++17). It reads a Spike `--log-commits` trace and the ELF, splits the trace into `SIGIL_PERF` regions at the marker CSR writes, and prints per region: instruction and control-flow statistics, the accuracy of branch direction predictors, BTBs and RASes, and cycles for each fetch and predictor variant. |
| `frontend-model/run.sh`, `rtlrun.sh`, `batch3.sh`, `batch4.sh`, `batch5.sh` | How the runs were made on sigil-verify. `run.sh`: Spike trace into the analyzer. `rtlrun.sh`: RTL retirement trace into the analyzer, used for the SHA chains, because Spike has no hash engine. |
| `frontend-model/trace_patch.svh` | The simulation-only retirement-trace tap used for `rtlrun.sh`. It was added to a `git archive` copy of `8d15410` on sigil-verify and never committed. In that copy, region 0 has the same cycle count as the baseline, so the tap is passive. |
| `frontend-model/out3/`, `out4/`, `out5/` | Model output (`<run>.<config>`), with the analyzer's stderr (`.err`) and the program's UART output under Spike (`.uart`). Only the newest copy of each file is kept. `version-consistency.log`: the analyzer gained variants between the three sets, but every (region, variant) pair present in two sets has the same cycle count (0 differences). |
| `frontend-model/tab.py`, `fe_summary.py`, `whatif.md` | Parser and the what-if table: model speedup for each fetch and predictor variant over the model of today's core, for every modelled region, default and sky130. Run with `python3 fe_summary.py out3 out4 out5 --rtl ../../perf-baseline-56-2026-10-22`. |
| `analyses/frontend.md`, `memory.md`, `execution.md` | The three analyses as written: front end and control flow, memory hierarchy and LSU, execution units and parallelism. PERFORMANCE.md §14 reconciles them. Where they disagree with PERFORMANCE.md, PERFORMANCE.md is the result. |

## Front-end model

**Inputs.**
- The baseline ELFs (`build/perf/baseline-56/default/bin` at `8d15410`).
  They are byte-identical in all three configurations.
- Spike 1.1.1-dev (riscv-isa-sim `2c300cd9`), with
  `--isa=rv64gcv_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh_zvl512b_zicntr_zihpm`.
- For `sha256chain` and `sha256chain_bulk`: the RTL retirement trace from
  `soc_rtl_tb`, built with Verilator 5.048 and the tap above.
- The analyzer built with g++ 13.3.0 on sigil-verify (Ubuntu 24.04).
- Run 2026-10-22, about 12:30–12:45Z.

**Model of today's core (`F0_rtl`).** The model implements the
`eeaa332` rules:
- The I$ accepts one request per lookup: 2 cycles per hit, 3 with
  `SRAM_OREG`. The next fetch is issued only after the response. Each
  instruction fetches its own aligned 32-bit word, and a 32-bit
  instruction at `pc % 4 == 2` takes two fetches.
- Taken branches, `jal` and `jalr` resolve in EX, with not-taken fetch.
- D$ hits freeze MEM for 1 cycle (2 with `SRAM_OREG`).
- The M unit and the FPU hold EX for the cycles `micro_units` measures.
- Load-use interlocks follow the RTL rules.
- Miss and refill timing is that of the `soc` memory model.

**Check against the RTL counters (`soc`).**

| Region | default: RTL cycles | model error | sky130: model error |
|---|---:|---:|---:|
| CoreMark scalar | 14,337,806 | +0.0002% | +0.0052% |
| CoreMark validation | 14,364,787 | +0.0003% | |
| Dhrystone scalar | 3,070,244 | +0.0014% | +0.0002% |
| SHA-256 C | 10,156,268 | +0.0001% | +0.0002% |
| SHA-256 Zknh | 6,915,325 | +0.0001% | +0.0004% |
| bulk SHA-256 C / Zknh | 10,114,258 / 6,903,194 | −0.012% / +0.010% | +0.0001% / +0.0003% |
| scalar C kernels | | −0.2% to +1.1% | |
| CoreMark sdk | 14,572,507 | −0.29% (9,443 vector instructions not modelled) | |
| Dhrystone sdk | 3,482,242 | −19.2%: the vector struct copy (`stk_vls` 672,000) is not modelled | |

- `ic_access`, `br_taken`, `jal_redir`, `jalr_redir`, `ret_branch` and
  `muldiv_busy` match the RTL counters exactly. For example, `ic_access`
  is 6,806,626 for CoreMark, 1,502,031 for Dhrystone and 1,384,025 for
  Dhrystone sdk.
- The kernels' error comes from FPU latencies other than
  fadd/fmul/fmadd/fdiv/fsqrt, which are estimated.
- For Dhrystone sdk, `whatif.md` also gives the speedups with the
  RTL's vector LS cycles held constant.
- `micro_pipe` agrees within 1 cycle per region, except
  `brpat_always/alt/rand`: a branch to the next instruction cannot be
  seen as taken in a PC trace.

**Programs under Spike.**
- Every traced program printed `SIGIL TEST PASS` (see the `.uart`
  files), apart from `micro_pipe`.
- Under Spike, `micro_pipe` fails one check: `rdtime` advances 50 ticks
  over 4096 reads, while the program expects at least one tick per read.
  Spike's timer does not run at the core clock, whereas on the RTL
  `mtime` does. The instruction stream is otherwise the same, and
  `micro_pipe` serves only the per-mechanism check above. No what-if
  number comes from it.

**Variants** (`whatif.md` column names):

| Name | Fetch |
|---|---|
| `F0` | today's fetch |
| `F1` | today's, plus reuse of the held 32-bit word for the next parcel |
| `F3` | 64-bit I$ response, a 2-entry doubleword queue with a parcel aligner, and next-block prefetch when the I$ is idle (with the response bypass into IF/ID) |
| `F3s` | F3 without the bypass (registered queue only) |
| `F3w16` | F3 with 16-byte blocks |
| `F4` | F3 with an I$ that accepts a new request during a hit lookup |
| `F5` | an idealized front end: 64-byte access, 4 deep, pipelined |

Predictor suffixes:

| Suffix | Predictor |
|---|---|
| `+jal` | `jal` taken via predecode |
| `+btfn` | static backward-taken/forward-not-taken, plus `jal` predecode and a 4-entry RAS |
| `+bim64` | 64-entry 2-bit bimodal BHT indexed by `pc[6:1]`, predecoded targets, `jal` predecode, 4-entry RAS |
| `+gsh12` | gshare, 4K entries |
| `+btb64` | a 64-entry BTB instead of predecoded targets |
| `+perfect` | perfect prediction |
| `+r1` | one bubble per predicted-taken transfer: the target is formed from registered data |

Mispredicts flush from EX, as today. The D$, the M unit and the FPU
keep today's timing in every variant.

**Assumptions.**
- `soc` memory. The `axi` model adds less than 0.02% to these regions,
  and F2 hardware matches `default/axi`, so the results apply to the
  current AFI.
- The `fpga` configuration equals `default` on every scalar region
  (measured).
- The BHT is updated with the true outcome, and the RAS only on the
  correct path.
- Accuracy is measured on these benchmarks only. Linux and code heavy
  in indirect calls will predict worse.

## What this analysis does not show

- **Dual issue and multithreading after a front-end fix.** Neither has
  been modelled. The pairing rate a dual-issue core would reach is not
  measured. PERFORMANCE.md therefore quotes only the bounds that
  today's counters set.
- **Area, timing and verification effort.** These are bottom-up
  estimates scaled from `docs/SOC_AREA.md` (nangate45 hierarchical
  area), `docs/evidence/fpga-f0-2026-10-21/impl_util_hier.rpt` (FPGA
  utilization), and the #53 timing path families
  (`docs/FPGA_TIMING_53.md` on `origin/53-mem-stage-pipeline`). None was
  synthesized.
