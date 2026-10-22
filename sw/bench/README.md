# Benchmarks

Each directory here is one benchmark for the performance harness:
`make -C sim perf` builds and runs it, validates it, and tabulates
cycles, instret, IPC, the per-cycle accounting and the benchmark's
metric. To add a benchmark, create `<name>/` with a `Makefile` on
`sw/sdk/sdk.mk` and a `bench.json`. The harness finds it
automatically; no shared file changes. Interface, validation rules and
metrics: [`docs/PERFORMANCE.md`](../../docs/PERFORMANCE.md) §5–7.

| Benchmark | Metric |
|---|---|
| [`dhrystone`](dhrystone/README.md) | DMIPS/MHz |
| [`coremark`](coremark/README.md) | CoreMark/MHz |
| [`kernels`](kernels/README.md) | work/cycle per kernel, RVV speedup over C |
| [`micro_pipe`](micro_pipe), [`micro_units`](micro_units), [`micro_dmem`](micro_dmem), [`micro_imem`](micro_imem), [`micro_vec`](micro_vec) | cycles per operation ([`micro_common`](micro_common/README.md): shared code and method; not a benchmark) |
| [`sha256chain`](sha256chain/README.md) | cycles/hash, bytes/cycle |
| [`sha256chain_bulk`](sha256chain_bulk/README.md) | bytes/cycle |
