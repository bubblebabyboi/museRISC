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
