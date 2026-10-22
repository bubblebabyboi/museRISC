# #56: deterministic simulation baseline of main `eeaa332` (2026-10-22)

The reference numbers for the design on main `eeaa332`, measured before
any #53 pipelining. Every benchmark under `sw/bench/` and every build
variant runs in three RTL configurations (`default`, `sky130`, `fpga`)
on both memory models (`soc`, `axi`). Every simulation runs twice.
Method: [`docs/PERFORMANCE.md`](../../PERFORMANCE.md).

## Files

| File | What |
|---|---|
| `headline.md` | cross-configuration tables from `baseline_tables.py`: the checks below; Dhrystone and CoreMark; SHA-256 chain and bulk; kernels (cycles per call, speedups); micro benchmarks (cycles per operation); per-cycle accounting and events of the headline regions |
| `<config>/results.csv` | raw harness output, one row per region result (both repeats) with every counter and metric. `<config>` is `default`, `sky130` or `fpga` |
| `<config>/report.md` | `scripts/perf_report.py` tables for that configuration: summary, speedups, projected throughput at 62.5 and 100 MHz, where the cycles go, events |
| `<config>/results.json` | everything, plus metadata: commit, merge base, rtl/ tree, tool versions, host, memory model arguments, image sha256s, build commands |
| `<config>/runs/` | UART log and `SIGIL_PERF` record of each of the 56 simulations |
| `<config>/build-logs/` | build log of each of the 14 images, with the compiler command lines |
| `<config>/perf-run.log` | `make perf` console output, with start and end times |
| `env.log` | commit, rtl/ difference to `eeaa332`, tool versions, host |
| `synth-view-diff.log` | `scripts/synth_view_diff.sh eeaa332 HEAD`: the synthesis views of rtl/ are byte-identical to main's |
| `tb-build.log` | fresh Verilator builds of the six testbenches |
| `compare-prior-evidence.log` | this run against the earlier #56 evidence sets, run by run |
| `micro_table.md`, `kernels_report.md` | the benches' own report scripts (`sw/bench/micro_common/micro_table.py`, `sw/bench/kernels/kernels_report.py`) over the runs of all three sets |
| `run_baseline.sh` | the script that produced this run |
| `baseline_tables.py` | the cross-configuration checks and tables |

## Setup

