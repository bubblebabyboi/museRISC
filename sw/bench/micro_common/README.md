# Micro benchmarks

Microbenchmarks for the performance harness (issue #56,
[`docs/PERFORMANCE.md`](../../../docs/PERFORMANCE.md)). Each region
isolates one mechanism and reports its cost in **cycles per operation**.
They calibrate the per-cycle accounting that the larger benchmarks
(Dhrystone, CoreMark, kernels) are analysed with: what a taken branch,
a load hit, a D$ miss or a vector element actually costs on this core.

This directory holds the code the five benchmarks share. It is not a
benchmark itself: it has no `bench.json`, so the harness skips it.
Measured numbers are in [`docs/evidence/`](../../../docs/evidence/README.md)
(`perf-micro-56-*`).

| Benchmark | Measures | Operation | Ops per region |
|---|---|---|---:|
| [`micro_pipe`](../micro_pipe) | fetch and ALU, branches, jumps, calls, branch patterns, L1 load/store hits, load-use, CSR access, `fence` | one instruction (call+return pairs, load+use pairs, pattern branches: see `bench.json`) | 4,096 |
| [`micro_units`](../micro_units) | M unit and FPU latency (dependent chain) and back-to-back throughput (independent ops) | one instruction | 1,024 |
| [`micro_dmem`](../micro_dmem) | pointer-chase latency over working sets of 1 KiB to 256 KiB (random and address order); load and store streams | one load or store | 4,096 |
| [`micro_imem`](../micro_imem) | instruction fetch over straight-line code footprints of 1 KiB to 32 KiB | one instruction | 49,152 |
| [`micro_vec`](../micro_vec) | `vsetvli`; `vadd.vv`, `vle8.v`, `vse8.v` versus VL (1 to 512); e64 `vadd`/`vmul`/`vfadd`/`vredsum` | one vector instruction | 256 |

Every region of a benchmark runs exactly `iterations` operations
(`bench.json`), so the harness's *cycles/iter* is cycles per operation.
Each `bench.json` lists its regions and, under `region_ops`, what one
operation is (the harness carries that key into `results.json`).

## Running

```sh
source deps/env.sh
make -C sim perf BENCHES="micro_pipe micro_units micro_dmem micro_imem micro_vec" \
    CONFIG=default MEM="soc axi" REPEAT=2 JOBS=8
sw/bench/micro_common/micro_table.py build/perf/run      # per-op tables (markdown)
```

[`micro_table.py`](micro_table.py) reads `results.json` and prints, per
benchmark and region: cycles per operation for every configuration and
memory model, the same net of the measurement window, instructions per
operation, where the cycles go per operation (the `stk_*` accounting),
and the I$/D$ misses per operation. It then derives the cache
parameters the sweeps show: the miss penalties and the largest working
set and code footprint that still hit. The harness's own `report.md`
has the same counters as percentages.

To run one benchmark outside the harness: `make -C sw/bench/micro_pipe
run`. Each region also prints its hardware-counter view, which is what a
run on F2 reports:

```text
MICRO region=8 br_taken ops=4096 cycles=16529 instret=4143 cycles/op=4.035
```

## Method

**Kernels.** The measured code is assembly (`kernels.S` in each
benchmark), so no compiler choice changes what is measured. A kernel is
a leaf function: `a0` = loop trips, its operands in `a1..`/`fa0..`, its
result in `a0`/`fa0`. It uses only caller-saved registers and no stack.
Each kernel starts on a 64-byte (I$ line) boundary. Kernels are
assembled with 32-bit encodings (`.option norvc`), so every instruction
starts on a fetch word. The exceptions are `alu16_dep` (`c.add`) and
`alu32_straddle`, which is shifted by a `c.nop` so that every 32-bit
instruction straddles two fetch words. The loop body unrolls U
operations: 256 in `micro_pipe`, 64 in `micro_units` and `micro_dmem`,
32 in `micro_vec`. In `micro_imem` the body is one pass over the
footprint.

**Region.** `main.c` runs every region the same way:

1. A **warm-up** call runs outside the window. It fetches the kernel
   into the I$ and its data into the D$.
2. `sigil_perf_begin_id(id)`, then the measured kernel call, then
   `sigil_perf_end_id(id)`.
