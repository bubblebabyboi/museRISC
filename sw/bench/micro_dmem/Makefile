# micro_dmem: data-side memory hierarchy (pointer chase over a sweep of
# working-set sizes, load and store streams) in cycles per load/store
# (../micro_common/README.md). Run by the performance harness:
# make -C sim perf BENCHES=micro_dmem. `make` here builds
# build/micro_dmem.{elf,bin,dis}; `make run` runs it on soc_rtl_tb.
PROG := micro_dmem

# Loads/stores per region (the harness passes bench.json's
# "iterations"); a multiple of 64 keeps every region exact.
BENCH_ITERATIONS ?= 4096

include ../micro_common/micro.mk
