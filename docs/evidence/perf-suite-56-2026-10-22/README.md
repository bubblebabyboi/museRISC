# #56: whole benchmark suite after integration (2026-10-22)

One run of every benchmark under `sw/bench/` after the four benchmark
branches (`56-perf-coremark`, `56-perf-kernels`, `56-perf-micro`,
`56-perf-sha256chain`) were merged into `56-perf-harness` and the
harness changes they asked for were applied. It checks that everything
still builds and validates together. It is not a new baseline: every
number is identical to the evidence of the branch that measured it.

## Files

| File | What |
|---|---|
| `report.md`, `results.csv`, `results.json` | harness output: every counter of all 712 region results, metadata (commit, rtl tree, tool versions, image sha256s, build commands) |
| `runs/` | UART log and `SIGIL_PERF` records of all 56 simulations |
| `build-logs/` | the build log of each of the 14 images, with the compiler command lines (CoreMark's includes the fresh pinned-source fetch) |
| `perf-run.log` | the `make perf` console output, with the start and end times |
| `compare-evidence.log`, `compare_evidence.py` | this run against each branch's evidence result set, run by run |
| `harness-options-smoke.log`, `variant_opts_test.py` | smoke tests of the new harness options (below); not results |

## Setup

- **Design.** `rtl/` tree `89b98cb227c6`: main `eeaa332` plus the
  harness's simulation-only counter block, the same tree as every #56
  baseline. No #53 pipelining is included.
- **Code.** `56-perf-harness` at `662bad7` (clean tree): the four
  merges plus the harness changes (`8ad310c`) and the bench.json
  metadata (`662bad7`). Later commits change only documentation and,
  in `b3a0a1c`, stop a `make -s` from silencing the bench build logs;
  none of them changes an image.
- **Run.** `make -C sim perf CONFIG=default MEM="soc axi" REPEAT=2
  JOBS=12 VJOBS=12 CLOCK_MHZ="62.5 100"` (every bench) on sigil-verify
  (c7i.8xlarge, Ubuntu 24.04), 2026-10-22T11:05:49Z to
  2026-10-22T11:11:11Z (5 min 21 s, including the testbench builds).
  Verilator 5.048, riscv64-unknown-elf-gcc 16.1.0 (`deps/`), Python
  3.12.3.
- **Benchmarks.** 10 benchmarks, 14 images (bench × variant), 2 memory
  models, 2 repeats: 56 simulations and 712 region results
  (dhrystone 8, coremark 12, kernels 224, micro_pipe 104,
  micro_units 72, micro_dmem 76, micro_imem 44, micro_vec 124,
  sha256chain 28, sha256chain_bulk 20).

## Validation

- **All 712 region results are valid**, with 0 failures. Each run
  passed the harness checks: the exit string after the program's own
  checks, every `expect` line, one `SIGIL_PERF` record per region with
  `cycles` = `mcycle` delta, `instret` = `minstret` delta and the
  accounting summing to `cycles`, and the hardware-counter line within
  the window. The programs' own checks are CoreMark's CRCs against
  native references, Dhrystone's final values, the kernels'
  bit-exact reference and known answers, the micro kernels' values
  computed in C, and the SHA FIPS known answers and `hashlib` values.
- **Deterministic.** Both repeats are identical
  (`perf: determinism over 2 repeats: PASS`).
- **Identical to the branch evidence** (`compare-evidence.log`). For
  every (bench, variant, region, memory model, repeat), the image
  sha256, every `SIGIL_PERF` counter and the hardware-counter numbers
  match the evidence set that first reported them: dhrystone 8/8
  (`perf-dhrystone-56-2026-10-22`, default configuration), coremark
  12/12, kernels 224/224, micro 420/420, sha256chain 48/48. The
  integration therefore changed no image and no count. CoreMark's
  sources were fetched afresh into this worktree and passed the pinned
  sha256 checks (`build-logs/build-coremark-scalar.log`).

## Harness changes checked here

The benchmark branches asked for these (`docs/PERFORMANCE.md` §1, §5,
§7, §8). `report.md` above uses all of the report-side ones:

- per-region `bytes_per_iteration`: `sha256chain` now reports
  bytes/cycle for every region, with 64-byte messages for the SHA-512
  chain. The values match the program's own `RESULT` lines;
- per-region `work_per_iteration`/`work_unit` and `baseline`: the
  kernels' work/cycle is in the summary's *Metric* column, and the
  *Speedups* table lists the kernels' RVV speedups over C and the
  SHA-256 speedups over plain C;
- `window_region`: the `micro_*` benches' *Net cycles/iter* column;
- `CLOCK_MHZ`: the projected-throughput table at 62.5 and 100 MHz.
  This is arithmetic on simulation cycles, not a hardware
  measurement;
- cycles/iteration with two decimals, and one row per run in the
  accounting and event tables when there are more than 8 runs;
- `cc_commands`: every compiler line of each build.

`harness-options-smoke.log` (commit `b3a0a1c`, 2026-10-22T11:14:21Z)
exercises the options this run does not use. None of these runs is a
result:

1. `VARIANTS=scalar MAX_CYCLES=5000000 ITER=5` under `make -s`: only
   the `scalar` variants run, with the overridden limit recorded per
   run and in the metadata, and the compiler lines are kept;
2. `MAX_CYCLES=200000`, below one CoreMark iteration: the run fails;
3. `VARIANTS=nosuch` is refused;
4. `VARIANTS=sdk` over `dhrystone micro_units` skips `micro_units`;
5. per-variant `regions` and `expect`, with `sha256chain`'s variants
   replaced in memory by `variant_opts_test.py`. A variant that lists
   all 7 regions and adds a printed `expect` line passes (7/7). A
   variant that lists only regions 0 and 5 fails on the undeclared
   records. A variant with an `expect` line that is never printed
   fails.
