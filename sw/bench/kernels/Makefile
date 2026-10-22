# Vector and FP kernels, C vs RVV (README.md). Built with the Sigil SDK;
# run by the performance harness: make -C sim perf BENCHES=kernels.
# `make` here builds build/kernels.{elf,bin,dis}; `make run` runs it on
# soc_rtl_tb.
PROG      := kernels
SIGIL_SDK := ../../sdk
OUT       ?= build

# Calls of each kernel per measured region (the harness passes
# bench.json's "iterations").
BENCH_ITERATIONS ?= 4

# The scalar ISA: everything the core implements except V (as
# Dhrystone's headline build).
KERNELS_SCALAR_MARCH ?= rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
# The C kernels (kern_c.c): the scalar ISA by default, the scalar
# baseline. The "autovec" variant sets the SDK -march (with V) so GCC
# auto-vectorizes them.
KERNELS_C_MARCH ?= $(KERNELS_SCALAR_MARCH)
KERNELS_C_OPT   ?= -O2

# main.c and kern_rvv.c are compiled and linked by sdk.mk with the SDK
# flags and -march (with V). kern_c.c and ref.c are compiled to objects
# here with their own -march/-O and linked in.
SRCS := main.c kern_rvv.c $(OUT)/kern_c.o $(OUT)/ref.o
EXTRA_CFLAGS += -DKERNELS_ITERATIONS=$(BENCH_ITERATIONS)

include $(SIGIL_SDK)/sdk.mk

C_OBJ_CFLAGS   = $(filter-out -march=% $(OPT),$(CFLAGS)) -march=$(KERNELS_C_MARCH) $(KERNELS_C_OPT)
# Reference: scalar ISA, -O1, no vectorization, no loop -> memcpy/memset
# call conversion, no FMA contraction.
REF_OBJ_CFLAGS = $(filter-out -march=% $(OPT),$(CFLAGS)) -march=$(KERNELS_SCALAR_MARCH) -O1 \
                 -fno-tree-vectorize -fno-tree-loop-distribute-patterns -ffp-contract=off

# Fails if a scalar-ISA object contains a vector instruction (every
# RISC-V mnemonic starting with "v" is one).
has_v = $(findstring v,$(firstword $(subst _, ,$(1))))
define check_no_vector
	@$(OBJDUMP) -d $(1) | awk -F'\t' '$$3 ~ /^v/ {print; bad = 1} END {exit bad}' >&2 || \
	  { echo "$(1): vector instructions in a scalar-ISA build" >&2; exit 1; }
endef

$(OUT)/kern_c.o: kern_c.c kernels.h $(SDK_DEPS) | $(OUT)
	$(CC) $(C_OBJ_CFLAGS) -c $< -o $@
	$(if $(call has_v,$(KERNELS_C_MARCH)),,$(call check_no_vector,$@))

$(OUT)/ref.o: ref.c kernels.h $(SDK_DEPS) | $(OUT)
	$(CC) $(REF_OBJ_CFLAGS) -c $< -o $@
	$(call check_no_vector,$@)

$(ELF): kernels.h kernels_kat.h
