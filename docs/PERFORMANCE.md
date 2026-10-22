# Performance harness

How Sigil's performance is measured (issue
[#56](https://github.com/bubblebabyboi/sigil/issues/56), epic #61). This
document covers the **method** only. Measured numbers live in
[`docs/evidence/`](evidence/README.md) with the commit, configuration,
tool versions and date of every run.

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

## 1. Quick start

```sh
source deps/env.sh
make -C sim perf                                  # every bench, default config, both memory models
make -C sim perf BENCHES=dhrystone CONFIG="default sky130 fpga" JOBS=8
make -C sim perf BENCHES=dhrystone MEM=soc REPEAT=2   # determinism check
make -C sim perf ITER=200                         # quick smoke (not a result)
```

| Variable | Default | Meaning |
|---|---|---|
| `BENCHES` | all of `sw/bench/*/` | benchmarks to run |
| `CONFIG` | `default` | RTL builds: any of `default sky130 oreg fpga` (§4) |
| `MEM` | `soc axi` | testbench and memory model: `soc`, `axi` (§4) |
| `JOBS` | 4 | simulations run in parallel |
| `REPEAT` | 1 | runs of each simulation; >1 checks determinism (§6) |
| `ITER` | bench.json | overrides every bench's iteration count |
| `PERF_OUT` | `build/perf/run` | output directory |
| `PERF_SOC_ARGS`, `PERF_AXI_ARGS` | §4 | memory model arguments |
| `VJOBS` | 0 (all cores) | Verilator build threads (shared with the rest of `sim/`) |

`make` builds the testbenches it needs, then
[`scripts/perf_run.py`](../scripts/perf_run.py) builds and runs every
benchmark and writes `results.json`, `results.csv` and `report.md` to
`PERF_OUT`. The target fails if any run fails validation.

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
the begin marker and before the end marker. The difference is a small
constant per binary, reported as `HW-counter cycles` next to `cycles`.

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
| `bytes_per_iteration` | for `bytes_per_cycle` | bytes processed per iteration |
| `regions` | no (`{"0": "main"}`) | measured regions, `{"<id>": "<label>"}`; one result row per region |
| `variants` | no (`{"default": {}}`) | build variants, `{"<variant>": {"description": "...", "make": {"VAR": "value"}}}`; each is built once and run on every configuration and memory model |
| `units` | no | what one iteration is |

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
2. every `expect` line is in the UART output;
3. there is exactly one `SIGIL_PERF` record per declared region, and no
   record for an undeclared one;
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
| bytes/cycle | `iterations × bytes_per_iteration / cycles` |

All metrics use the simulation window (`cycles`). Per-MHz figures are
clock-independent. To get absolute figures, multiply by the clock: for
example, F2 runs at 62.5 MHz today (`docs/FPGA_F2.md`).

## 8. Reports and diffs

```sh
scripts/perf_report.py build/perf/run --csv out.csv --md out.md   # tables from one result set
scripts/perf_report.py --diff build/perf/base build/perf/new      # A vs B, run by run
```

`report.md` has four parts: a summary (cycles, instret, IPC, CPI,
cycles/iteration, metric, hardware-counter cycles), *Where the cycles
go* (every `stk_*` category as a percentage of cycles), and *Events*
(instruction mix, redirect rate, I$/D$ and bus activity, unit busy
time). `results.csv` has one row per run with every counter.
`results.json` adds the metadata: UTC date, commit, merge base with
`main`, `rtl/` tree hash, Verilator and compiler versions, host, memory
model arguments, image hashes and build commands. The diff matches runs
by bench, variant, region, configuration and memory model. It reports
the change in cycles, IPC and metric, and which accounting categories
moved.

## 9. Benchmarks

| Benchmark | What | Metric | Variants |
|---|---|---|---|
| [`dhrystone`](../sw/bench/dhrystone/README.md) | Dhrystone 2.1, netlib C source. Ground rules: separate compilation and `-fno-inline`; `-O2`, otherwise the SDK flags. | DMIPS/MHz | `scalar`: `-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`, the headline. `sdk`: SDK default `-march` with V, where GCC turns the 56-byte struct assignment into a `vle8`/`vse8` loop. |

Planned (issue #56): CoreMark (pinned EEMBC source fetched into the
git-ignored `third_party/`), vector/FPU kernels (scalar vs RVV), and the
SHA-256 chain from #10 (scalar vs RVV vs accelerator, bytes/cycle).
