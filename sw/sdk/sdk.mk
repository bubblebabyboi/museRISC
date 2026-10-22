# Sigil bare-metal SDK build rules. A program's Makefile is:
#
#   PROG      := myprog                 # image name (and test name)
#   SRCS      := myprog.c util.c        # optional, default: all *.c *.S here
#   SIGIL_SDK := ../../sdk              # path to sw/sdk
#   include $(SIGIL_SDK)/sdk.mk
#
# `make` builds $(OUT)/$(PROG).elf, .bin (flat image for 0x8000_0000,
# what soc_rtl_tb --load and sigil_host --bin take) and .dis
# (disassembly). `make run` builds the RTL SoC simulator if needed and
# runs the image to its PASS/FAIL line. Variables you can override:
#   OUT=dir            build directory (default ./build)
#   OPT=-O2            optimisation level
#   EXTRA_CFLAGS=...   added to CFLAGS (e.g. -DFOO)
#   STACK_SIZE=65536   stack bytes (link.ld default 64 KiB)
#   RISCV_PREFIX=riscv64-elf-   toolchain prefix (auto-detected)
#   MAX_CYCLES=200000000        `make run` cycle limit
#   SIM_ARGS=...       extra soc_rtl_tb arguments (e.g. --no-cache)
# Guide: docs/PROGRAMMING.md.

SIGIL_SDK  := $(abspath $(SIGIL_SDK))
SIGIL_ROOT := $(abspath $(SIGIL_SDK)/../..)

RISCV_PREFIX ?= $(shell command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 \
                  && echo riscv64-unknown-elf- || echo riscv64-elf-)
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
SIZE    := $(RISCV_PREFIX)size

# What the core implements (docs/CORE.md; misa = RV64IMAFDCBHV + SU):
# RV64GC + V (RVV 1.0, VLEN 512, ELEN 64) + B (Zba/Zbb/Zbs) + Zbc + Zcb
# + Zicond + scalar crypto Zbkb/Zbkx/Zkne/Zknd/Zknh.
SIGIL_MARCH ?= rv64gcv_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
SIGIL_MABI  ?= lp64d

comma := ,
OUT  ?= build
OPT  ?= -O2
SRCS ?= $(wildcard *.c *.S)

SDK_SRCS := $(SIGIL_SDK)/lib/crt0.S $(SIGIL_SDK)/lib/runtime.c \
            $(SIGIL_SDK)/lib/accel.c $(SIGIL_SDK)/lib/ed25519.c
SDK_DEPS := $(SDK_SRCS) $(SIGIL_SDK)/include/sigil.h \
            $(SIGIL_ROOT)/sw/sigil_crypto.h $(SIGIL_SDK)/link.ld \
            $(SIGIL_SDK)/sdk.mk

# -mstrict-align: misaligned loads/stores trap on this core.
CFLAGS := -march=$(SIGIL_MARCH) -mabi=$(SIGIL_MABI) -mcmodel=medany \
          -mstrict-align $(OPT) -g -std=gnu11 -Wall -Wextra \
          -ffreestanding -fno-common -ffunction-sections -fdata-sections \
          -fno-asynchronous-unwind-tables \
          -I$(SIGIL_SDK)/include -I$(SIGIL_ROOT)/sw \
          -DSIGIL_PROG='"$(PROG)"' $(EXTRA_CFLAGS)
LDFLAGS := -nostdlib -nostartfiles -static -T $(SIGIL_SDK)/link.ld \
           -Wl,--gc-sections -Wl,--no-warn-rwx-segments \
           $(if $(STACK_SIZE),-Wl$(comma)--defsym=__stack_size=$(STACK_SIZE))

ELF := $(OUT)/$(PROG).elf
BIN := $(OUT)/$(PROG).bin

.PHONY: all run clean
all: $(BIN) $(OUT)/$(PROG).dis

# Single compile+link step: the SDK is a handful of files, so it is
# built with each program (no separate library to keep in sync).
$(ELF): $(SRCS) $(SDK_DEPS) $(wildcard *.h) | $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SDK_SRCS) $(SRCS) -lgcc -o $@
	@$(SIZE) $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(OUT)/$(PROG).dis: $(ELF)
	$(OBJDUMP) -d -S $< > $@

$(OUT):
	mkdir -p $@

# ---- run on the RTL SoC simulator (sim/Makefile `soc_rtl_tb`) ----
SOC_RTL_TB := $(SIGIL_ROOT)/build/sim/soc_rtl_tb
MAX_CYCLES ?= 200000000
SIM_ARGS   ?=

run: $(BIN)
	$(MAKE) -C $(SIGIL_ROOT)/sim ../build/sim/soc_rtl_tb
	$(SOC_RTL_TB) $(MAX_CYCLES) $(SIM_ARGS) --load 0x80000000=$(abspath $(BIN)) \
	  --exit-string "SIGIL TEST PASS $(PROG)" --fail-string "SIGIL TEST FAIL"

clean:
	rm -rf $(OUT)
