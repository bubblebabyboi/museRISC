# Bulk hashing benchmark (../sha256chain/README.md). Built with the Sigil
# SDK; run by the performance harness:
# make -C sim perf BENCHES=sha256chain_bulk. `make` here builds
# build/sha256chain_bulk.{elf,bin,dis}; `make run` runs it on soc_rtl_tb.
# Needs python3 (../sha256chain/gen_kat.py: the expected digests for this
# buffer size, from hashlib).
PROG      := sha256chain_bulk
SIGIL_SDK := ../../sdk
OUT       ?= build
COMMON    := ../sha256chain
SRCS      := sha256chain_bulk.c $(COMMON)/sha256_sw.c $(COMMON)/sha256_rvv.c \
             $(COMMON)/sha256_kat.c

# KiB hashed per region (the harness passes bench.json's "iterations").
BENCH_ITERATIONS ?= 64

KAT_H := $(OUT)/sha256chain_bulk_kat_$(BENCH_ITERATIONS).h
EXTRA_CFLAGS += -DSHA256CHAIN_KIB=$(BENCH_ITERATIONS) \
                -DSHA256CHAIN_KAT_H='"$(notdir $(KAT_H))"' -I$(OUT) -I$(COMMON)

include $(SIGIL_SDK)/sdk.mk

$(ELF): $(KAT_H) $(COMMON)/gen_kat.py $(COMMON)/sha256_bench.h

$(KAT_H): $(COMMON)/gen_kat.py | $(OUT)
	python3 -I $(COMMON)/gen_kat.py bulk $(BENCH_ITERATIONS) > $@.tmp && mv $@.tmp $@
