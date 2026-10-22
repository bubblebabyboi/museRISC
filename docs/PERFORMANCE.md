# Performance

This document covers Sigil's performance (issue
[#56](https://github.com/bubblebabyboi/sigil/issues/56), epic #61):

- **§1–9, method.** How performance is measured: the harness, the
  simulation counters, configurations, benchmarks, validation, metrics
  and reports.
- **§10.** Running the same benchmarks on AWS F2 hardware.
- **§11, baseline.** Results for main `eeaa332` in simulation (three
  configurations, two memory models) and on F2 hardware.
- **§12.** Where the cycles go.
- **§13.** SHA-256 on the scalar core, with Zknh, with RVV and on the
  accelerator ([#10](https://github.com/bubblebabyboi/sigil/issues/10)).
- **§14.** Upgrade candidates, ranked on the evidence.
- **§15.** The evidence sets.

Every number in §11–14 comes from [`docs/evidence/`](evidence/README.md)
(§15), which records the commit, configuration, tool versions and date
of each run. Figures come in three kinds:

- **Measured** figures come from those runs.
- **Model** figures come from a trace-driven model of the front end. It
  reproduces the RTL cycle counts to within 0.0002–0.005% on CoreMark
  and Dhrystone.
- **Estimate** figures are arithmetic on the measured counters, under
  an assumption stated next to them.

Nothing in §14 has been built.

## Contents

1. [Quick start](#1-quick-start)
2. [What a run measures](#2-what-a-run-measures)
3. [The simulation event counters](#3-the-simulation-event-counters)
4. [Configurations and memory models](#4-configurations-and-memory-models)
5. [Benchmark interface](#5-benchmark-interface)
6. [Validation and determinism](#6-validation-and-determinism)
7. [Metrics](#7-metrics)
8. [Reports and diffs](#8-reports-and-diffs)
9. [Benchmarks](#9-benchmarks)
10. [Running on F2 hardware](#10-running-on-f2-hardware)
11. [Baseline: main `eeaa332`](#11-baseline-main-eeaa332)
12. [Where the cycles go](#12-where-the-cycles-go)
13. [SHA-256: scalar, Zknh, RVV and the accelerator (#10)](#13-sha-256-scalar-zknh-rvv-and-the-accelerator-10)
14. [Upgrade candidates](#14-upgrade-candidates)
15. [Evidence](#15-evidence)

## 1. Quick start

```sh
source deps/env.sh
make -C sim perf                                  # every bench, default config, both memory models
make -C sim perf BENCHES=dhrystone CONFIG="default sky130 fpga" JOBS=8
make -C sim perf BENCHES=dhrystone MEM=soc REPEAT=2   # determinism check
make -C sim perf ITER=200                         # quick smoke (not a result)
make -C sim perf BENCHES=kernels VARIANTS=scalar CLOCK_MHZ="62.5 100"
make -C sim perf BENCHES=coremark VARIANTS=scalar ITER=1000 MAX_CYCLES=1500000000
```

| Variable | Default | Meaning |
|---|---|---|
| `BENCHES` | all of `sw/bench/*/` | benchmarks to run |
| `CONFIG` | `default` | RTL builds: any of `default sky130 oreg fpga` (§4) |
| `MEM` | `soc axi` | testbench and memory model: `soc`, `axi` (§4) |
| `JOBS` | 4 | simulations run in parallel |
| `REPEAT` | 1 | runs of each simulation; >1 checks determinism (§6) |
| `ITER` | bench.json | overrides every bench's iteration count |
| `VARIANTS` | every variant | build variants to run, by name; a selected bench with none of them is skipped |
| `MAX_CYCLES` | bench.json | overrides every bench's `max_cycles` simulation limit (long runs) |
| `CLOCK_MHZ` | none | clocks for the report's projected-throughput table (§8), e.g. `"62.5 100"` |
| `PERF_OUT` | `build/perf/run` | output directory |
| `PERF_SOC_ARGS`, `PERF_AXI_ARGS` | §4 | memory model arguments |
| `VJOBS` | 0 (all cores) | Verilator build threads (shared with the rest of `sim/`) |

`make` builds the testbenches it needs, then
[`scripts/perf_run.py`](../scripts/perf_run.py) builds and runs every
benchmark and writes `results.json`, `results.csv` and `report.md` to
`PERF_OUT`. The target fails if any run fails validation.

To compare a design change against the baseline of §11, run it the
same way and diff it run by run (§8):

```sh
make -C sim perf CONFIG=default MEM="soc axi" PERF_OUT=build/perf/new
scripts/perf_report.py --diff docs/evidence/perf-baseline-56-2026-10-22/default build/perf/new
```

The baseline itself was produced by
[`run_baseline.sh`](evidence/perf-baseline-56-2026-10-22/run_baseline.sh):
all three configurations, both memory models, `REPEAT=2`. §10 runs the
same images on F2 hardware.

## 2. What a run measures

A benchmark marks the code it wants measured:

```c
#include "sigil.h"
sigil_perf_begin();
work();
sigil_perf_t t = sigil_perf_end();   /* prints "SIGIL PERF region=0 cycles=.. instret=.." */
```

`sigil_perf_begin()` writes a **begin marker** and then reads
`mcycle`/`minstret`. `sigil_perf_end()` reads them again, writes an
**end marker**, prints the `SIGIL PERF` line and returns the delta. The
`_id(n)` forms tag up to 256 regions, one open at a time. The marker and
counter reads are always inlined, so they add no call overhead at the
region edges, even under `-fno-inline`.

A marker is a single `csrw mhpmevent31, rs`. The value is
`0x5045_RRCC`: magic `0x5045` in bits 31:16, the region id in 15:8, and
the command (1 = begin, 2 = end) in 7:0. `mhpmevent3..31` are legal WARL
CSRs on this core, and writes to them are ignored. The marker therefore
has no architectural effect. A CSR write does not flush this pipeline,
so the marker costs one ordinary instruction. On hardware it is a
no-op, and the `SIGIL PERF` line (from `mcycle`/`minstret`) is the only
measurement.

In simulation, the event counters (§3) count every cycle from the begin
marker's CSR write up to, but not including, the end marker's. When the
end marker arrives they write one record. By construction, the
simulation `cycles` and `instret` equal the `mcycle` and `minstret`
deltas between the two markers. The record carries both values, and the
harness checks that they agree. The program's own `SIGIL PERF` window
lies a few instructions inside the marker window: its reads come after
the begin marker and before the end marker. The difference is a few
tens of cycles and about ten instructions. It is fixed for a given
binary, configuration and memory model: a load of the saved start
values can fall between the end read and the end marker. The report
shows it as `HW-counter cycles` next to `cycles`.

## 3. The simulation event counters

### Wiring

[`rtl/core/sigil_perf.svh`](../rtl/core/sigil_perf.svh) is textually
included at the end of `sigil_cpu` (core + L1s + bus arbiter) inside
`` `ifndef SYNTHESIS``:

- **No effect on any netlist.** Every synthesis flow defines
  `SYNTHESIS` (ORFS/slang `-DSYNTHESIS`, `synth_*.sh`, Vivado
  `-verilog_define SYNTHESIS`, sv2v `-DSYNTHESIS`). The preprocessor
  skips the include, and the two cache taps below are also inside
  `` `ifndef SYNTHESIS``. With `SYNTHESIS` defined, the preprocessed RTL
  is byte-identical to the RTL without the harness.
  [`scripts/synth_view_diff.sh`](../scripts/synth_view_diff.sh)
  `<rev-A> <rev-B>` checks this for every flow's define set. Run it on
  any change that should be simulation-only.
- **Passive.** The block only reads signals through hierarchical
  references and drives nothing in the design:
  - `u_core.*`: pipeline valid/stall/flush/hold signals, the ID
    decode, the EX CSR write port (marker decode), MEM stall causes,
    MMU ready/fault, multi-cycle unit handshakes, vector busy, and
    `u_csr.mcycle_q`/`minstret_q` for the cross-check.
  - The core's fetch and data ports (`ireq/irsp/dreq/drsp`) and the
    bus master port, with `u_arb.busy_q`.
  - `u_icache.perf_miss` / `u_dcache.perf_miss`: one-line simulation
    taps (the lookup of the current request missed).
- **Every harness gets it.** `core_tb` and `soc_tb` (top `sigil_cpu`),
  `soc_rtl_tb` and the srammacro builds (`sigil_soc_top`), and
  `fpga_top_tb`/`fpga_ocl_tb` all include it. It is excluded from
  coverage (`verilator coverage_off`), so the coverage figures of the
  existing gates do not change.
- **Lint.** Clean on Verilator 5.020 (Ubuntu 24.04/CI), 5.044 and 5.048
  (`make lint`).

Output: one line per end marker, `SIGIL_PERF v1 region=<id> seq=<n>
<key>=<value> ...`, appended to the file named by the plusarg
`+sigil_perf=<file>` (written to stderr without it). Every harness
forwards plusargs. The record also carries `mcycle_begin`,
`mcycle_delta`, `minstret_delta`, the build configuration
(`cfg_sram_oreg`, `cfg_vrf_oreg`, `cfg_ic`/`cfg_dc` as sets × ways ×
line bytes, `cfg_cache_en`) and `stk_sum`.

### Per-cycle accounting (`stk_*`)

Every cycle in the region is charged to exactly one category, so the
categories sum to `cycles`. A simulation `$error` fires if they do not,
and the same holds if `stk_retire` differs from `instret`. The core is
single-issue and in order, so the slot is read at WB:

1. **WB traps** (an excepting instruction is in WB) → `stk_trap`.
2. **The whole pipeline is frozen by MEM** (`mem_stall`). The cycle is
   charged to the sub-cause:

   | Category | Sub-cause |
   |---|---|
   | `stk_dtlb` | data translation walk |
   | `stk_vls` | vector load/store sequencing |
   | `stk_dc_clean` | FENCE.I D$ clean |
   | `stk_io` | uncached device access (UART, CLINT, crypto, ...) |
   | `stk_dc_miss` | D$ miss: write-back and/or refill, from the lookup that missed until the response |
   | `stk_dc_lat` | D$ hit latency: every load/store holds MEM until its response, at least one cycle, two with `SRAM_OREG` |

3. **An instruction retires** → `stk_retire`.
4. **Otherwise WB holds a bubble.** The bubble is charged to the cause
   that created it. A shadow tag travels with every empty slot down the
   pipeline, updated with exactly the core's IF/ID, ID/EX, EX/MEM and
   MEM/WB enables:

   | Category | The bubble was created because |
   |---|---|
   | `stk_fetch_lat` | IF waited for an I$ hit. This is the fetch request/response latency plus the issue gap: the core issues the next fetch only after the previous response, so one word every two cycles, three with `SRAM_OREG`. |
   | `stk_fetch_straddle` | a 32-bit instruction straddled a fetch word (two fetches) |
   | `stk_fetch_miss` | IF waited for an I$ refill |
   | `stk_fetch_unc` | IF waited for an uncached fetch (boot ROM) |
   | `stk_fetch_itlb` | IF waited for the page-table walker |
   | `stk_branch`, `stk_jal`, `stk_jalr` | a wrong-path instruction in ID or IF was squashed by a taken branch, a `jal` or a `jalr` |
   | `stk_serial` | squashed by xRET, FENCE.I or SFENCE/HFENCE, or IF was blocked by a FENCE.I in MEM |
   | `stk_loaduse` | load-use interlock |
   | `stk_muldiv`, `stk_fpu`, `stk_vec` | EX was held by the M unit, the FPU or the vector unit |
   | `stk_trap` | the slot was emptied by a trap flush |
   | `stk_other` | reset or a `trap_halt_i` freeze (never in a benchmark region) |

   Only slots that held, or were about to receive, a wrong-path
   instruction are charged to a redirect. A slot that was already empty
   keeps its own cause. So `stk_branch + stk_jal + stk_jalr` counts
   squashed wrong-path instructions. The refetch latency after a
   redirect is charged to `stk_fetch_*`.

### Event counters

These counters are not exclusive. They count raw events or busy cycles:

| Group | Counters |
|---|---|
| Totals | `cycles`, `instret` |
| Retired by class | `ret_alu`, `ret_load` (incl. FP loads), `ret_store`, `ret_amo` (incl. LR/SC), `ret_branch`, `ret_jal`, `ret_jalr`, `ret_mul`, `ret_div`, `ret_fp` (FPU ops), `ret_vec`, `ret_vls`, `ret_vset`, `ret_csr`, `ret_fence` (FENCE, FENCE.I), `ret_system` (xRET, WFI, SFENCE/HFENCE); `ret_rvc` = compressed, any class |
| Redirects | `br_taken`, `jal_redir`, `jalr_redir`, `xret_flush`, `fencei_flush`, `sfence_flush`; `squash_id`, `squash_if` = valid wrong-path instructions squashed |
| Traps | `trap_exc`, `trap_irq` |
| Stall/busy cycles | `loaduse_cyc`, `muldiv_busy`, `fpu_busy` (scalar FP), `vec_busy`, `vec_ex_stall`, `vls_cyc`, `fetch_stall_cyc`, `itlb_cyc`, `dtlb_cyc`, `mem_stall_cyc` |
| I$ (fetch port) | `ic_access` (requests accepted), `ic_miss`, `ic_unc` (uncached), `ic_miss_cyc` (cycles with a miss outstanding) |
| D$ (data port: MEM + walker) | `dc_load`, `dc_store`, `dc_clean`, `dc_miss`, `dc_unc`, `dc_miss_cyc`, `dc_unc_cyc` |
| Memory bus (`sigil_cpu` master port) | `bus_ifill`, `bus_iunc`, `bus_dfill`, `bus_dwb` (write-back bursts), `bus_dunc` (single beats); `bus_busy_cyc` (transaction in flight or offered), `bus_req_wait` (valid && !ready), `bus_rsp_wait` (in flight, no request beat, no response beat) |

## 4. Configurations and memory models

`CONFIG` selects the RTL build. All of them are the same RTL as the
synthesized design, with the same defines and parameters:

| `CONFIG` | Build | L1 geometry | SRAM read latency |
|---|---|---|---|
| `default` | default SoC | I$ 8 KiB 2-way, D$ 16 KiB 4-way, 64 B lines | 1 cycle |
| `sky130` | sky130hd chip configuration: `SIGIL_SRAM_SKY130`, the OpenRAM macro behavioural models, `SIGIL_SOC_PARAMS_SKY130` (srammacro family `sky130`) | I$ and D$ 4 KiB direct-mapped | 2 cycles (`SRAM_OREG`: caches and VRF) |
| `oreg` | `SIGIL_SRAM_OREG` on the default arrays (family `oreg`) | default | 2 cycles |
| `fpga` | the F2 build: `SIGIL_VRF_OREG` (family `vrforeg`, #53) | default | VRF 2 cycles, caches 1 |

`MEM` selects the testbench and the external memory model. Both models
are deterministic: fixed latencies and no random backpressure or gaps,
so every run of the same image gives identical counts (§6).

- **`soc`**: `soc_rtl_tb` (`sigil_soc_top`). RAM is the memory-bus
  slave model (`tb/cpp/mbus_model.h`). The default `PERF_SOC_ARGS` is
  `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`. The first response beat
  comes 1 cycle after the request beat that completes the request, then
  one 8-byte beat per cycle, and requests are always accepted. A 64-byte
  line refill therefore takes 1 + 8 bus cycles after the request is
  accepted. This is an ideal on-chip SRAM.
- **`axi`**: `fpga_top_tb` (`sigil_fpga_top`, the design that runs on
  F2). RAM sits behind the real `sigil_mbus_axi4` bridge, a 64-bit AXI4
  port, in the AXI DDR model (`tb/cpp/axi4_slave_model.h`). The default
  `PERF_AXI_ARGS` is `--axi-lat 24:24 --axi-gap 0 --axi-ready 100
  --uart-pop 100`. The first R beat comes 24 cycles after AR acceptance
  and B 24 cycles after the last W beat with its AW. There are no R
  gaps, AW/W/AR are always ready, and the host drains the virtual UART
  every cycle. The bridge's own cycles come on top of the 24. The
  regression's `--axi-lat 8:40` range is centred on this value; its
  seeded random gaps and backpressure are left out.

Run both models to see how sensitive a benchmark is to memory latency.
The effective miss penalty is `ic_miss_cyc / ic_miss` and
`dc_miss_cyc / dc_miss`.

**F2 hardware** is the third memory system: the CL's real DDR4 path
(§10). Two simulation configurations matter for it:

- **`default`.** The public AFI `agfi-035116450e0a0d093` was built from
  `4058108`, before `VRF_OREG` existed, so it runs the `default`
  configuration. Compare it with `default`/`axi`.
- **`fpga`.** The next AFI will be built with `VRF_OREG`; `fpga`
  predicts that one.

On the current AFI, a line refill costs about 1.5 cycles more than in
the 24-cycle `axi` model, and a dirty write-back about 10 cycles less
(§11.3). The `oreg` configuration exists for experiments and is not
part of the baseline.

## 5. Benchmark interface

A benchmark is a directory `sw/bench/<name>/`. The harness discovers it
automatically, so adding one needs no change to any shared file.

```text
sw/bench/<name>/
  Makefile      PROG := <name>; SIGIL_SDK := ../../sdk; include $(SIGIL_SDK)/sdk.mk
  bench.json    metadata (below)
  *.c *.h ...   sources
```

**Makefile.** It must:

- set `PROG := <name>`, which is the directory name and the test name;
- build with `sw/sdk/sdk.mk`;
- compile the iteration count in from `BENCH_ITERATIONS`, with a default
  (`BENCH_ITERATIONS ?= N`, `EXTRA_CFLAGS += -DMY_RUNS=$(BENCH_ITERATIONS)`);
- accept the usual `sdk.mk` overrides on the command line (`OUT`,
  `RISCV_PREFIX`, `SIGIL_MARCH`, `OPT`, ...).

The harness runs `make -C sw/bench/<name> OUT=<dir>
BENCH_ITERATIONS=<n> RISCV_PREFIX=<p> <variant make vars>` into a clean
directory and runs `<dir>/<name>.bin`.

**Program.** The program:

- puts `sigil_perf_begin()` / `sigil_perf_end()` (or the `_id` forms)
  around exactly the work being measured, once per region;
- checks its own output after the region against known answers
  (checksums, KATs, reference values);
- prints its `expect` lines, then `SIGIL TEST PASS <name>` via
  `sigil_pass()`, only if every check passed. Otherwise it calls
  `sigil_fail()`.

**`bench.json`:**

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | the directory name |
| `iterations` | yes | work units per run, passed as `BENCH_ITERATIONS`; the metrics divide by it |
| `description` | no | one line for the report |
| `max_cycles` | no (2e8) | simulation cycle limit |
| `expect` | no | lines that must appear in the UART output (`{iterations}` is substituted), e.g. a checksum line |
| `metrics` | no | any of `dmips_per_mhz`, `coremark_per_mhz`, `bytes_per_cycle` (§7) |
| `bytes_per_iteration` | for `bytes_per_cycle` | bytes processed per iteration; a region can override it |
| `regions` | no (`{"0": "main"}`) | measured regions, `{"<id>": "<label>"}` or `{"<id>": {"label": "...", ...}}` with the region fields below; ids 0–255; one result row per region |
| `window_region` | no | id of a region that measures an empty window (the region's own cost); the report adds cycles/iteration net of it |
| `variants` | no (`{"default": {}}`) | build variants, `{"<variant>": {"description": "...", "make": {"VAR": "value"}, "regions": [...], "expect": [...]}}`; each is built once and run on every configuration and memory model. `regions` (optional) lists the region ids this variant measures (default: all). `expect` (optional) adds lines for this variant only |
| `units` | no | what one iteration is |

Region fields, all optional apart from `label`:

| Field | Meaning |
|---|---|
| `label` | the row label |
| `bytes_per_iteration` | bytes per iteration for this region (`bytes_per_cycle`), when it differs from the bench's |
| `work_per_iteration`, `work_unit` | work per iteration in a unit of the bench's choosing (`elem`, `mac`, `byte`, ...); the report adds work/cycle |
| `baseline` | id of another region of the same image; the report adds this region's speedup over it (same configuration and memory model) |

`perf_run.py` checks these fields and fails with the bench.json path on
the first error. Any other key, such as `region_ops` in the `micro_*`
benches or `kernels` in `kernels`, is carried into `results.json`
(`meta.benches.<name>`) unchanged, for a bench's own report script. A
bench Makefile may run `python3`, which the harness needs anyway, for
example to generate known answers.

To run one benchmark: `make -C sim perf BENCHES=<name>`, with `CONFIG`,
`MEM` and the other variables as needed. To debug it outside the
harness, run `make -C sw/bench/<name> run`. It runs on `soc_rtl_tb`
and prints the counter record to stderr.

## 6. Validation and determinism

A run is a result only if all of these hold. A run that fails any of
them is listed under `failed` in `results.json`, left out of the
tables, and makes `make perf` fail:

1. the testbench exits 0 on `SIGIL TEST PASS <name>`, and the program
   printed it only after its own checks passed;
2. every `expect` line, the bench's and the variant's, is in the UART
   output;
3. there is exactly one `SIGIL_PERF` record per declared region (the
   variant's `regions`, if it lists them), and no record for any other
   region;
4. in each record, `cycles == mcycle_delta`,
   `instret == minstret_delta` and `stk_sum == cycles`;
5. the program's `SIGIL PERF region=<id>` line is present, and its
   cycle count is no greater than, and within 1000 cycles of, the
   marker window;
6. with `REPEAT > 1`: every repeat of the same (bench, variant,
   region, configuration, memory model) gives identical counters and
   hardware-counter numbers.

Determinism holds because the testbenches are cycle-based Verilator
models, the memory models above have no random component, and the
benchmarks have no input. A seeded random model (for example
`--mem-lat 1:6 --mem-ready 70`) is also reproducible for a fixed seed.

## 7. Metrics

| Metric | Definition |
|---|---|
| IPC / CPI | `instret / cycles` and its inverse, over the region |
| cycles/iter | `cycles / iterations` |
| DMIPS/MHz | `iterations / cycles × 10^6 / 1757` (Dhrystones per second at 1 MHz over the VAX 11/780's 1757) |
| CoreMark/MHz | `iterations / cycles × 10^6` |
| bytes/cycle | `iterations × bytes_per_iteration / cycles`, with the region's `bytes_per_iteration` if it has one |
| work/cycle | `iterations × work_per_iteration / cycles`, in the region's `work_unit` |
| net cycles/iter | `(cycles − window region cycles) / iterations`, against the `window_region` of the same simulation |
| speedup | baseline region cycles / region cycles, same simulation |

All metrics use the simulation window (`cycles`). Per-MHz figures are
clock-independent. To get absolute figures, multiply by the clock: for
example, F2 runs at 62.5 MHz today (`docs/FPGA_F2.md`). `CLOCK_MHZ`
adds that projection to the report; it is arithmetic on simulation
cycles, not a hardware measurement.

**Code placement.** On this core a 32-bit instruction that straddles a
4-byte fetch word costs a second fetch (`stk_fetch_straddle`), so the
same instructions at a different address can take a different number
of cycles. Shifting the `kernels` C code by 2 bytes moved its cycles by
−24% to +26%, and without `-falign-functions=64` the `sha256chain`
SHA-512 accelerator chain took 43% more cycles
([`docs/evidence/`](evidence/README.md), `perf-kernels-56-*` and
`perf-sha256chain-56-*`). `kernels` and `sha256chain*` therefore align
their measured functions to 64 bytes. Dhrystone and CoreMark use the
SDK flags unchanged, so their figures can move when unrelated code
changes size. Compare images (`bin_sha256` in `results.json`), not only
sources.

## 8. Reports and diffs

```sh
scripts/perf_report.py build/perf/run --csv out.csv --md out.md   # tables from one result set
scripts/perf_report.py --diff build/perf/base build/perf/new      # A vs B, run by run
```

`report.md` has these parts:

- the configurations, as the counter records report them;
- a summary: cycles, instret, IPC, CPI, cycles/iteration, net
  cycles/iteration (benches with a `window_region`), metric and
  hardware-counter cycles;
- *Speedups* over each region's `baseline`, if any region has one;
- *Projected throughput* at the `CLOCK_MHZ` clocks, if given:
  iterations/s and bytes/s or work/s;
- *Where the cycles go*: every `stk_*` category as a percentage of
  cycles;
- *Events*: instruction mix, redirect rate, I$/D$ and bus activity,
  unit busy time.

The last two have one column per run when there are at most 8 runs,
and one row per run otherwise. `results.csv` has one row per run with
every counter and metric. `results.json` adds the metadata: UTC date,
commit, merge base with `main`, `rtl/` tree hash, Verilator and
compiler versions, host, memory model arguments, any `ITER`,
`MAX_CYCLES` or `VARIANTS` override, image hashes and build commands
(`cc_commands`: every compiler line of the build). The diff matches runs
by bench, variant, region, configuration and memory model. It reports
the change in cycles, IPC and metric, and which accounting categories
moved.

## 9. Benchmarks

| Benchmark | What | Metric | Variants |
|---|---|---|---|
| [`dhrystone`](../sw/bench/dhrystone/README.md) | Dhrystone 2.1, netlib C source. Ground rules: separate compilation and `-fno-inline`; `-O2`, otherwise the SDK flags. | DMIPS/MHz | `scalar`: `-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`, the headline. `sdk`: SDK default `-march` with V, where GCC turns the 56-byte struct assignment into a `vle8`/`vse8` loop. |
| [`coremark`](../sw/bench/coremark/README.md) | EEMBC CoreMark 1.0, unmodified upstream source at a pinned commit, fetched and sha256/md5-checked into the git-ignored `third_party/coremark` (network on first build). Timed region = CoreMark's `iterate()`; `portable_fini` checks every CRC against references. `-O2`. | CoreMark/MHz | `scalar` (the headline, same `-march` as Dhrystone's), `sdk` (with V), `validation` (seeds `0x3415`, EEMBC run rule 2). |
| [`kernels`](../sw/bench/kernels/README.md) | 13 vector/FP kernels (int/fp add, axpy, dot, memcpy/memset, 32×32 gemm, FIR, int8/int16 MAC), each as portable C and as RVV intrinsics, checked bit for bit against a scalar reference and a host known answer. Regions `10k` (C), `10k+1` (RVV), `10k+2` (RVV e8). | work/cycle, RVV speedup over C (plus `kernels_report.py`) | `scalar`: C without V, `-O2`. `autovec`: the same C with V at `-O3` (GCC auto-vectorization). |
| [`micro_pipe`, `micro_units`, `micro_dmem`, `micro_imem`, `micro_vec`](../sw/bench/micro_common/README.md) | Calibration microbenchmarks: one mechanism per region, assembly kernels running exactly `iterations` operations, results checked in C. Pipeline/branches/load-use/CSR; M unit and FPU latency and throughput; D$ working-set and stream sweeps; I$ footprint sweep; vector ops versus VL. | cycles per operation, net of the `empty` window region (plus `micro_table.py`) | `default`: C for the scalar `-march`; `micro_vec`'s assembly enables V itself |
| [`sha256chain`](../sw/bench/sha256chain/README.md) | SHA-256 hash chain (#10): plain C, Zknh, RVV ×16 multi-buffer, the accelerator (block and byte APIs), plus SHA-512 and SHA3-256 chains on the accelerator. FIPS 180-4/202 known answers first; every result checked against Python `hashlib`. Functions 64-byte aligned. | cycles/hash, bytes/cycle (64-byte messages for SHA-512), speedup over plain C | `sdk` |
| [`sha256chain_bulk`](../sw/bench/sha256chain_bulk/README.md) | Hashing one 64 KiB buffer: SHA-256 plain C, Zknh, RVV ×16 (16 segments), accelerator SHA-512 and SHA3-256. Same checks. | bytes/cycle, speedup over plain C | `sdk` |

## 10. Running on F2 hardware

The images the harness builds run unchanged on the F2 FPGA. On
hardware the region markers are no-ops (§2). A hardware run therefore
gives the program's own `SIGIL PERF` lines (`mcycle`/`minstret`) and
its UART output, but not the event counters of §3. Comparing hardware
with simulation means comparing the same image's `HW-counter cycles`
(`hw_cycles` in `results.csv`) with the simulated ones.

The scripts are in
[`docs/evidence/perf-f2-56-2026-10-22/scripts/`](evidence/perf-f2-56-2026-10-22/scripts/):

| Step | Where | Script |
|---|---|---|
| 1. Build the images with the harness's make arguments and record their sha256 | build host (sigil-verify) | `build_images.sh`, writes `SHA256SUMS` |
| 2. Launch one `f2.6xlarge` from the FPGA Developer AMI with a hard cap | AWS | `user-data.sh` (`shutdown -h +55`), with shutdown behaviour `terminate` |
| 3. Copy `bins/`, `fpga/host/` (as `host/`) and the two instance scripts to `~/f2perf` | | |
| 4. Build `sigil_host` against aws-fpga and load the AFI | instance | `setup_f2.sh` |
| 5. Check the image sha256s, then run every image 3 times (the 1000-iteration CoreMarks twice) | instance | `run_f2.sh` |
| 6. Validate against the simulation logs of the same images, then tabulate | build host | `f2_validate.py`, `f2_report.py` |

Each run is:

```sh
sudo ./host/sigil_host --ignore-mem-err --bin bins/<image>.bin --timeout 60 \
     --exit "SIGIL TEST PASS <bench>" --fail "SIGIL TEST FAIL" --log logs/<image>.r<k>.uart
```

`--ignore-mem-err` is the #62 workaround the current AFI needs.

A hardware run counts as a result only if `f2_validate.py` finds all
of the following:

1. `sigil_host` exited 0 on `SIGIL TEST PASS`. The program prints this
   only after its own CRC, KAT or known-answer checks pass.
2. There was no UART TX overflow.
3. Every `expect` line is present.
4. There is exactly one `SIGIL PERF` line per declared region.
5. The UART output equals the simulation output of the same image, line
   for line. Only numbers on timing lines may differ. Every CHECK, KAT
   and CRC line must be byte-identical, which also catches dropped
   UART bytes.

The images must be byte-identical to the simulated ones; `run_f2.sh`
checks the sha256s on the instance.

Compare against the simulation of the AFI's own design (§4). See
[`docs/FPGA_F2.md`](FPGA_F2.md) ("Flash Sigil on your own F2", and the
cost guardrails) for loading an AFI. Terminate the instance when done.
The last full run used 5 min 35 s of instance time.

## 11. Baseline: main `eeaa332`

This is the reference that #53 and every later change is compared
against (§1, `perf_report.py --diff`).

### 11.1 What was measured

- **Design.** Main `eeaa332` RTL plus the simulation-only counters
  (`rtl/` tree `89b98cb227c6`). No #53 pipelining is included.
  - With `SYNTHESIS` defined, the preprocessed RTL is byte-identical to
    `eeaa332` for every flow's defines (`synth-view-diff.log`).
  - The existing gates are unchanged on this RTL. `make core-test` gives
    the same `TB PASS` lines and cycle counts as main, coverage is
    identical, and riscv-tests pass 123/123 (`perf-dhrystone-56`
    `gates.log`).
- **Simulation.** `run_baseline.sh` at `8d15410` ran on sigil-verify on
  2026-10-22 from 11:20 to 11:41Z. Tools: Verilator 5.048,
  riscv64-unknown-elf-gcc 16.1.0 and Python 3.12.3.
  - Each configuration (`default`, `sky130`, `fpga`) was run with
    `make -C sim perf CONFIG=<config> MEM="soc axi" REPEAT=2 JOBS=12`.
  - That is 14 images, 168 simulations and 2136 region results. All are
    valid, and both repeats are identical.
  - The images are bit-identical across the three configurations.
  - `default` is identical to every earlier #56 evidence set.
- **Hardware.** The same 14 images, plus two 1000-iteration CoreMark
  images, ran on an `f2.6xlarge` with the public AFI
  `agfi-035116450e0a0d093`. The core clock measured 62.500 MHz. The run
  was on 2026-10-22 from 11:25 to 11:28Z.
  - All 46 runs are valid.
  - In 178 of 180 regions, the hardware retired exactly the simulated
    instruction count. The 2 exceptions are SHA-512 accelerator poll
    loops, whose iteration count depends on timing.

### 11.2 Dhrystone and CoreMark

`scalar` means
`-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`
(the headline). `sdk` means the SDK default `-march`, which includes V.
Both are built with `-O2`. The F2 hardware column is the median of
the repeats. Its cycles are the program's own counter window, which is
a few tens of cycles shorter than the marker window that the
simulation columns use (§2).

| Benchmark | default soc | default axi | sky130 soc | sky130 axi | fpga soc | fpga axi | F2 hardware |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Dhrystone scalar, DMIPS/MHz** | **0.371** | 0.371 | **0.216** | 0.201 | 0.371 | 0.371 | **0.371** = 23.17 DMIPS |
| cycles (2000 runs) | 3,070,244 | 3,070,652 | 5,272,386 | 5,670,943 | 3,070,244 | 3,070,652 | 3,070,662 |
| IPC | 0.337 | 0.337 | 0.196 | 0.183 | 0.337 | 0.337 | 0.337 |
| Dhrystone sdk, DMIPS/MHz | 0.327 | 0.327 | 0.191 | 0.173 | 0.317 | 0.317 | 0.327 |
| **CoreMark scalar, CoreMark/MHz** | **1.395** | 1.395 | **0.868** | 0.867 | 1.395 | 1.395 | **1.395** = 87.19 CoreMark |
| cycles (20 iterations) | 14,337,806 | 14,339,056 | 23,030,662 | 23,060,820 | 14,337,806 | 14,339,056 | 14,339,138 |
| IPC | 0.366 | 0.366 | 0.228 | 0.228 | 0.366 | 0.366 | 0.366 |
| CoreMark sdk, CoreMark/MHz | 1.372 | 1.372 | 0.856 | 0.855 | 1.372 | 1.372 | 1.372 |
| CoreMark validation seeds | 1.392 | 1.392 | 0.867 | 0.865 | 1.392 | 1.392 | 1.392 |

- **CoreMark on hardware.** The 87.19 CoreMark figure comes from the
  1000-iteration image: an 11.47 s timed region at 62.5 MHz, with
  `Correct operation validated` for both seed sets. It meets EEMBC's
  10 s rule in real time. It has not been submitted to EEMBC.
- **Same images.** The simulation figures and the hardware figures come
  from the same images.
- **Absolute figures.** At the #53 target of 100 MHz, `default` would
  give 37.1 DMIPS and 139.5 CoreMark. At the 25 MHz that the W7 sky130
  floorplan meets after global routing, `sky130` would give 5.4 DMIPS
  and 21.7 CoreMark. Both are arithmetic on the simulation cycles
  ([`derived.md`](evidence/perf-analysis-56-2026-10-22/counters/derived.md)).

### 11.3 Hardware against simulation

- **The AFI runs the `default` configuration.** In all 61 regions
  where `default` and `fpga` differ, the hardware is closer to
  `default`. For example, `vse8` at vl=512 takes 1,537.8 cycles on
  hardware, 1,537.8 in `default` and 2,049.8 in `fpga`. `fpga`
  therefore predicts the next AFI: vector code up to 29% slower (RVV
  memset), Dhrystone `sdk` +3.2%, and scalar code unchanged.
- **Agreement with `default`/`axi`.**
  - 145 of 180 regions are within 0.1%, and 165 are within 1%.
  - The 32 regions with no cache miss repeat cycle for cycle.
  - CoreMark at 1000 iterations is +1,336 cycles out of 716.8 M (the
    comparison is against `soc`).
  - The SHA chains are within 0.001%.
- **The gap is in the memory model.** Only the cache-miss
  microbenchmarks show it.
  - A line refill costs about 1.5 cycles more on F2's DDR4 path than in
    the 24-cycle model. A dependent D$ miss takes 40.6 cycles on F2,
    against 39.1 in the model.
  - A dirty write-back costs about 10 cycles less.
  - Kernel regions land between 1.2% faster and 0.2% slower than the
    model.
  - Against the ideal 1-cycle `soc` memory, a dependent miss costs 2.9x
    as much (40.6 against 14.1 cycles). CoreMark and Dhrystone fit in
    the L1s, so they do not notice.

### 11.4 Kernels: RVV over scalar C

The table gives the speedup of RVV intrinsics over the scalar C of the
same configuration and memory model, with GCC 16 `-O3`
auto-vectorization in brackets.

| Kernel | C cycles/call (default soc) | default soc | default axi | sky130 soc | sky130 axi | fpga soc | F2 hardware |
|---|---:|---:|---:|---:|---:|---:|---:|
| vadd_i32 | 19,520 | 1.81x (1.55x) | 1.72x | 2.04x | 1.74x | 1.65x | 1.73x |
| vadd_i64 | 9,842 | 1.77x (1.38x) | 1.68x | 1.83x | 1.50x | 1.61x | 1.69x |
| daxpy | 14,988 | 1.66x (1.40x) | 1.66x | 1.83x | 1.61x | 1.57x | 1.66x |
| saxpy | 32,904 | 1.86x (1.67x) | 1.85x | 2.20x | 1.99x | 1.75x | 1.85x |
| ddot | 12,857 | 1.63x (1.00x) | 1.63x | 1.89x | 1.68x | 1.62x | 1.63x |
| idot_i32 | 19,500 | 1.51x (1.24x) | 1.51x | 1.87x | 1.72x | 1.51x | 1.51x |
| memcpy | 8,280 | 2.51x (1.00x) | 2.46x | 2.24x | 1.72x | 2.17x | 2.47x |
| memset | 5,208 | 2.96x (1.00x) | 2.96x | 3.05x | 3.01x | 2.29x | 2.95x |
| dgemm 32×32 | 721,504 | 1.85x (1.00x) | 1.82x | 2.97x | 3.85x | 1.84x | 1.82x |
| sgemm 32×32 | 809,562 | 2.07x (1.00x) | 2.07x | 2.90x | 3.14x | 2.06x | 2.07x |
| fir_f32 | 479,294 | 2.56x (1.28x) | 2.56x | 3.48x | 3.47x | 2.55x | 2.56x |
| mac_i8 | 86,059 | 1.73x (1.40x) | 1.73x | 2.22x | 2.15x | 1.73x | 1.73x |
| mac_i16 | 43,052 | 1.85x (1.66x) | 1.85x | 2.30x | 2.17x | 1.85x | 1.85x |

The `e8` forms of memcpy and memset run at 0.29x to 0.49x of C
everywhere. §12.4 explains why most of the RVV advantage is the
scalar code's fetch cost.

### 11.5 What changes between configurations

- **`fpga` (`VRF_OREG`) changes only vector code.** Its 210 results
  with no vector instruction are identical to `default`. Of its 146
  vector results, 122 are slower:
  - vector arithmetic costs +1 cycle per instruction;
  - a unit-stride store costs +1 cycle per element, so `vse8` at
    vl=512 goes from 1,537.6 to 2,049.6 cycles;
  - as a result, Dhrystone `sdk` is +3.2%, SHA-256 RVV ×16 +4.6%,
    memcpy RVV +15.5% and memset RVV +29%.
- **`sky130` is 1.58–1.85x slower on scalar code.** The registered SRAM
  reads (`SRAM_OREG`) cause most of it:
  - the fetch issue gap grows from 2 to 3 cycles;
  - a load takes 5 cycles instead of 2.5;
  - load-use takes 8 cycles instead of 4;
  - a taken branch takes 6 instead of 4, and call/return 15 instead
    of 10.

  The 4 KiB direct-mapped L1s add the rest:
  - Dhrystone gets 8,004 D$ misses and 6,004 write-backs. They cost
    4.0% of cycles on `soc` and 10.7% on `axi`.
  - An 8 KiB random working set misses on every access.

  The M unit and the FPU have the same latencies in all three
  configurations. Vector code loses less, so RVV speedups over C are
  larger in `sky130`.
- **Memory model.** In `default` and `fpga`, the 24-cycle `axi` model
  adds less than 0.02% to Dhrystone and CoreMark. It adds up to 6.8% to
  the kernels and 8% to the bulk accelerator hashes. The I$ miss
  penalty is 12 cycles on `soc` and 37 on `axi`. The D$ miss penalty is
  12–30 cycles on `soc` and 37–88 on `axi`; misses that also write back
  a dirty line cost more.

## 12. Where the cycles go

Sources:
- The accounting is from the baseline (`<config>/results.csv`,
  `headline.md`).
- Derived ratios are in
  [`perf-analysis-56/counters/derived.md`](evidence/perf-analysis-56-2026-10-22/counters/derived.md).
- Per-mechanism costs are from the `micro_*` benchmarks.

### 12.1 The accounting

Each cell is a percentage of the region's cycles, for `default` with
`soc` memory. Every cycle is charged to exactly one category (§3).
`redirect` is `stk_branch + stk_jal + stk_jalr`.

| Region | IPC | retire | fetch_lat | straddle | redirect | loaduse | muldiv / fpu | vec | vls | dc_lat | dc_miss soc (axi) | io |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| CoreMark scalar | 0.366 | 36.6 | 40.4 | 5.4 | 4.8 | 0.7 | 2.6 | | | 9.5 | 0.0 (0.0) | |
| CoreMark sdk | 0.359 | 35.9 | 40.5 | 5.9 | 4.8 | 0.7 | 2.6 | 0.1 | 0.2 | 9.3 | 0.0 | |
| Dhrystone scalar | 0.337 | 33.7 | 40.6 | 8.9 | 3.7 | 0.1 | 0.2 | | | 12.7 | 0.0 (0.0) | |
| Dhrystone sdk | 0.293 | 29.3 | 32.9 | 4.4 | 3.6 | 0.0 | 0.2 | | **19.3** | 10.3 | 0.0 | |
| SHA-256 C | 0.366 | 36.6 | 45.9 | 11.4 | 1.4 | | | | | 4.7 | | |
| SHA-256 Zknh | 0.395 | 39.5 | 44.7 | 6.9 | 2.1 | | | | | 6.9 | | |
| SHA-256 RVV ×16 | 0.046 | 4.6 | 3.6 | 0.0 | 0.0 | | | **89.6** | 2.1 | 0.1 | | |
| SHA-256 accelerator, block API | 0.278 | 27.8 | 33.4 | 3.3 | 4.2 | | | | | 9.6 | | **21.7** |
| SHA-256 accelerator, byte API | 0.360 | 36.0 | 40.9 | 7.9 | 2.4 | | 0.1 | | | 8.3 | | 4.4 |
| SHA-512 accelerator chain | 0.400 | 40.0 | 41.9 | 2.4 | 3.7 | | | | | 5.5 | | 6.5 |
| SHA3-256 accelerator chain | 0.396 | 39.6 | 42.2 | 3.5 | 3.3 | | | | | 5.5 | | 5.8 |
| bulk SHA-512 accelerator | 0.242 | 24.2 | 30.2 | 0.0 | 6.0 | | | | | 12.0 | 3.7 (11.0) | **23.9** |
| scalar C kernels (13) | 0.22–0.42 | 21.8–42.0 | 29.0–40.0 | 0–18.6 | 0–9.8 | | fpu 18.7–27.2 (FP), muldiv 9.5–10.5 (int MAC) | | | 7.1–15.7 | ≤ 0.8 | |
| RVV kernels (15) | | 0.3–3.4 | 0.3–4.0 | | | | | 0–71.0 | 26.0–99.2 | | ≤ 0.5 | |

`sky130`, `soc` (`axi` in brackets where it differs):

| Region | IPC | retire | fetch_lat | straddle | redirect | muldiv | vec | vls | dc_lat | dc_miss soc (axi) | io |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| CoreMark scalar | 0.228 | 22.8 | **60.6** | 3.1 | 0.0 | 1.6 | | | 11.9 | 0.0 (0.0) | |
| Dhrystone scalar | 0.196 (0.183) | 19.6 | **57.5** | 4.0 | 0.0 | 0.1 | | | 14.8 | **4.0 (10.7)** | |
| Dhrystone sdk | 0.171 (0.155) | 17.1 | 46.6 | 1.6 | 0.0 | 0.1 | | 16.9 | 12.1 | 5.6 (14.6) | |
| SHA-256 C | 0.232 | 23.2 | 63.6 | 7.2 | 0.0 | | | | 5.9 | | |
| SHA-256 Zknh | 0.248 | 24.8 | 62.2 | 4.3 | 0.0 | | | | 8.6 | | |
| SHA-256 RVV ×16 | 0.043 | 4.3 | 4.5 | | | | 88.2 | 2.7 | 0.2 | | |
| SHA-256 accelerator, block API | 0.197 | 19.7 | 53.7 | 1.6 | 0.0 | | | | 9.8 | | 15.1 |
| bulk SHA-512 accelerator | 0.176 | 17.6 | 48.4 | 0.0 | 0.0 | | | | 13.1 | 3.3 (9.6) | 17.4 |

`fpga` has the same accounting as `default` for every region with no
vector instruction. For Dhrystone `sdk`, `vls` is 21.8% in `fpga`.

### 12.2 The mechanisms

The table gives cycles per operation, net of the window, from the
`micro_*` benchmarks (`headline.md`). With `soc` memory, the `axi`
model is within 0.1 cycles of these for everything except the misses.

| Operation | default (= fpga) | sky130 |
|---|---:|---:|
| any ALU instruction, 32-bit or 16-bit, dependent or not | 2.03 | 3.04 |
| 32-bit instruction straddling a 4-byte fetch word | 4.05 | 6.08 |
| branch not taken / taken; `jal` | 2.03 / 4.03; 4.02 | 3.04 / 6.05; 6.04 |
| call + return | 10.03 | 15.04 |
| `ld` hit, independent; `sd` hit | 2.53; 2.53 | 5.04; 5.04 |
| `ld` hit, dependent (load to load); `ld` + use (per pair) | 3.02; 4.02 | 5.04; 8.04 |
| `mul`; `div` (63 quotient bits) | 4.14; 36.1 | 4.17; 36.1 |
| `fadd.d`; `fmadd.d`; `fdiv.d` | 6.13; 8.13; 33.1 | 6.22; 8.18; 33.2 |
| `vadd.vv` e8, vl = 512 | 518.1 (fpga 519.1) | 519.1 |
| `vle8.v` / `vse8.v`, vl = 512 | 1,537.6 / 1,537.6 (fpga 2,049.6) | 2,051.3 / 2,563.2 |
| uncached access to the crypto engine (`dc_unc_cyc / dc_unc`) | 5.0 | 5.0 |
| dependent D$ miss: `soc` / `axi` / F2 hardware | 14.1 / 39.1 / 40.6 | 17.2 / 42.2 |
| I$ miss penalty: `soc` / `axi` | 12 / 37 | 13 / 38 |

Five facts explain most of §12.1:

1. **Fetch delivers at most one instruction every 2 cycles (3 on
   sky130).**
   - The I$ accepts one request per lookup, and the core issues the
     next fetch only after the previous response.
   - Each instruction fetches its own aligned 32-bit word. The second
     half of a word holding two compressed instructions is fetched
     again, so a 16-bit instruction costs the same as a 32-bit one.
   - A 32-bit instruction at `pc % 4 == 2` takes two fetches.
2. **There is no prediction.** A taken branch, `jal` or `jalr` costs 2
   more cycles than falling through (3 on sky130). The cost depends
   only on the outcome.
3. **Every load and store holds MEM for 1 cycle (2 on sky130).** On
   `default`, only about half of that cycle shows: an independent load
   costs 2.53 cycles against 2.03 for an ALU op, because the frozen
   cycle overlaps the fetch gap. On sky130 the full 2 cycles show.
4. **The M unit, the FPU and the vector unit do not overlap work.**
   Every operation costs its EX occupancy plus about 1 cycle, and
   dependent and independent sequences cost the same.
   - Vector arithmetic takes N + 4 cycles in EX; FP multiply-add takes
     8N + 4.
   - A vector unit-stride load or store takes 3 cycles per element
     (`stk_vls` = 3N) at any element width.
5. **An uncached access costs 5 cycles** (1 `dc_lat` + 4 `io`). The
   accelerator drivers make one such access per 32-bit word.

### 12.3 The fetch port is saturated

The I$ port is busy for `ic_access × 2` cycles (× 3 on sky130).

| Region | I$ port busy | I$ accesses per instruction | bytes per instruction | 16-bit share | taken redirects per instruction |
|---|---:|---:|---:|---:|---:|
| CoreMark scalar | **94.9%** | 1.30 | 2.97 | 51.4% | 0.142 |
| Dhrystone scalar | **97.8%** | 1.45 | 2.53 | 73.7% | 0.174 |
| SHA-256 C | **98.9%** | 1.35 | 3.25 | 37.4% | 0.039 |
| SHA-256 Zknh | 97.4% | 1.23 | 2.90 | 55.0% | 0.054 |
| SHA-256 accelerator, block API | 78.3% | 1.41 | 2.72 | 64.1% | 0.189 |
| bulk SHA-512 accelerator | 72.4% | 1.50 | 2.51 | 74.4% | 0.248 |
| SHA-256 RVV ×16 | 9.3% | 1.01 | 4.00 | 0.2% | 0.001 |
| sky130 CoreMark scalar | 87.3% | 1.28 | 2.97 | 51.4% | 0.142 |

- **Scalar code runs at 95–99% of its fetch ceiling.** CoreMark needs
  2.97 bytes per instruction, but the port delivers 2 bytes per cycle,
  so its IPC cannot exceed about 0.5 however the rest of the core
  behaves.
- **Most execution-side stalls are hidden.** Changes that leave fetch
  alone (faster M unit or FPU, dual issue, multithreading) can win back
  at most the cycles the port is idle: 5.1% on CoreMark, 2.2% on
  Dhrystone, 1.1% on SHA-256 C.
- **Vector and accelerator regions are the exception.** In the RVV
  regions the port is 1–9% busy, so the vector unit is the bottleneck.
  In the accelerator regions it is 72–78% busy, and the uncached I/O
  takes up to 24% of cycles.

### 12.4 Reading the accounting correctly

The accounting is exact: every cycle is charged once. Three categories
still need care, because they record where a bubble was *created*, not
what removing that bubble would save. The front-end model and the
`micro_*` results settle each one.

- **`redirect` understates branch cost about 2x.**
  - The category counts only squashed wrong-path slots. The refetch
    after a redirect is charged to `fetch_lat` (§3).
  - A taken transfer costs 2.0 cycles (`br_taken` 4.03 against `br_nt`
    2.03). CoreMark has 744,296 of them (`br_taken + jal_redir +
    jalr_redir`), which is 1.49 M cycles or 10.4%, against the 4.8% that
    `redirect` shows. Dhrystone: 11.7%, against 3.7%.
  - On sky130, `redirect` is 0.0% everywhere, yet a taken branch costs
    3 cycles more than a fall-through. The 3-cycle fetch never puts a
    wrong-path instruction into a slot, so the whole cost lands in
    `fetch_lat`.
- **`dc_lat` overstates the cost of a D$ hit about 2x on `default`.**
  - `stk_dc_lat` is exactly 1 cycle per access (CoreMark: 1,365,092 =
    `dc_load + dc_store`).
  - Only about 0.5 cycle of it shows: `ld_indep` and `st` cost 2.53
    against 2.03 for an ALU op.
  - Once fetch stops being the limit, the whole cycle shows. That is
    why D$ work is worth about twice as much after the fetch fix
    (§14).
- **`muldiv` overstates `mul` about 2x.** CoreMark's 187,920 `mul`
  each hold EX for 2 cycles (375,840). In mixed code the I$ prefetches
  one word during the hold, so the marginal cost is about 1 cycle per
  `mul`.

### 12.5 Per benchmark

- **CoreMark** (IPC 0.366).
  - **The front end costs 45% of cycles (model).** Of that, the issue
    gap is 25.0%, taken redirects 11.9% and straddles 8.1%.
  - **Taken transfers.** There are 744,296 (14.2% of instructions):
    617,615 branches, 83,907 `jal` and 42,774 `jalr`. 708,693
    instructions straddle a fetch word (13.5%).
  - **Memory.** CoreMark fits in the L1s: 39 I$ and 11 D$ misses cost
    0.01%, and the bus is 0.0% busy. `axi` adds 1,250 cycles. On F2
    hardware, 1000 iterations come within 0.0002% of the 1-cycle model.
  - **Execution side.** D$ hits take 9.5% (about half exposed, §12.4),
    `mul` 2.6% (about half exposed) and load-use 0.7%.
- **Dhrystone `scalar`** (IPC 0.337). The front end costs 46.6%
  (model): issue gap 17.1%, redirects 16.7% and straddles 12.9%.
  Taken transfers are 17.4% of instructions, and 73.7% of instructions
  are 16-bit, which the fetch refetches. The 2,000 divides cost 0.2%.
- **Dhrystone `sdk`.** It runs the same scalar code, plus one 56-byte
  struct copy per run that GCC turns into `vle8`/`vse8`.
  - Each of those instructions takes 168 cycles (3 per byte), which is
    672,000 cycles or 19.3%; 21.8% on `fpga` and 16.9% on `sky130`.
  - The whole `sdk` build is 411,998 cycles slower than `scalar`. Hence
    0.327 against 0.371 DMIPS/MHz.
- **SHA-256 C and Zknh** — see §13.3. Both are front-end bound
  (57.3% and 51.6% of cycles), with the I$ port 97–99% busy.
- **RVV regions.** The vector unit is the bottleneck, and fetch is 1–4%.
  - SHA-256 RVV ×16: `vec` 89.6%.
  - Kernels: `vec` + `vls` is 95–99%. The FP kernels are dominated by
    `vfmacc` at 8 cycles per element (dgemm 68.5%, fir 71.0%). The
    integer MACs pay 5–6 cycles per element in the iterative vector
    multiplier (`vec` 45–50%). `vadd`, `memcpy` and `memset` are 86–99%
    `vls`.
- **Scalar C kernels.** IPC is 0.22–0.42. The I$ port is 67–100% busy.
  FP kernels lose 18.7–27.2% to the FPU: each `fmadd` holds EX for 6
  cycles, during which the I$ is idle 19–33% of the time.
- **Why RVV beats C.** Most of the RVV advantage is the scalar code's
  fetch cost. With the fetch and predictor fix of §14 (model F3+bim64),
  the scalar C kernels speed up 1.50–2.48x. RVV-over-C would then be
  0.98x for daxpy, 0.91x for ddot, 0.95x for idot_i32 and 0.99x for
  mac_i8, against 1.51–1.73x today. RVV code itself would not change.
- **Accelerator regions** — see §13.3. The CPU-side driver is
  front-end bound, and the uncached I/O takes 4.4–23.9%.

### 12.6 Memory: misses barely matter here

- **The headline benchmarks fit in the L1s.**
  - CoreMark: 39 I$ + 11 D$ misses. Dhrystone: 13 + 2. SHA chains:
    8 + 0.
  - Hot code is at most 6 KiB. `micro_imem` hits up to 8 KiB.
  - The `default` D$ hits random working sets of up to 16 KiB at 3.08
    cycles per dependent load.
- **Where misses do cost:**
  - **Bulk accelerator hashing.** 894 D$ misses: 3.7% on `soc` and
    11.0% on `axi`, at 12.2 and 37.7 cycles each.
  - **Kernels on `axi`.** At most 6.8% (vadd_i32/i64 RVV). The vector
    LS sequencer waits for these misses, so they show up as `vls`.
  - **sky130 Dhrystone.** Conflict misses in the 4 KiB direct-mapped D$.
  - **sky130 kernels above 4 KiB.** For example, dgemm C on sky130
    `axi`: `stk_dc_miss` 55.6%.
- **The core is latency-bound, not bandwidth-bound.** Bus occupancy is
  at most 32.5% (bulk accelerator on `axi`), with one line in flight.
- **Write-backs.** They are serialized ahead of the refill. Compared
  with a clean refill they add 15.8 cycles per line on `soc` and 44.9
  on `axi` (`stream_st` against `stream_ld`). On F2 they cost about 10
  cycles less than on `axi`.
- **F2 DDR4.** A dependent miss is 40.6 cycles at 62.5 MHz. About
  26.5 of those cycles (about 424 ns) are DDR and interconnect time,
  which is fixed in nanoseconds. A miss would therefore cost about 54
  cycles at 100 MHz. This is an *estimate*: §11.3 says to rerun
  `micro_dmem` at the new clock.

## 13. SHA-256: scalar, Zknh, RVV and the accelerator (#10)

Issue [#10](https://github.com/bubblebabyboi/sigil/issues/10) asks
where hashing throughput should live: on the scalar core, on the
vector unit, or on the accelerator.

**Answer: on the accelerator, through its block API.** It takes 572
cycles per hash. That is 17.3x plain C, 11.8x Zknh and 8.1x RVV ×16
running 16 chains at once, and F2 hardware gives the same counts. The
byte API and the bulk feed lose most of the engine's speed in the CPU
driver. That driver, not the engine, is what to improve next (§13.4).

### 13.1 Method

- **`sha256chain`** computes 1024 chained hashes of a 32-byte value,
  h<sub>i+1</sub> = SHA-256(h<sub>i</sub>). Each hash depends on the
  previous one, so the chain measures latency per hash.
  - RVV ×16 runs 16 independent chains in one multi-buffer kernel and
    reports aggregate throughput. Each single chain is 16x slower than
    that.
  - The SHA-512 chain hashes 64-byte messages on the accelerator; the
    SHA3-256 chain also runs on the accelerator.
- **`sha256chain_bulk`** hashes one 64 KiB buffer. There is no SHA-256
  accelerator row, because that engine has no chaining (block API
  only).
- **Checks.** Each implementation passes the FIPS 180-4/202 known
  answers before its region. After the region, every result, including
  all 16 RVV lanes, is checked against Python `hashlib`.
- **Build.** The SDK `-march` (with V) and `-falign-functions=64`.
  Without that alignment, the SHA-512 chain took 43% more cycles.
- **Implementations.** [`sw/bench/sha256chain/README.md`](../sw/bench/sha256chain/README.md).

### 13.2 Results

Cycles per hash, `soc` (the `axi` model is within 0.02%), with the
speedup over plain C in brackets. The F2 column is the median of the
hardware repeats. Hashes/s at 62.5 MHz are measured on F2 hardware.
The 100 MHz (#53 target, `default`) and 25 MHz (W7 sky130 floorplan,
`sky130`) columns are arithmetic on the simulation cycles.

| Implementation | default | sky130 | fpga | F2 hardware | hashes/s, F2 at 62.5 MHz | at 100 MHz | sky130 at 25 MHz |
|---|---:|---:|---:|---:|---:|---:|---:|
| plain C | 9,918.2 | 15,634.4 | 9,918.2 | 9,918.4 | 6,301 | 10,082 | 1,599 |
| C + Zknh | 6,753.2 (1.47x) | 10,747.4 (1.45x) | 6,753.2 (1.47x) | 6,753.4 | 9,255 | 14,808 | 2,326 |
| RVV ×16 multi-buffer | 4,642.0 (2.14x) | 4,949.1 (3.16x) | 4,854.6 (2.04x) | 4,642.6 | 13,462 | 21,542 | 5,051 |
| **accelerator, `sigil_sha256_block`** | **572.1 (17.34x)** | **792.2 (19.74x)** | 572.1 (17.34x) | **572.1** | **109,250** | 174,797 | 31,559 |
| accelerator, `sigil_sha256` (byte API) | 2,793.1 (3.55x) | 4,422.2 (3.54x) | 2,793.1 (3.55x) | 2,793.3 | 22,375 | 35,802 | 5,653 |
| SHA-512 chain (64 B), accelerator | 2,472.2 | 3,775.3 | 2,472.2 | 2,472.3 | 25,280 | 40,450 | 6,622 |
| SHA3-256 chain, accelerator | 1,370.1 | 2,120.2 | 1,370.1 | 1,370.1 | 45,616 | 72,986 | 11,791 |

Bulk hashing of 64 KiB, in bytes per cycle (MB/s = bytes/cycle × MHz):

| Implementation | default soc | default axi | sky130 soc | fpga soc | F2 hardware | MB/s on F2 |
|---|---:|---:|---:|---:|---:|---:|
| SHA-256 plain C | 0.0065 | 0.0065 | 0.0041 | 0.0065 | 0.0065 | 0.40 |
| SHA-256 Zknh | 0.0095 | 0.0095 | 0.0060 | 0.0095 | 0.0095 | 0.59 |
| SHA-256 RVV ×16 (16 segments) | 0.0131 | 0.0130 | 0.0121 | 0.0124 | 0.0130 | 0.81 |
| SHA-512 accelerator | 0.2388 | 0.2205 | 0.1740 | 0.2388 | 0.2195 | 13.72 |
| SHA3-256 accelerator | 0.2398 | 0.2215 | 0.1748 | 0.2398 | 0.2206 | 13.78 |

### 13.3 Where the cycles go

Figures are for `default`/`soc`; the per-hash numbers are in
[`derived.md`](evidence/perf-analysis-56-2026-10-22/counters/derived.md).

- **Plain C is bound by the front end.**
  - It runs 3,627 instructions per hash at IPC 0.366.
  - Fetch latency plus straddles take 57.3% of cycles, with the I$
    port 98.9% busy.
  - 31% of its instructions are 32-bit instructions that straddle a
    fetch word (model).
- **Zknh speeds things up only by cutting instructions.**
  - It runs 2,667 instructions per hash, 26.5% fewer.
  - The Zknh instructions are single-cycle, but they run into the same
    fetch ceiling (I$ port 97.4% busy).
  - So 1.47x is the instruction-count reduction, nothing more.
- **RVV ×16 is bound by the vector unit.**
  - It issues 213,131 vector instructions at vl = 16, e32, each taking
    N + 4 = 19.98 EX cycles. `vec` is 89.6% of cycles and fetch 3.6%.
  - It escapes the fetch ceiling, which is also why sky130 slows it by
    only 6.6%, against 57.6% for C. That gives 3.16x over C there.
  - `fpga` (`VRF_OREG`) makes it 4.6% slower.
- **The accelerator's block API spends its time in the CPU.**
  - Per hash: 159 instructions plus 31 uncached 32-bit accesses (16
    DIN stores, 1 CTRL store, 8 DOUT loads, about 6 status polls).
  - `io` is 124 cycles per hash (21.7%), and the driver's own fetch
    takes most of the rest.
  - The engine compresses a block in 64 cycles (1 round per cycle,
    `rtl/crypto/sha256_block.sv`). About 89% of the 572 cycles are
    therefore the CPU feeding and reading it.
- **The byte API costs 4.9x the block API on the same engine.**
  - It runs 846 more instructions per hash, all byte packing and
    unpacking in `sw/sdk/lib/accel.c`.
  - It makes the same 31 uncached accesses.
- **The bulk accelerator feed is limited by the driver loop.**
  - The loop (`lw` from the buffer, `sw` to HDATA, `addi`, `bne`) takes
    16.75 cycles per 32-bit word on `soc`: retire 4.06, fetch 5.06,
    `io` 4.01, `dc_lat` 2.01, branch 1.00, and D$ misses 0.61 (2.00 on
    `axi`).
  - That gives 0.239 bytes/cycle. The SHA-512 engine could take 1.6
    bytes/cycle (128 bytes per 80-cycle compression, `docs/SPEC.md`).

### 13.4 What would move these numbers

These are the hashing items of §14. Every speedup is an *estimate*
unless marked as a model result.

| Change | Gain | Kind |
|---|---|---|
| Pack the `sigil_sha256` byte API by word (software only) | The 846 extra instructions per hash fall to about 40: 2,793 → about 690 cycles/hash (about 4x) | estimate |
| Posted uncached stores (§14, #5) | Block API 572 → about 504 cycles/hash (1.13x); bulk SHA-512/SHA3 1.26–1.32x | estimate |
| 64-bit HDATA writes, with the posted stores | Bulk about 2.5x (each feed iteration moves 8 bytes) | estimate |
| Hash DMA from RAM, SHA-256 stream mode | Bulk SHA-512 limited by the engine at 1.6 B/cycle, about 6.7x | estimate |
| Decoupled fetch and branch prediction (§14, #1–2) | C 2.15x / 2.32x; Zknh 1.85x / 2.07x; RVV and accelerator about 1.0x | model |
| Vector back-to-back issue | RVV ×16 about 1.20x | estimate |

Even after the front-end fix, plain C would take about 4,300 cycles
per hash and Zknh about 3,300 (model), against 572 on the accelerator.
SHA-256 throughput belongs on the accelerator. The scalar, Zknh and
RVV paths are fallbacks; RVV ×16 is the best of them when 16
independent messages are available.

## 14. Upgrade candidates

This section ranks upgrades to the `eeaa332` core. It covers the
roadmap items (branch predictor, superscalar, multithreading,
multicore) and the changes the data says matter more.

Three analyses fed it: front end and control flow, memory hierarchy
and LSU, and execution units and parallelism. They are kept as written
in
[`perf-analysis-56/analyses/`](evidence/perf-analysis-56-2026-10-22/analyses/).
This section reconciles them. §14.5 lists where they disagreed and
which evidence decided each point. Claims the counters do not support
were dropped.

**How to read the figures.**
- **Speedups** are relative to today's cycles, measured on `default`
  with `soc` memory unless noted. `fpga` is identical on scalar code.
  - *Model* figures are from the RTL-calibrated front-end model
    ([`whatif.md`](evidence/perf-analysis-56-2026-10-22/frontend-model/whatif.md)).
  - *Estimate* figures are counter arithmetic under a stated
    assumption.
  - *Bound* figures assume the targeted cycles disappear completely.
- **Area** is nangate45, against the 689 kµm² SoC (`docs/SOC_AREA.md`).
  LUT counts are against the SoC's roughly 80 k LUTs on the VU47P
  (F0 implementation).
- **Costs** are bottom-up estimates; none was synthesized.
- **fmax risk** is judged against the #53 timing path families.

### 14.1 Ranked list

| # | Candidate | Roadmap item | Fixes (counter evidence) | Speedup | Area / FPGA | fmax risk | Verification |
|---:|---|---|---|---|---|---|---|
| 1 | **Decoupled 64-bit fetch.** Return the I$'s full 64-bit word, add a 2-entry doubleword queue with a parcel aligner, and prefetch the next block while the I$ is idle. | — | I$ port 95–99% busy. `fetch_lat` + straddle = 45.8% of CoreMark, 49.5% of Dhrystone, 57.3% of SHA-256 C. 2.97 bytes per instruction against 2 bytes per cycle delivered. | *Model*: CoreMark **1.41x** (1.395 → about 1.96/MHz), Dhrystone **1.43x** (0.371 → about 0.53), SHA-256 C 2.15x, Zknh 1.85x, scalar C kernels 1.25–1.60x. sky130: CoreMark 1.75x, Dhrystone 1.72x. RVV about 1.0x. Without the response bypass: 1.27x / 1.29x. | 2.3–4.0 kµm² (0.35–0.6%); 250–600 LUT, 240–300 FF | low–medium | medium–high, 1–4 weeks |
| 2 | **Branch prediction on top of #1.** 64-entry bimodal BHT, predecoded branch and `jal` targets (no BTB), 4-entry RAS. Mispredicts use the existing EX flush. | **branch predictor** | 744,296 taken transfers on CoreMark (14.2% of instructions) and 179,999 on Dhrystone (17.4%). Each costs 2 cycles today and 3 after #1. bim64 accuracy is 92.1% (CoreMark) and 96.5% (Dhrystone); RAS-4 is 99.7% / 100%. | *Model*, cumulative with #1: CoreMark **1.70x** (about 2.37/MHz, +21% over #1), Dhrystone **1.80x** (about 0.67, +26%), SHA-256 C 2.32x, C kernels 1.50–2.48x. sky130: 2.08x / 2.13x. With a one-bubble target path: 1.59x / 1.70x. Static BTFN + `jal` + RAS-4 only: 1.66x / 1.77x. | 4.2–5.2 kµm² (0.6–0.8%); about 350 LUT, 400 FF | medium (zero-bubble), low–medium (one-bubble) | medium, 2–3 weeks |
| 3 | **D$ hits without the MEM freeze.** Launch the array read from the #53 EX address unit, compare tags in MEM, and add a 1-entry store buffer. | — | `stk_dc_lat` is exactly 1 cycle per access: 1,365,092 cycles = 9.5% of CoreMark, 12.7% of Dhrystone. About 0.5 cycle of it shows today, and all of it after #1–2. | *Estimate*: today 1.05x (CoreMark) and 1.07x (Dhrystone). After #1–2, at most **1.19x / 1.30x** on top (*bound*: the freeze is 16% / 23% of the model's cycles). | about 2.5 kµm² (0.4%); 300 LUT, 150 FF | medium–high (may relieve #53 family A) | high, 2–3 weeks |
| 4 | **Vector unit-stride LS packing.** One 64-bit D$ access per aligned 8 bytes instead of one per element. | — | 3 cycles per element at every SEW. Dhrystone `sdk` struct copy: 672,000 cycles (19.3%). `vls` share: memcpy-e8 99.2%, memset-e8 94.8%, vadd_i32 87.9%. | *Estimate* (`vls × (1 − 1/k)`): Dhrystone `sdk` **1.20x** (0.327 → 0.393 DMIPS/MHz; `fpga` 1.24x), memcpy-e8 7.6x, memset-e8 5.9x, vadd_i32 1.78x, mac_i8 1.76x, mac_i16 1.66x, saxpy 1.35x. e64 kernels 1.0x. No change on scalar code. | 2.5–4 kµm² (0.4–0.6%); 300–600 LUT | medium (VRF→D$ is the F2 critical family) | high, about 2 weeks |
| 5 | **Accelerator feed.** A 2-entry posted uncached-store buffer on the core side, then 64-bit HDATA writes, then SDK loop unrolling. | — | An uncached access takes 5.0 cycles (1 `dc_lat` + 4 `io`). The block API makes 31 per hash (`io` 21.7%). Bulk feed: 16.75 cycles per 4-byte word, `io` 4.0 of them. Bus at most 32.5% busy. | *Estimate*: posted stores alone give bulk SHA-512/SHA3 1.26–1.32x and the block API 1.13x. With 64-bit HDATA, bulk about 2.5x. No change elsewhere. | about 3.4 kµm² (0.5%); 260 FF, 150 LUT | low | medium (I/O ordering, CLINT/PLIC side effects, imprecise I/O store errors) |
| 6 | **Pipelined FPU** (one op per cycle for add, mul and FMA), so the vector unit can stream FP elements. | — | `vfmacc` takes 8 cycles per element. `stk_vec` matches 8N + 4 exactly (dgemm 1,069,568). `vec` share: dgemm 68.5%, sgemm 68.4%, fir 71.0%. | *Estimate*: dgemm/sgemm 2.32x, fir 2.56x, ddot 1.81x, saxpy 1.67x, daxpy 1.64x. No change on CoreMark, Dhrystone or SHA. | 4–8 kµm² (0.6–1.2%); about 600 FF, 300–600 LUT, no DSP | low | medium |
| 7 | **Vector integer multiply on the M unit's pipelined multiplier.** | — | `vwmul`/`vwmacc` take 5–6 cycles per element in the iterative vector multiplier. `vec` share: mac_i8 49.7%, idot 49.2%. | *Estimate*: mac_i8 1.49x, mac_i16 1.54x, idot_i32 1.65x. Combined with #4: mac_i8 about 4.2x. | about neutral; frees about 4 DSPs | low–medium | medium |
| 8 | **Smaller items** (§14.2) | — | | 1–30% on narrow workloads | | | |
| 9 | **Dual core**: two `sigil_cpu` on a 2-master fabric with coherent D$s. | **multicore** | Bus is 0.0% busy on CoreMark and Dhrystone. Private I$s escape the saturated port. | *Estimate*: 2.0x aggregate throughput on independent, cache-resident work. Single-thread 1.0x. Per-MHz scores unchanged. Bulk hashing 1.0x (one accelerator). | +585 kµm² (+85%); +55 k LUT | low per core, medium on the fabric | very high (coherence, LR/SC, per-hart CLINT/PLIC, multi-hart boot and SBI) |
| 10 | **In-order dual issue.** | **superscalar** | The I$ port is 94.9% busy (CoreMark), so a second issue slot would wait on the same fetch. | *Bound*: today at most **1.053x** CoreMark, 1.022x Dhrystone, 1.011x SHA C. After #1–3 it can shorten only the retire cycles (62% of the model's #1+#2 CoreMark cycles). The pairing rate is unmeasured, so there is no figure (§14.5). | +40–50 kµm² (+6–7%); +6–10 k LUT | high | very high |
| 11 | **Fine-grained multithreading**, 2 threads. | **multithreading** | Both threads share the same saturated I$ port. The stalls it would hide (`dc_lat`, redirects, `muldiv`) already overlap the fetch gap. | *Bound*: today at most 1.053x aggregate on CoreMark and 1.022x on Dhrystone, single-thread 1.0x or worse. After #1–2, at most about 1.6x aggregate (single-issue IPC ≤ 1 against the model's 0.62). | about +150 kµm² (+22%); +15–20 k LUT | medium–high | very high (per-thread privilege and H-extension state) |

### 14.2 Smaller items

| Candidate | Speedup | Cost | Note |
|---|---|---|---|
| Non-blocking scalar `mul` (2-stage side pipe) | CoreMark 1.013–1.027x today (*estimate*). Worth about twice that after #1. mac_i8/idot C 1.05–1.12x. | under 2 kµm² | Bundle it with #1. |
| Back-to-back vector issue (hide the +4 per instruction) | SHA-256 RVV ×16 about 1.20x (*estimate*) | 1–2 kµm² | Chaining VLS with arithmetic is bounded at 1.4–2.0x on the kernels, but costs about +40 kµm² for a second VRF write path. Not now. |
| Non-blocking scalar FP, after #6 | Scalar FP C kernels 1.18–1.29x (*estimate*) | 2–4 kµm² | Only for FP code that RVV does not cover. Verification is high. |
| I$ that accepts a request during a hit lookup, after #1 | +2.9% CoreMark on `default`; +7.6% CoreMark and +14.3% SHA C on sky130 (*model*) | about 0.5 kµm² | High fmax risk on FPGA: the tag compare would sit in front of the I$ enable, on #53 path family B. On sky130 the registered SRAM read already makes it a 2-stage pipeline. |
| 16-byte fetch blocks, sky130 respin | sky130 CoreMark +7.7% over #1 (*model*); `default` +3.8% | queue +2 × 64 b | The sky130 L1 macro already reads 128 bits. |
| D$ next-line prefetch (1-line stream buffer) | Bulk accelerator on `axi` 1.08x (*estimate*), about 1.14x at 100 MHz. No change on the headline benchmarks. | about 7.4 kµm² | Its value grows with the core clock on F2. |
| Write-back buffer (refill first, write the victim back after) | sky130 Dhrystone `axi` 1.046x. About 1.00x on `default`. | about 0.8 kµm² | `linebuf_q` already exists. |
| sky130 respin: 2-line D$ victim buffer | sky130 Dhrystone 1.04x (`soc`), 1.12x (`axi`) | about 0.06 mm² on sky130 | Next tapeout only. Do not disturb the in-flight GDS. |

**Software only (no RTL change).**

| Change | Effect | Kind |
|---|---|---|
| Keep `-falign-functions=64` on hot code | Without it, the SHA-512 chain takes 43% more cycles, SHA3 37% more and Zknh 6.8% more | measured |
| `-O2`, not `-O3` | CoreMark `-O3` is 19% slower (more straddles) | measured |
| Do not let GCC turn small struct copies into `vle8`/`vse8` (Dhrystone `sdk`) | `scalar` scores 0.371 DMIPS/MHz, against 0.327 for `sdk` | measured |
| Use e64, not e8, for RVV memcpy/memset | e8 runs at 0.29–0.49x of C; e64 at 2.5–3.0x | measured |
| Pack the `sigil_sha256` byte API by word | 846 extra instructions per hash, measured. 2,793 → about 690 cycles/hash | estimate |

### 14.3 Roadmap items: branch predictor, superscalar, multithreading, multicore

- **Branch predictor: yes, second.**
  - Build a small one: a 64-entry bimodal BHT, predecoded targets and
    a 4-entry RAS. A BTB or gshare does not pay (§14.4).
  - On today's fetch it gives 1.12x on CoreMark and 1.19x on Dhrystone.
    After the fetch fix (#1) the same hardware adds 21% and 26%, because
    a mispredict there costs 3 cycles against a 1-cycle baseline.
  - So sequence it after #1, or build it at the same time.
- **Superscalar: not now.**
  - Today the I$ port bounds it at 1.053x.
  - After #1–3 the retire cycles are 62–74% of the model's cycles, so
    dual issue would have something to shorten. How much depends on a
    pairing rate that nobody has measured.
  - The front-end model's traces can measure that rate cheaply. Do it
    before committing to dual issue's high fmax and verification cost.
- **Multithreading: last.**
  - It has the same 1.053x bound today.
  - After #1–2, two threads could give at most about 1.6x aggregate
    throughput on a single-issue pipe. That costs +22% area, plus a
    per-thread copy of the privilege and H-extension state.
  - Dual core is a better route to throughput.
- **Multicore: the only roadmap item that scales throughput.**
  - About 2.0x on independent, cache-resident work, for +85% area and
    heavy platform work: coherence, LR/SC across harts, per-hart
    CLINT/PLIC, and multi-hart SBI.
  - It leaves the per-MHz scores unchanged.
  - It does not fit the sky130 chip: the W7 floorplan already fails
    detail routing at about twice the available routing.
  - Consider it for the FPGA after #1–4, if throughput rather than
    single-thread speed is the goal.

### 14.4 Not recommended on this evidence

| Candidate | Why |
|---|---|
| Large or global predictors, BTB | gshare-4K beats bim64 by only 0.8% on CoreMark and 0.3% on Dhrystone (*model*), for 8 kbit. A 64-entry BTB instead of predecoded targets gives 1.117x against 1.118x for about 4.5 kbit. |
| Larger or more associative L1s | CoreMark's 39 + 11 misses cost 0.01%. Hot code is at most 6 KiB. Revisit with Linux traces (`micro_imem` above 8 KiB costs 2.5–4.0 cycles per instruction). |
| Non-blocking D$ with MSHRs; HBM; critical-word-first | Miss cycles on the headline benchmarks are at most 0.01%. The core is latency-bound with one line in flight. HBM latency is no better than DDR4. |
| Multi-lane vector integer datapath | SHA-256 RVV would gain about 2.2x, but the accelerator is already 8x faster than RVV. Cost +7–9% area on the F2 critical VRF path. |

### 14.5 Where the analyses disagreed

| Question | Front end | Memory | Execution | What decides | Result |
|---|---|---|---|---|---|
| How much does the fetch fix give CoreMark? | 1.41x (*model*) | 1.45x (1.43–1.52x). Counter arithmetic: 3.5 cycles per redirect, 0.3 load-use bubbles per load | not estimated; best single-issue case 54% of today's cycles | The model reproduces the RTL to 0.0002% and simulates load-use and post-redirect I$ occupancy, where the memory figure assumes them. The model's own floor with perfect prediction (IPC 0.67) agrees with the execution analysis (0.68). | **1.41x** |
| What does a taken branch cost? | 2 cycles: 10.4% of CoreMark | — | uses `stk_branch+jal+jalr` = 4.8% | `micro_pipe`: `br_taken` 4.03 against `br_nt` 2.03. On sky130 `redirect` is 0.0% while 744,296 redirects each cost 3 cycles. The refetch is charged to `fetch_lat` (§12.4). | **10.4%**. The `redirect` category is not the branch cost. |
| Does the predictor need a BTB? | No: predecoded targets | "a BTB becomes the next lever" | — | Trace: BTB-64 1.117x against predecode 1.118x. Prediction at extraction already hides the target. | **No BTB** |
| What does a D$ hit cost? | 1 cycle, fully exposed after the fetch fix | 0.5 today, 1 after | 0.5 today | `ld_indep` and `st` 2.53 against 2.03 for an ALU op. All three agree. | 0.5 today, 1 after #1 |
| Pipelined I$ (a request accepted during lookup): fmax risk | medium | high | — | #53 timing: the I$ enable is on path family B (−3.857 ns at 10 ns), the second-worst. The tag compare would go in front of it. | **High on FPGA**, natural on sky130. Small gain (+2.9%), ranked low. |
| Where to post the accelerator's stores | — | in the D$ (core side), removes all 4 `io` cycles | in the crypto bridge, `io` 4.0 → 0.5 | RTL (`sigil_dcache.sv`, `sigil_soc_fabric.sv`, `sigil_crypto_bridge.sv`): the 4 `io` cycles are the D$ uncached state machine (`S_UNC_REQ`→`S_UNC_RSP`→`S_UNC_DONE`) plus the fabric's `D_ACC`/`D_RSP` handshake. The bridge's own wait is only part of that. | **Core side** (#5). A bridge-only post saves less; measure it before choosing it. |
| Dual issue after the fetch fix | "nothing to issue" | — | 1.25x if 30% of instructions pair | Neither is measured. Retire is 62% of the model's #1+#2 cycles, so dual issue is not useless, but the 30% pairing rate is an assumption. | **Both figures dropped.** Only today's bound (1.053x) stands. Measure the pairing rate from the traces. |
| Multithreading after the fix | — | — | "about 1.2x realistic" | No counter or model supports 1.2x. | **Dropped.** The bound (about 1.6x) stands. |
| Verification effort of the fetch fix | 3–4 weeks | 1–2 weeks | — | Not measurable. The front-end estimate includes the 4-byte PMP grain splitting a doubleword, and page-boundary prefetch, which the memory estimate does not cover. | **1–4 weeks**; plan for the upper end |
| Vector LS packing gains | — | 1.20x Dhrystone `sdk`, 7.6x memcpy-e8 | same | Same counter arithmetic | agreed |

Also dropped: the memory analysis's sky130 fetch-fix figure (about
1.68x, counter arithmetic), replaced by the model's 1.75x, and its
CoreMark/MHz projection of about 2.02, replaced by about 1.96.

### 14.6 Ordering with #53

- **#1** issues sequential prefetches from a registered block address.
  That matches #53 step 7 (a registered fetch address), so build it
  on #53.
- **#3** needs #53 steps 5–6 (EX address unit and D-TLB in EX,
  speculative array reads). It must come after them.
- **#4–7** are independent of #53. Each sits on a known critical
  family (VRF→D$, MEM-stage VLS), so check timing with the #53 flow.
- **Every change above alters cycle counts.** Compare each one against
  this baseline with `perf_report.py --diff`. Rerun the F2 comparison
  (§10) on the AFI that contains it.

## 15. Evidence

| Evidence set | What |
|---|---|
| [`perf-baseline-56-2026-10-22`](evidence/perf-baseline-56-2026-10-22/README.md) | **The baseline (§11–12).** Main `eeaa332`, `default`/`sky130`/`fpga` × `soc`/`axi`, `REPEAT=2`, 2136/2136 valid. Includes `headline.md`, per-config `results.csv`/`report.md`, `micro_table.md` and `kernels_report.md`. |
| [`perf-f2-56-2026-10-22`](evidence/perf-f2-56-2026-10-22/README.md) | **F2 hardware (§10, §11.3).** 46/46 runs on the public AFI at 62.5 MHz, compared region by region with the simulation. Includes the run and validation scripts. |
| [`perf-analysis-56-2026-10-22`](evidence/perf-analysis-56-2026-10-22/README.md) | **Analysis (§12–14).** Counter-derived tables, the front-end model (source, runs, what-if table, check against the RTL), and the three analyses. |
| [`perf-suite-56-2026-10-22`](evidence/perf-suite-56-2026-10-22/README.md) | The whole suite after integration (`default`), identical to the branch sets |
| [`perf-dhrystone-56-2026-10-22`](evidence/perf-dhrystone-56-2026-10-22/report.md) | First Dhrystone baseline, including the `oreg` configuration, and the gates run on the harness RTL |
| [`perf-coremark-56-2026-10-22`](evidence/perf-coremark-56-2026-10-22/README.md) | CoreMark port, 1000-iteration runs for the 10 s rule, flag sweep |
| [`perf-kernels-56-2026-10-22`](evidence/perf-kernels-56-2026-10-22/README.md) | Kernels, the code-placement experiment |
| [`perf-micro-56-2026-10-22`](evidence/perf-micro-56-2026-10-22/micro_table.md) | Microbenchmark calibration |
| [`perf-sha256chain-56-2026-10-22`](evidence/perf-sha256chain-56-2026-10-22/report.md) | SHA chains and bulk hashing (#10), the alignment experiment |
