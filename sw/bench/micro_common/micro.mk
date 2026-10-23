# Shared build rules for the micro_* benchmarks (README.md here). A
# bench Makefile is
#
#   PROG := micro_xxx
#   BENCH_ITERATIONS ?= N        # operations per region
#   include ../micro_common/micro.mk
#
# Sources: main.c (driver, self-checks) + kernels.S (measured loops).
# The C code is built for the scalar ISA (no V), so compiled code
# never touches vector state between the micro_vec kernels; kernels.S
# enables V itself where it needs it. The usual sdk.mk overrides (OUT,
# RISCV_PREFIX, SIGIL_MARCH, OPT, ...) work as for any SDK program.
MICRO_COMMON := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SIGIL_SDK    ?= $(MICRO_COMMON)/../../sdk
SIGIL_MARCH  ?= rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
SRCS         ?= main.c kernels.S

EXTRA_CFLAGS += -I$(MICRO_COMMON) -DMICRO_ITERS=$(BENCH_ITERATIONS)

include $(SIGIL_SDK)/sdk.mk

$(ELF): $(MICRO_COMMON)/micro.h $(MICRO_COMMON)/micro_asm.h $(MICRO_COMMON)/micro.mk
