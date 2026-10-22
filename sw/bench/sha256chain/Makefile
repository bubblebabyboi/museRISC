# SHA-256 hash chain benchmark (README.md). Built with the Sigil SDK;
# run by the performance harness: make -C sim perf BENCHES=sha256chain.
# `make` here builds build/sha256chain.{elf,bin,dis}; `make run` runs it
# on soc_rtl_tb. Needs python3 (gen_kat.py: the expected chain values
# for this hash count, from hashlib).
PROG      := sha256chain
SIGIL_SDK := ../../sdk
OUT       ?= build
SRCS      := sha256chain.c sha256_sw.c sha256_rvv.c sha256_kat.c

# Hashes per region (the harness passes bench.json's "iterations").
BENCH_ITERATIONS ?= 1024

KAT_H := $(OUT)/sha256chain_kat_$(BENCH_ITERATIONS).h
# Every function starts on an I$ line (64 B). The front end fetches
# 4-byte words, so a 2-byte shift of a function changes which 32-bit
# instructions straddle two words: with the same instructions, the Zknh
# chain took 7,212 cycles/hash at offset 2 mod 4 and 6,758 at offset 0.
# Aligning keeps each region's code placement independent of the code
# linked before it (the iteration count, linker relaxation).
EXTRA_CFLAGS += -falign-functions=64
EXTRA_CFLAGS += -DSHA256CHAIN_HASHES=$(BENCH_ITERATIONS) \
                -DSHA256CHAIN_KAT_H='"$(notdir $(KAT_H))"' -I$(OUT)

include $(SIGIL_SDK)/sdk.mk

$(ELF): $(KAT_H) gen_kat.py

$(KAT_H): gen_kat.py | $(OUT)
	python3 -I gen_kat.py chain $(BENCH_ITERATIONS) > $@.tmp && mv $@.tmp $@
