# micro_imem: instruction fetch over a sweep of straight-line code
# footprints (1..32 KiB), in cycles per instruction
# (../micro_common/README.md). Run by the performance harness:
# make -C sim perf BENCHES=micro_imem. `make` here builds
# build/micro_imem.{elf,bin,dis}; `make run` runs it on soc_rtl_tb.
PROG := micro_imem

# Instructions per region (the harness passes bench.json's
# "iterations"); a multiple of 6144 (= lcm of the per-pass instruction
# counts) keeps every region exact.
BENCH_ITERATIONS ?= 49152

include ../micro_common/micro.mk