- **Design.** `rtl/` tree `89b98cb227c6`. It is main `eeaa332` plus
  the simulation-only counters: `rtl/core/sigil_perf.svh` (new) and its
  `` `include`` at the end of `sigil_cpu`, inside `` `ifndef SYNTHESIS``,
  and one `perf_miss` tap in each of `sigil_icache` and `sigil_dcache`,
  inside their existing `` `ifndef SYNTHESIS`` blocks (`env.log` has the
  full diff). With `SYNTHESIS` defined, the preprocessed RTL is
  byte-identical to `eeaa332`. This holds alone and with
  `SIGIL_SRAM_FAKERAM45`, `SIGIL_SRAM_SKY130`, `SIGIL_SRAM_OREG` and
  `SIGIL_VRF_OREG` (`synth-view-diff.log`). No #53 code is included.
- **Code.** `56-perf-harness` at `8d15410`, clean tree, merge base with
  main `eeaa332`.
- **Run.** `run_baseline.sh` on sigil-verify (c7i.8xlarge, Xeon
  Platinum 8488C, Ubuntu 24.04), 2026-10-22T11:20:07Z to 11:40:57Z.
  It rebuilt the six testbenches from scratch, then ran once per
  configuration:
  `make -C sim perf CONFIG=<config> MEM="soc axi" REPEAT=2 JOBS=12
  VJOBS=12 CLOCK_MHZ="62.5 100"`. The runs took 6 min 39 s
  (`default`), 8 min 12 s (`sky130`) and 5 min 23 s (`fpga`). The
  riscv-dv regression shared the host; this does not change the counts.
- **Tools.** Verilator 5.048, riscv64-unknown-elf-gcc 16.1.0
  (`g6afcc4f6d`, `deps/`), host g++ 13.3.0, Python 3.12.3, GNU Make 4.3.
- **Configurations** (as the counter records report them):

  | Config | Testbenches | I$ | D$ | SRAM_OREG | VRF_OREG |
  |---|---|---|---|---:|---:|
  | `default` | `soc_rtl_tb`, `fpga_top_tb` | 8 KiB 2-way (64×2×64 B) | 16 KiB 4-way (64×4×64 B) | 0 | 0 |
  | `sky130` | `soc_rtl_tb_sky130`, `fpga_top_tb_sky130` | 4 KiB direct-mapped | 4 KiB direct-mapped | 1 | 1 |
  | `fpga` | `soc_rtl_tb_vrforeg`, `fpga_top_tb_vrforeg` | 8 KiB 2-way | 16 KiB 4-way | 0 | 1 |

  `fpga` is the F2 build as `docs/PERFORMANCE.md` §4 defines it, with
  `SIGIL_VRF_OREG`: the next F2 build. The public AFI that ran the
  benchmarks on F2 hardware was built without `VRF_OREG`, so it runs
  the `default` configuration
  ([`perf-f2-56-2026-10-22`](../perf-f2-56-2026-10-22/README.md)).
- **Memory models.** `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready
  100`, a fixed 1-cycle first beat. `axi`: `--axi-lat 24:24 --axi-gap 0
  --axi-ready 100 --uart-pop 100`, behind the `sigil_mbus_axi4` bridge,
  a fixed 24-cycle AXI latency. Both are deterministic.
- **Benchmarks.** 10 benchmarks, 14 images (bench × variant), with
  bench.json iteration counts: dhrystone 2000, coremark 20, kernels 4
  calls, sha256chain 1024 hashes, sha256chain_bulk 64 KiB, and the
  `micro_*` benches. Per configuration: 56 simulations and 712 region
  results. In all: 168 simulations and 2136 region results.

## Validation

- **Self-checks.** All 2136 region results are valid, with 0 failures.
  Each program checks its own output before it prints `SIGIL TEST
  PASS`: CoreMark's CRCs against the references, Dhrystone's final
  values, the kernels bit for bit against a scalar reference and host
  known answers, the micro kernels' values computed in C, and the SHA
  FIPS 180-4/202 known answers plus Python `hashlib` values for every
  chain. The harness then requires every `expect` line and one
  `SIGIL_PERF` record per region. In each record, `cycles` must equal
  the `mcycle` delta, `instret` the `minstret` delta, and the
  accounting must sum to `cycles`. The program's hardware-counter line
  must fall within the window.
- **Deterministic.** Each configuration was run twice, with every
  simulation repeated (`REPEAT=2`). The harness reports `determinism
  over 2 repeats: PASS (identical counts)` for all three.
  `baseline_tables.py` repeats the check on the raw records: rep 0
  equals rep 1 in every counter and in the hardware-counter numbers
  for 356/356 results per configuration.
- **Same images everywhere.** Each configuration's run rebuilt all 14
  images, and the three builds are bit-identical (sha256). The numbers
  of different configurations therefore come from the same binaries.
- **Same as the earlier evidence** (`compare-prior-evidence.log`). The
  `default` set equals `perf-suite-56-2026-10-22` (712/712) and each
  branch evidence set (dhrystone 8/8, coremark 12/12, kernels 224/224,
  micro 420/420, sha256chain 48/48): the same image sha256s and the
  same counters. The `sky130` and `fpga` Dhrystone results equal
  `perf-dhrystone-56-2026-10-22`'s (8/8 each), which came from another
  commit and another testbench build. All other `sky130` and `fpga`
  results are new.

## Headline

All numbers come from simulation cycles over the measured region. The
per-MHz figures do not depend on the clock. `headline.md` has every
table.

**Dhrystone 2.1 and CoreMark 1.0** (`scalar` = `-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`,
the headline; `sdk` = SDK default `-march` with V; `-O2`):

| Benchmark | Metric | default soc | default axi | sky130 soc | sky130 axi | fpga soc | fpga axi |
|---|---|---:|---:|---:|---:|---:|---:|
| **dhrystone [scalar]** | **DMIPS/MHz** | **0.371** | 0.371 | **0.216** | 0.201 | **0.371** | 0.371 |
| | cycles | 3,070,244 | 3,070,652 | 5,272,386 | 5,670,943 | 3,070,244 | 3,070,652 |
| | IPC | 0.337 | 0.337 | 0.196 | 0.183 | 0.337 | 0.337 |
| dhrystone [sdk] | DMIPS/MHz | 0.327 | 0.327 | 0.191 | 0.173 | 0.317 | 0.317 |
| | cycles | 3,482,242 | 3,482,658 | 5,966,289 | 6,596,705 | 3,594,242 | 3,594,658 |
| | IPC | 0.293 | 0.293 | 0.171 | 0.155 | 0.284 | 0.284 |
| **coremark [scalar]** | **CoreMark/MHz** | **1.395** | 1.395 | **0.868** | 0.867 | **1.395** | 1.395 |
| | cycles | 14,337,806 | 14,339,056 | 23,030,662 | 23,060,820 | 14,337,806 | 14,339,056 |
| | IPC | 0.366 | 0.366 | 0.228 | 0.228 | 0.366 | 0.366 |
| coremark [sdk] | CoreMark/MHz | 1.372 | 1.372 | 0.856 | 0.855 | 1.372 | 1.372 |
| | cycles | 14,572,507 | 14,573,757 | 23,365,328 | 23,400,453 | 14,580,592 | 14,581,842 |
| | IPC | 0.359 | 0.359 | 0.224 | 0.224 | 0.359 | 0.359 |
| coremark [validation] | CoreMark/MHz | 1.392 | 1.392 | 0.867 | 0.865 | 1.392 | 1.392 |
| | cycles | 14,364,787 | 14,366,037 | 23,079,360 | 23,110,518 | 14,364,787 | 14,366,037 |
| | IPC | 0.366 | 0.366 | 0.228 | 0.227 | 0.366 | 0.366 |

CoreMark runs 20 iterations here, as in the CoreMark evidence's
baseline. That evidence's 1000-iteration `default`/`soc` runs, which
meet EEMBC's 10 s rule in simulated time at 62.5 MHz, give the same
1.395 (`perf-coremark-56-2026-10-22`). These are RTL simulation
figures, not submitted scores. `validation` is a correctness run.

**SHA-256 chain** (`sha256chain`, 1024 chained hashes of a 32-byte
value): cycles per hash, with the speedup over plain C in brackets.
The SHA-512 chain hashes 64-byte messages:

| Implementation | default soc | default axi | sky130 soc | sky130 axi | fpga soc | fpga axi |
|---|---:|---:|---:|---:|---:|---:|
| plain C | 9,918.2 | 9,918.4 | 15,634.4 | 15,634.7 | 9,918.2 | 9,918.4 |
| Zknh | 6,753.2 (1.47x) | 6,753.4 (1.47x) | 10,747.4 (1.45x) | 10,747.6 (1.45x) | 6,753.2 (1.47x) | 6,753.4 (1.47x) |
| RVV ×16 multi-buffer | 4,642.0 (2.14x) | 4,642.6 (2.14x) | 4,949.1 (3.16x) | 4,950.3 (3.16x) | 4,854.6 (2.04x) | 4,855.3 (2.04x) |
| accelerator, `sigil_sha256_block` | 572.1 (17.34x) | 572.1 (17.34x) | 792.2 (19.74x) | 792.2 (19.73x) | 572.1 (17.34x) | 572.1 (17.34x) |
| accelerator, `sigil_sha256` (byte API) | 2,793.1 (3.55x) | 2,793.3 (3.55x) | 4,422.2 (3.54x) | 4,422.5 (3.54x) | 2,793.1 (3.55x) | 2,793.3 (3.55x) |
| SHA-512, accelerator `sigil_hash` | 2,472.2 | 2,472.3 | 3,775.3 | 3,775.6 | 2,472.2 | 2,472.3 |
| SHA3-256, accelerator `sigil_hash` | 1,370.1 | 1,370.2 | 2,120.2 | 2,120.3 | 1,370.1 | 1,370.2 |

**Bulk hashing** (`sha256chain_bulk`, one 64 KiB buffer): bytes per
cycle, with the speedup over plain C in brackets:

| Implementation | default soc | default axi | sky130 soc | sky130 axi | fpga soc | fpga axi |
|---|---:|---:|---:|---:|---:|---:|
| SHA-256 plain C | 0.0065 | 0.0065 | 0.0041 | 0.0041 | 0.0065 | 0.0065 |
| SHA-256 Zknh | 0.0095 (1.47x) | 0.0095 (1.46x) | 0.0060 (1.46x) | 0.0060 (1.45x) | 0.0095 (1.47x) | 0.0095 (1.46x) |
| SHA-256 RVV ×16 (16 segments) | 0.0131 (2.02x) | 0.0130 (2.01x) | 0.0121 (2.94x) | 0.0120 (2.92x) | 0.0124 (1.91x) | 0.0123 (1.90x) |
| SHA-512 accelerator | 0.2388 | 0.2205 | 0.1740 | 0.1626 | 0.2388 | 0.2205 |
| SHA3-256 accelerator | 0.2398 | 0.2215 | 0.1748 | 0.1635 | 0.2398 | 0.2215 |

**Kernels**: speedup over the scalar C of the same configuration and
memory model. RVV intrinsics are first, then GCC auto-vectorization
(`autovec` image, V at `-O3`):

| Kernel | C cycles/call (default soc) | default soc | default axi | sky130 soc | sky130 axi | fpga soc | fpga axi |
|---|---:|---:|---:|---:|---:|---:|---:|
| vadd_i32 | 19,520 | 1.81x / 1.55x | 1.72x / 1.52x | 2.04x / 1.76x | 1.74x / 1.58x | 1.65x / 1.43x | 1.57x / 1.40x |
| vadd_i64 | 9,842 | 1.77x / 1.38x | 1.68x / 1.36x | 1.83x / 1.50x | 1.50x / 1.33x | 1.61x / 1.28x | 1.54x / 1.26x |
| daxpy | 14,988 | 1.66x / 1.40x | 1.66x / 1.40x | 1.83x / 1.53x | 1.61x / 1.40x | 1.57x / 1.33x | 1.57x / 1.33x |
| saxpy | 32,904 | 1.86x / 1.67x | 1.85x / 1.67x | 2.20x / 1.95x | 1.99x / 1.80x | 1.75x / 1.58x | 1.75x / 1.59x |
| ddot | 12,857 | 1.63x / 1.00x | 1.63x / 1.00x | 1.89x / 1.19x | 1.68x / 1.16x | 1.62x / 0.98x | 1.63x / 0.98x |
| idot_i32 | 19,500 | 1.51x / 1.24x | 1.51x / 1.24x | 1.87x / 1.48x | 1.72x / 1.42x | 1.51x / 1.23x | 1.51x / 1.23x |
| memcpy | 8,280 | 2.51x / 1.00x | 2.46x / 1.00x | 2.24x / 1.00x | 1.72x / 1.00x | 2.17x / 1.00x | 2.14x / 1.00x |
| memset | 5,208 | 2.96x / 1.00x | 2.96x / 1.00x | 3.05x / 1.00x | 3.01x / 1.00x | 2.29x / 1.00x | 2.29x / 1.00x |
| dgemm | 721,504 | 1.85x / 1.00x | 1.82x / 1.00x | 2.97x / 1.00x | 3.85x / 1.00x | 1.84x / 1.00x | 1.81x / 1.00x |
| sgemm | 809,562 | 2.07x / 1.00x | 2.07x / 1.00x | 2.90x / 1.00x | 3.14x / 1.00x | 2.06x / 1.00x | 2.06x / 1.00x |
| fir_f32 | 479,294 | 2.56x / 1.28x | 2.56x / 1.28x | 3.48x / 1.64x | 3.47x / 1.65x | 2.55x / 1.27x | 2.55x / 1.27x |
| mac_i8 | 86,059 | 1.73x / 1.40x | 1.73x / 1.40x | 2.22x / 1.75x | 2.15x / 1.72x | 1.73x / 1.38x | 1.73x / 1.38x |
| mac_i16 | 43,052 | 1.85x / 1.66x | 1.85x / 1.66x | 2.30x / 2.01x | 2.17x / 1.92x | 1.85x / 1.65x | 1.85x / 1.65x |

The `e8` forms of memcpy and memset are slower than C in every
configuration: 0.29x to 0.49x (`headline.md`).

## What the counters show

- **`fpga` (`SIGIL_VRF_OREG`) only changes vector code.** The 210
  region results per configuration that retire no vector instruction
  have the same counters as in `default`. Only the configuration fields
  and the absolute `mcycle` at the begin marker differ. Dhrystone
  `scalar`, CoreMark `scalar`/`validation`, every SHA path except
  RVV, and the `micro_pipe/units/dmem/imem` results are therefore the
  same in both. Of the 146 vector results, 122 are slower:
  - every vector arithmetic instruction costs 1 more cycle
    (`vadd_e8_vl1`: 7.12 to 8.12 cycles);
  - unit-stride stores cost 4 cycles per element instead of 3
    (`vse8_vl512`: 1,537.6 to 2,049.6 cycles);
  - unit-stride loads are unchanged.

  As a result, Dhrystone `sdk` is +3.2%, where the vectorized struct
  copy is `vle8`/`vse8`. SHA-256 RVV ×16 is +4.6%, memcpy RVV +15.5%,
  memset RVV +29%, and memset RVV-e8 +32%. CoreMark `sdk` is +0.06%.
- **`sky130` is 1.58–1.85x slower on scalar code.** Cycles against
  `default`:
  - Dhrystone `scalar`: +71.7% (`soc`), +84.7% (`axi`);
  - CoreMark `scalar`: +60.6% and +60.8%;
  - SHA-256 plain C: +57.6%.

  The registered SRAM reads cause most of it. The fetch issue gap
  grows from 2 to 3 cycles, so dependent ALU chains take 3.0 cycles
  per instruction instead of 2.0 (`micro_pipe`). Loads take 5.0 cycles
  instead of 2.5, load-use 8 instead of 4, a taken branch 6 instead of
  4 and call/return 15 instead of 10. CoreMark's I$ hit-latency share
  grows from 40.4% to 60.6% of cycles. Its I$ misses grow from 39 to
  1,187 but cost only 0.1–0.2%.
- **The 4 KiB direct-mapped L1s.** A random pointer chase misses on
  every access (1.001 D$ misses per load) from an 8 KiB working set:
  17.2 cycles per load (`soc`) and 42.2 (`axi`). In `default` it hits
  up to 16 KiB at 3.08–3.10 cycles. Code footprints of 6 KiB and more
  miss in the I$: 0.043–0.063 misses per instruction, against at most
  0.008 up to 4 KiB. Dhrystone gets 8,004 D$ misses and 6,004
  write-backs over 2000 runs, against 2 and 1 in `default`. These cost
  4.0% of cycles (`soc`) and 10.7% (`axi`). Of Dhrystone, CoreMark and
  the SHA-256 chain, only Dhrystone is memory-latency sensitive in
  `sky130`: `axi` adds 7.6%, against 0.13% for CoreMark. The kernels'
  data exceed 4 KiB, and `axi` adds up to 68% (memcpy RVV: 7,610 to
  12,789 cycles per call; dgemm C: +60%, 1,442,598 to 2,309,066).
- **Vector code loses less in `sky130`.** The element-serial vector
  unit adds only one cycle per instruction. Unit-stride loads cost 4
  cycles per element and stores 5, against 3 in `default`. Most RVV
  speedups over C are therefore larger in `sky130`: SHA-256 RVV ×16
  3.16x against 2.14x, dgemm 2.97x (`soc`) and 3.85x (`axi`), and FIR
  3.48x. The exceptions are memcpy (2.24x against 2.51x on `soc`) and
  vadd_i64 on `axi` (1.50x against 1.68x).
- **Multi-cycle units do not change.** Divide, FP divide and square
  root, multiply and FP add/multiply latencies are the same in all
  three configurations within 0.25 cycles (`micro_units`).
- **Memory model sensitivity.** In `default` and `fpga`, the
  24-cycle AXI model adds less than 0.02% to Dhrystone and CoreMark.
  It adds 0.01–6.8% to the kernel regions (most: vadd_i32/i64 RVV,
  5.5–6.8%), 8% to the bulk accelerator hashes and 0.3% to bulk
  SHA-256 C. Effective
  miss penalties in the headline regions (`dc_miss_cyc / dc_miss`) are
  12 cycles (`soc`) and 37 (`axi`) for the I$. For the D$ they are
  12–30 and 37–88. A miss that also writes back a dirty line costs
  more: Dhrystone's 2 misses take 42 cycles with 1 write-back and 60
  with 2 (`soc`). In `sky130` they are 13 and 38 for the I$.

## Reproduce

On sigil-verify (or any host with `scripts/install_deps.sh --gcc15`),
in a checkout of `56-perf-harness` at `8d15410`:

```sh
docs/evidence/perf-baseline-56-2026-10-22/run_baseline.sh       # -> build/perf/baseline-56/
python3 docs/evidence/perf-baseline-56-2026-10-22/baseline_tables.py build/perf/baseline-56 \
  --md headline.md --merged merged.json
python3 sw/bench/micro_common/micro_table.py merged.json --md micro_table.md
python3 sw/bench/kernels/kernels_report.py merged.json --md kernels_report.md
```

The counts should be identical on any host with the same Verilator
and compiler. The Dhrystone evidence also found identical records on a
Verilator 5.020 build. `scripts/perf_report.py --diff
docs/evidence/perf-baseline-56-2026-10-22/<config> <new run>` compares
a later design, such as the #53 pipelining, run by run against this
baseline.
