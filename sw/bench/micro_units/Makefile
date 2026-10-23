# micro_units: M unit and FPU latency and back-to-back throughput in
# cycles per operation (../micro_common/README.md). Run by the
# performance harness: make -C sim perf BENCHES=micro_units. `make`
# here builds build/micro_units.{elf,bin,dis}; `make run` runs it on
# soc_rtl_tb.
PROG := micro_units

# Operations per region (the harness passes bench.json's
# "iterations"); a multiple of 64 keeps every region exact.
BENCH_ITERATIONS ?= 1024

include ../micro_common/micro.mk
