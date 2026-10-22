# EEMBC CoreMark (README.md). Built with the Sigil SDK; run by the
# performance harness: make -C sim perf BENCHES=coremark.
# `make` here builds build/coremark.{elf,bin,dis}; `make run` runs it
# on soc_rtl_tb. The benchmark sources are the unmodified EEMBC files at
# a pinned commit, fetched into the git-ignored third_party/coremark by
# fetch_coremark.sh on first use (needs network once); only the porting
# layer core_portme.{c,h} lives here.
PROG      := coremark
SIGIL_SDK := ../../sdk

COREMARK_DIR ?= $(abspath ../../../third_party/coremark)
COREMARK_SRCS := $(addprefix $(COREMARK_DIR)/,core_list_join.c core_main.c \
                   core_matrix.c core_state.c core_util.c)
SRCS := $(COREMARK_SRCS) core_portme.c

# Timed iterations (the harness passes bench.json's "iterations").
BENCH_ITERATIONS ?= 20
# Seeds: performance (0,0,0x66) or validation (0x3415,0x3415,0x66);
# EEMBC run rule 2 requires both to validate.
COREMARK_RUN ?= performance
# Clock that converts CoreMark's ticks (mcycle) to seconds in its
# printout: the F2 B1 build's 62.5 MHz (docs/FPGA_F2.md).
COREMARK_CLOCK_HZ ?= 62500000

ifeq ($(COREMARK_RUN),performance)
COREMARK_RUN_DEF := -DPERFORMANCE_RUN=1
else ifeq ($(COREMARK_RUN),validation)
COREMARK_RUN_DEF := -DVALIDATION_RUN=1
else
$(error COREMARK_RUN must be performance or validation)
endif

EXTRA_CFLAGS += -I. -I$(COREMARK_DIR) -DITERATIONS=$(BENCH_ITERATIONS) \
                $(COREMARK_RUN_DEF) -DSIGIL_COREMARK_CLOCK_HZ=$(COREMARK_CLOCK_HZ)u

include $(SIGIL_SDK)/sdk.mk

# CoreMark prints its compiler flags: sdk.mk's code-generation flags
# (CFLAGS without -D/-I/-W/-g), so the report states what was built.
COREMARK_FLAGS_STR := $(filter-out -D% -I% -W% -g,$(CFLAGS))
CFLAGS += -DFLAGS_STR='"$(COREMARK_FLAGS_STR)"'

# Fetch the pinned sources on first use; the script checks every
# file's sha256 before writing the stamp.
COREMARK_STAMP := $(COREMARK_DIR)/.sigil-fetched
$(COREMARK_STAMP): fetch_coremark.sh
	bash $(CURDIR)/fetch_coremark.sh $(COREMARK_DIR)
$(COREMARK_SRCS) $(COREMARK_DIR)/coremark.h: | $(COREMARK_STAMP)

$(ELF): $(COREMARK_DIR)/coremark.h core_portme.h

.PHONY: fetch
fetch: $(COREMARK_STAMP)
