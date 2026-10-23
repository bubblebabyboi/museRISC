# micro_vec: vsetvli cost and element-serial vector throughput versus VL,
# in cycles per vector instruction (../micro_common/README.md). Run by
# the performance harness: make -C sim perf BENCHES=micro_vec. `make`
# here builds build/micro_vec.{elf,bin,dis}; `make run` runs it on
# soc_rtl_tb.
PROG := micro_vec

# Vector instructions per region (the harness passes bench.json's
# "iterations"); a multiple of 32 keeps every region exact.
BENCH_ITERATIONS ?= 256

include ../micro_common/micro.mk
