# micro_pipe: fetch/ALU, branch and jump, L1 load/store hit, load-use
# and CSR costs in cycles per operation (../micro_common/README.md).
# Run by the performance harness: make -C sim perf BENCHES=micro_pipe.
# `make` here builds build/micro_pipe.{elf,bin,dis}; `make run` runs it
# on soc_rtl_tb.
PROG := micro_pipe

# Operations per region (the harness passes bench.json's
# "iterations"); a multiple of 256 keeps every region exact.
BENCH_ITERATIONS ?= 4096

include ../micro_common/micro.mk