3. The `MICRO` line, then the **self-check**: the kernel's result is
   compared with a value computed independently in C, for example
   `x + 3 * ops` for the add chain, the not-taken count of a branch
   pattern, the node reached after a chase, or the stored vector
   elements. Any mismatch fails the program, so the run is not a
   result.

The program prints `MICRO CHECK OK <bench> iterations=<n>
regions=<r>` (the `bench.json` `expect` line) only after every region
ran and every check matched.

**What a raw number includes.** Besides the operation itself, a raw
number includes:

- the **window overhead**: the marker CSR writes, the counter reads and
  the kernel call and return: 66 to 131 cycles per region in the
  default configuration. Each
  benchmark's `empty` region measures it, and `micro_table.py`
  subtracts it in the *net of window* column. It is 0.016 cycles/op in
  `micro_pipe`, 0.07 in `micro_units` and 0.3 in `micro_vec`.
- the **loop overhead**: one `addi` and one taken `bnez` per trip.
  `micro_pipe`'s `loop` region measures that trip at 6 cycles, which is
  at most 6/U cycles per operation (0.023 in `micro_pipe`). A
  multi-cycle operation hides most of it, because the loop instructions
  are fetched while the unit holds EX.

The bounds are small next to every cost measured here, so the tables
quote the raw and the net-of-window values and subtract nothing else.

**Data side (`micro_dmem`).**

- **Chase.** One 8-byte pointer per 64-byte line, one node per line.
  The chain is a random single cycle (Sattolo's algorithm, fixed seed)
  or address order, and C checks the cycle length.
- **Before each chase region.** `FENCE.I` cleans the D$ (it writes back
  every dirty line), so no victim in the region is dirty. Then the
  chain is walked: 8 passes for working sets up to 32 KiB, 1 pass above.
  The region therefore sees the steady state of a cache that is full of
  valid lines. That matters because the replacement pointer is
  round-robin and shared by all sets.
- **Streams.** They run over 64 KiB buffers, four times the default D$.
  One warm-up pass runs first, then the region reads or writes `ops`
  doublewords from the start of the buffer:
  - `stream_ld`: 8 independent loads per line, no consumer;
  - `stream_st`: stores into lines that are all dirty, so every miss
    writes a line back and then refills one.

**Instruction side (`micro_imem`).** A 32 KiB block of `addi a1, a1, 1`
ends in `ret`. A footprint of S bytes is the last S bytes of the block:
the driver `jalr`s to `end - S`, runs S/4 instructions and returns. That
pass repeats until 49,152 instructions have run. Per pass the driver
adds 4 instructions (`jalr`, `ret`, `addi`, `bnez`). The check is the
`addi` count.

**Vector (`micro_vec`).**

- **No vector state in C.** The C driver is built without V (`micro.mk`
  sets a scalar `-march` for every micro benchmark; `kernels.S` enables
  V with `.option arch, +v`), so compiled code never touches vector
  state between kernel calls.
- **Operands and results.** A setup kernel loads the operands (v8 and
  v16) and sets `vl`/`vtype` before the window. Another stores v8 after
  it, and C checks the stored elements.
- **The `vadd`, `vmul`, `vfadd` and `vredsum` chains** are dependent
  through v8.
- **`vle8` and `vse8`** hit in the D$. The warm-up `vle8` loads a
  different buffer than the region does, so the check proves the
  region's loads ran.

**Determinism.** The programs have no input. Their data comes from a
fixed-seed xorshift generator, and both memory models are
deterministic, so every repeat gives identical counts. The harness
checks this with `REPEAT=2`.

**Iteration overrides.** `make perf ITER=n` with an `n` that is not a
multiple of the unroll (the `Makefile` comments give it) rounds each
region up to whole trips. The `MICRO` line prints the exact op count,
but the harness's cycles/iter then divides by `n`. Use such runs only
as smoke tests.

## Files

| File | Purpose |
|---|---|
| `micro.h` | C driver helpers: `MICRO_REGION`, checks, the `MICRO` line, `micro_finish`, the fixed-seed generator |
| `micro_asm.h` | `MICRO_FUNC` / `MICRO_ENDF` for the kernels |
| `micro.mk` | shared Makefile part: scalar `-march`, `main.c` + `kernels.S`, `-DMICRO_ITERS=$(BENCH_ITERATIONS)`, includes `sw/sdk/sdk.mk` |
| `micro_table.py` | per-operation tables and derived cache parameters from `results.json` |
