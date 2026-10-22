# #56: CoreMark on the performance harness (2026-10-22)

EEMBC CoreMark 1.0, `sw/bench/coremark` (port and method:
[`sw/bench/coremark/README.md`](../../../sw/bench/coremark/README.md);
harness: [`docs/PERFORMANCE.md`](../../PERFORMANCE.md)), measured in
RTL simulation of main `eeaa332`'s design. No #53 pipelining is
included.

## Files

| File | What |
|---|---|
| `report.md`, `results.csv`, `results.json` | harness output of the baseline run (every counter, plus metadata: commit, rtl tree, tool versions, image sha256s, build commands) |
| `runs/`, `perf_run.log` | UART log and `SIGIL_PERF` record of all 12 baseline runs; the `make perf` output |
| `build-coremark-{scalar,sdk,validation}.log` | build logs with the full compiler command lines |
| `fetch.log` | `fetch_coremark.sh` from a clean destination; upstream's `md5sum -c coremark.md5`; sha256 of every file used; a modified tree is refused |
| `host-reference.log` | native x86-64 build of the same sources (EEMBC `posix` port): the CRCs for both seed sets at 16 iteration counts (the `crcfinal` table in `core_portme.c`), plus full outputs at 20 and 1000 iterations |
| `long-1000/` | 1000-iteration runs that meet EEMBC's 10 s rule at 62.5 MHz (below) |
| `flag-sweep/` | `-O2` vs `-O3`, `-O3 -funroll-loops` and `-Os` (below) |
| `image-check.log`, `rerun-final.log` | the measured images rebuilt from the final code (byte-identical), and the baseline re-run at the final code (identical records) |
| `cm_long_run.py` | the wrapper that ran `long-1000/` and `flag-sweep/`: `scripts/perf_run.py` unchanged, with the bench's `max_cycles` and variant set overridden in memory |

## Setup

- **Design.** RTL of `56-perf-harness` (`d2b3df4`). This is main
  `eeaa332` plus the harness's `` `ifndef SYNTHESIS`` counter block;
  the rtl/ tree is `89b98cb227c6`, the same as in the Dhrystone
  baseline. The branch `56-perf-coremark` adds only `sw/bench/coremark`
  and this directory.
- **Code.** Measured at `320cf57`. Two later commits change only how
  the sources are fetched and checked: `13d7aaf` and `4526052` (the
  Makefile re-verifies an edited `third_party/coremark`, and a verified
  tree is never written to). The final code is `4526052`; later commits
  add only evidence. Two checks show the images did not change:
  - `image-check.log` rebuilds all five measured images from a clean
    export of `4526052`, with a fresh fetch, and compares them by
    sha256: all are byte-identical;
  - `rerun-final.log` repeats the baseline run at `4526052`
    (2026-10-22T10:56:08Z): all 12 records are identical in all 91
    fields, with the same image hashes.
- **Run.** `make -C sim perf BENCHES=coremark CONFIG=default MEM="soc
  axi" REPEAT=2 JOBS=12` on sigil-verify (c7i.8xlarge, Ubuntu 24.04).
  Results written 2026-10-22T09:39:42Z. Verilator 5.048,
  riscv64-unknown-elf-gcc 16.1.0 (`deps/`).
- **Benchmark.** eembc/coremark `b56889a7bd9d5624fbeff2a73ba69878e6a9c146`,
  unmodified (`fetch.log`). `TOTAL_DATA_SIZE` 2000, data on the stack
  in RAM, 20 iterations.
- **Flags.** `GCC16.1.0 -O2 -mabi=lp64d -mcmodel=medany
  -mstrict-align -std=gnu11 -ffreestanding -fno-common
  -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables
  -fno-math-errno`, the same for every file, no LTO. The variants
  differ in `-march`:
  - `scalar` and `validation` use
    `rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`;
  - `sdk` uses the SDK default `rv64gcv_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`.
- **Configuration.** `default` only: I$ 8 KiB 2-way, D$ 16 KiB 4-way,
  64 B lines, 1-cycle SRAM reads. Two memory models:
  - `soc`: `soc_rtl_tb`, fixed 1-cycle memory;
  - `axi`: `fpga_top_tb`, the F2 top, through the AXI4 bridge with a
    fixed 24-cycle latency.

