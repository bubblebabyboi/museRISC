# Dhrystone 2.1 benchmark (README.md). Built with the Sigil SDK; run
# by the performance harness: make -C sim perf BENCHES=dhrystone.
# `make` here builds build/dhrystone.{elf,bin,dis}; `make run` runs it
# on soc_rtl_tb.
PROG      := dhrystone
SIGIL_SDK := ../../sdk
SRCS      := dhry_1.c dhry_2.c sigil_port.c

# Runs through the benchmark (the harness passes bench.json's
# "iterations").
BENCH_ITERATIONS ?= 2000

# Dhrystone ground rules (RATIONALE, section 5): separate compilation
# of dhry_1.c / dhry_2.c (sdk.mk compiles each file separately, no
# LTO) and no procedure merging (-fno-inline). The 1988 source is K&R
# C (implicit int, undeclared calls), accepted under sdk.mk's gnu11
# with those diagnostics off (GCC 14+ makes them errors by default).
# -DTIME picks dhry.h's time() variant (stubbed in sigil_port.c) over
# times(); -Iport supplies <stdio.h>.
EXTRA_CFLAGS += -fno-inline -DSIGIL_PORT -DTIME \
                -DSIGIL_DHRY_RUNS=$(BENCH_ITERATIONS) -Iport \
                -Wno-implicit-int -Wno-implicit-function-declaration \
                -Wno-return-type -Wno-pointer-to-int-cast

include $(SIGIL_SDK)/sdk.mk

$(ELF): port/stdio.h dhry.h