## Validation

All 12 runs (3 variants × 2 memory models × 2 repeats) are valid under
the harness rules. Each run passed the following checks:

- **Program's own checks.** CoreMark printed the known per-algorithm
  CRCs for its seed set:
  - performance (`0,0,0x66`): seedcrc `0xe9f5`, list `0xe714`, matrix
    `0x1fd7`, state `0x8e3a`;
  - validation (`0x3415,0x3415,0x66`): `0x18f2`, `0xe3c1`, `0x0747`,
    `0x8d84`.

  The port re-checked these. It also matched `crcfinal` against the
  native x86-64 reference (`0x4983` performance, `0xad38` validation, at
  20 iterations) before it printed `COREMARK CHECK OK iterations=20`.
- **Harness checks.** The `SIGIL_PERF` record has `cycles` = `mcycle`
  delta and `instret` = `minstret` delta, and the accounting sums to
  `cycles`. The program's `SIGIL PERF` line lies within the window.
- **Determinism.** Both repeats are identical in all 91 record fields.
- **Run rules.** Both EEMBC seed sets validate (run rule 2). The runs
  are below the 10 s rule: 14.34 M cycles is 0.229 s at 62.5 MHz. So
  `core_main.c` prints its `ERROR! Must execute for at least 10 secs`
  and `Errors detected` lines, as documented. `long-1000/` covers that
  rule.

## Results (default configuration, 20 iterations)

CoreMark/MHz = 20 / cycles × 10^6, over CoreMark's timed region
(`iterate()`):

| Variant | Memory | Cycles | Instret | IPC | Cycles/iteration | CoreMark/MHz |
|---|---|---:|---:|---:|---:|---:|
| **scalar** (headline) | soc | 14,337,806 | 5,246,413 | 0.366 | 716,890 | **1.395** |
| scalar | axi | 14,339,056 | 5,246,413 | 0.366 | 716,953 | 1.395 |
| sdk (V) | soc | 14,572,507 | 5,238,336 | 0.359 | 728,625 | 1.372 |
| sdk (V) | axi | 14,573,757 | 5,238,336 | 0.359 | 728,688 | 1.372 |
| validation seeds | soc | 14,364,787 | 5,253,779 | 0.366 | 718,239 | 1.392 |
| validation seeds | axi | 14,366,037 | 5,253,779 | 0.366 | 718,302 | 1.392 |

In EEMBC's scaling format, this is `CoreMark/MHz 1.0 : 1.395 /
GCC16.1.0 -O2 -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
-mabi=lp64d -mcmodel=medany -mstrict-align / Stack in RAM, L1 I$ 8 KiB
2-way + D$ 16 KiB 4-way 1:1, memory 1:1 (1-cycle)`. It is an RTL
simulation figure, below the 10 s rule, not a submitted score.

### Where the cycles go (scalar, soc)

| Category | Cycles | % |
|---|---:|---:|
| retire | 5,246,413 | 36.6 |
| fetch: I$ hit latency / issue gap | 5,799,431 | 40.4 |
| fetch: 32-bit instruction straddles a fetch word | 769,852 | 5.4 |
| MEM: D$ hit latency | 1,365,092 | 9.5 |
| squashed: taken branch / jal / jalr | 587,477 / 72,205 / 23,454 | 4.1 / 0.5 / 0.2 |
| EX: M unit | 375,840 | 2.6 |
| load-use interlock | 97,498 | 0.7 |
| I$ miss + D$ miss | 415 + 129 | 0.0 |

Observations:

- **Fetch is the bottleneck, as in Dhrystone.** Fetch latency and
  straddles take 45.8% of cycles, against 49.5% in Dhrystone. There
  are 1.30 I$ accesses per instruction, and 51.4% of the retired
  instructions are compressed.
- **CoreMark runs from the L1s.** Over 20 iterations there are 39 I$
  and 11 D$ misses, all cold. The 24-cycle AXI model adds only
  1,250 cycles, so in this configuration the result is insensitive to
  memory latency.
- **Mix.** 20.1% branches (58.6% taken, 141.9 redirects per 1000
  instructions), 20.6% loads, 5.4% stores and 3.6% multiplies. The M
  unit holds EX for 2 cycles per multiply (187,920 multiplies).
- **The V build is 1.6% slower (+234,701 cycles).** The vector
  instructions themselves (`stk_vls` + `stk_vec`) cost 44,820 cycles.
  The rest is code layout: fetch latency +97,022, straddles +93,597,
  `jalr` squashes +17,720. GCC's SLP vectorizer emits short
  `vle32`/`vse32`/`vse16` sequences for CoreMark's state counters and
  CRC fields (`sw/bench/coremark/README.md`).

## `flag-sweep/`: optimization level (scalar ISA, soc, 20 iterations)

| `OPT` | Cycles | Instret | IPC | CoreMark/MHz | straddle % | I$ accesses/instr |
|---|---:|---:|---:|---:|---:|---:|
| `-O2` (the variant above) | 14,337,806 | 5,246,413 | 0.366 | **1.395** | 5.4 | 1.297 |
| `-O3` | 17,062,942 | 5,423,950 | 0.318 | 1.172 | 11.5 | 1.501 |
| `-O3 -funroll-loops` | 17,291,002 | 5,446,598 | 0.315 | 1.157 | 12.8 | 1.512 |
| `-Os` | 20,238,586 | 6,557,699 | 0.324 | 0.988 | 9.2 | 1.485 |

All four runs validated (CRCs and `crcfinal`). On this core `-O3` is
19% slower than `-O2` while it runs only 3.4% more instructions. The
difference is in the front end: twice the share of cycles lost to
32-bit instructions that straddle a fetch word, and 16% more fetch
accesses per instruction. `-O2` is therefore the headline. The sweep
used `cm_long_run.py` with extra variants; it is not part of
`bench.json`.

## `long-1000/`: the 10 s rule

The harness's 20-iteration region is 0.229 s at 62.5 MHz. To show
that this short window gives the same figure as a run that meets the
rule, the same code ran for 1000 iterations with both seed sets,
twice each, on `soc`/`default`. These runs used the harness's own
build, validation and determinism code through `cm_long_run.py`, with
`max_cycles` 1.5e9 (`long-1000/perf_run.log` has the command). Results
were written 2026-10-22T10:51:49Z at `320cf57`. Each simulation took
about 70 minutes.

| Seeds | Cycles | Instret | IPC | Cycles/iteration | CoreMark/MHz | Region at 62.5 MHz |
|---|---:|---:|---:|---:|---:|---:|
| performance `0,0,0x66` | 716,834,078 | 262,309,888 | 0.366 | 716,834 | **1.395** | 11.47 s |
| validation `0x3415,0x3415,0x66` | 718,245,526 | 262,700,093 | 0.366 | 718,246 | 1.392 | 11.49 s |

- **CoreMark validated these runs itself.** In both runs `core_main.c`
  printed `Correct operation validated`, so it found no errors at all,
  the 10 s rule included. `crcfinal` (`0xd340` / `0x26c2`) matches the
  native reference at 1000 iterations. Both repeats are identical in
  every counter. All four runs are valid under the harness rules.
- **The performance run printed EEMBC's result line:**
  `CoreMark 1.0 : 87.188939 / GCC16.1.0 -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
  -mabi=lp64d -mcmodel=medany -mstrict-align -O2 -std=gnu11
  -ffreestanding -fno-common -ffunction-sections -fdata-sections
  -fno-asynchronous-unwind-tables -fno-math-errno / STACK`.
  The 87.19 iterations/s is the RTL simulation of the default
  configuration with the ideal 1-cycle memory, converted at the 62.5 MHz
  F2 clock. It is not an F2 hardware measurement and has not been
  submitted to EEMBC. Both seed sets validate at ≥ 10 s, so EEMBC run
  rules 1 and 2 are both met in simulated time.
- **The 20-iteration window is representative.** At 1000 iterations a
  run takes 716,834 cycles per iteration; at 20 it takes 716,890. The
  0.008% difference is a fixed start-up cost: the 20-iteration window is
  1,124 cycles longer than 20 × 716,834. CoreMark/MHz is 1.395 either
  way (1.39502 vs 1.39491).
