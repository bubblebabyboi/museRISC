# Verilator C++ testbenches for the in-house core (issue #18).
# Everything builds and runs on the host: verilator, verilator_coverage,
# and a riscv64 bare-metal gcc (riscv64-unknown-elf- or riscv64-elf-).
#
#   make -C sim            # unit + core tests, prints coverage summary
#   make -C sim coverage   # (re)build the annotated coverage report
#
# Coverage .dat files from every run in this directory's build output
# are merged; the annotated report lands in build/sim/coverage/.

ROOT   := ..
RTL    := $(ROOT)/rtl/core
CRYPTO := $(ROOT)/rtl/crypto
BUILD  := $(ROOT)/build/sim
OBJ    := $(BUILD)/obj

VERILATOR ?= verilator
# Verilator build/verilation jobs; 0 = all cores. CI sets VJOBS=1: Ubuntu's
# Verilator 5.020 intermittently aborts with "attempted to destroy locked
# Thread Pool" when verilating multi-threaded.
VJOBS     ?= 0
VFLAGS    := --cc --exe --build -j $(VJOBS) -Wall -Wno-DECLFILENAME \
             --coverage-line --coverage-toggle --assert -I$(RTL) \
             -CFLAGS "-std=c++17 -O2" --Mdir
# The platform harness writes no coverage; build it without the
# (expensive) coverage instrumentation for long OS boots.
VFLAGS_FAST := --cc --exe --build -j $(VJOBS) -Wall -Wno-DECLFILENAME --assert -O3 -I$(RTL) \
               -CFLAGS "-std=c++17 -O2" --Mdir
PKG       := $(RTL)/sigil_pkg.sv
# `included by sigil_fpu_pkg.sv and sigil_fpu.sv (dependency only)
FPU_INC   := $(RTL)/sigil_fpu_ops.svh
# Harness bus timing for the randomized-latency runs (core_tb).
CORE_RAND_ARGS := --mem-lat 1:6 --mem-gap 2 --mem-ready 70

RISCV_PREFIX ?= $(shell command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 \
                  && echo riscv64-unknown-elf- || echo riscv64-elf-)
RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
SWFLAGS       := -march=rv64imafdc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh_zicsr_zifencei -mabi=lp64 -nostdlib -T $(ROOT)/sw/core-tests/link.ld

CORE_RTL := $(PKG) $(RTL)/sigil_regfile.sv \
            $(RTL)/sigil_fpregfile.sv $(RTL)/sigil_alu.sv \
            $(RTL)/sigil_muldiv.sv \
            $(RTL)/sigil_muldiv_mc.sv \
            $(RTL)/sigil_fpu_pkg.sv $(RTL)/sigil_fpu.sv \
            $(RTL)/sigil_bext_pkg.sv $(RTL)/sigil_bext.sv \
            $(RTL)/sigil_vregfile.sv \
            $(RTL)/sigil_vec_pkg.sv $(RTL)/sigil_vec.sv \
            $(RTL)/sigil_rvc.sv \
            $(RTL)/sigil_decoder.sv \
            $(RTL)/sigil_csr.sv $(RTL)/sigil_mmu.sv \
            $(RTL)/sigil_cache_pkg.sv $(RTL)/sigil_core.sv
# L1 caches + CPU wrapper (sigil_cpu is the harness top).
CACHE_RTL := $(RTL)/sigil_cache_pkg.sv $(RTL)/sigil_sram_sp.sv \
             $(RTL)/sigil_icache.sv $(RTL)/sigil_dcache.sv \
             $(RTL)/sigil_bus_arb.sv
CPU_RTL  := $(CORE_RTL) $(filter-out $(RTL)/sigil_cache_pkg.sv,$(CACHE_RTL)) \
            $(RTL)/sigil_cpu.sv
TESTS    := rv64i_directed rv64m_directed md_directed md_irq_directed md_kill_directed irq_exc_race_directed amo_directed fp_directed fp_stall_directed fp_irq_directed bext_directed rvc_directed pipeline_directed priv_directed counter_time_directed hyp_directed vec_directed fpvec_directed vec_trap_directed \
            vm_directed \
            trap_illegal trap_misalign trap_ecall trap_ebreak \
            trap_store_misalign trap_younger_store trap_younger_csr irq_seip_rmw irq_mip_rmw_variants \
            trap_pa_fetch trap_pa_load \
            smc_fencei_directed amo_cache_directed mmio_bypass_directed \
            vm_sfence_cache_directed fp_hold_cache_directed ptw_drop_directed

.PHONY: all alu muldiv muldiv_mc decoder regfile csr plic mmu fpu fpu-ds1 bext rvc vec vec-xinit icache dcache core core-ds1 core-xinit sw coverage clean riscv-tests \
        crypto sha256 sha512 keccak ecfield cryptotop hashstream sochash core-mdcomb srammacro directed-bins
all: alu muldiv muldiv_mc decoder regfile csr plic mmu fpu fpu-ds1 bext rvc vec vec-xinit icache dcache core core-ds1 core-mdcomb core-xinit srammacro coverage

## ---- Stage gate: upstream riscv-tests (not part of `all`) -------------
# Caches on, seeded random bus latency/gaps/backpressure.
riscv-tests: $(BUILD)/core_tb
	CORE_TB_ARGS="$(CORE_RAND_ARGS)" bash $(ROOT)/sim/run_riscv_tests.sh

$(BUILD) $(OBJ):
	mkdir -p $@

## ---- ALU unit test ----------------------------------------------------
$(BUILD)/alu_tb: $(ROOT)/tb/cpp/alu_tb.cpp $(PKG) $(RTL)/sigil_alu.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/alu --top-module sigil_alu \
	  -o $(abspath $(BUILD)/alu_tb) $(PKG) $(RTL)/sigil_alu.sv \
	  $(abspath $(ROOT)/tb/cpp/alu_tb.cpp)

alu: $(BUILD)/alu_tb
	cd $(BUILD) && COV_FILE=cov_alu.dat ./alu_tb

## ---- Muldiv unit test ---------------------------------------------------
$(BUILD)/muldiv_tb: $(ROOT)/tb/cpp/muldiv_tb.cpp $(ROOT)/tb/cpp/muldiv_golden.h \
                    $(RTL)/sigil_muldiv.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/muldiv --top-module sigil_muldiv \
	  -o $(abspath $(BUILD)/muldiv_tb) $(RTL)/sigil_muldiv.sv \
	  $(abspath $(ROOT)/tb/cpp/muldiv_tb.cpp)

muldiv: $(BUILD)/muldiv_tb
	cd $(BUILD) && COV_FILE=cov_muldiv.dat ./muldiv_tb

## ---- Multi-cycle muldiv unit test (COMB=0 and the COMB=1 legacy mode) ----
MULDIV_MC_SRC := $(RTL)/sigil_muldiv.sv $(RTL)/sigil_muldiv_mc.sv
MULDIV_MC_DEP := $(ROOT)/tb/cpp/muldiv_mc_tb.cpp $(ROOT)/tb/cpp/muldiv_golden.h $(MULDIV_MC_SRC)
$(BUILD)/muldiv_mc_tb: $(MULDIV_MC_DEP) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/muldiv_mc --top-module sigil_muldiv_mc \
	  -o $(abspath $(BUILD)/muldiv_mc_tb) $(MULDIV_MC_SRC) \
	  $(abspath $(ROOT)/tb/cpp/muldiv_mc_tb.cpp)

$(BUILD)/muldiv_mc_comb_tb: $(MULDIV_MC_DEP) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/muldiv_mc_comb --top-module sigil_muldiv_mc \
	  -GCOMB=1 -CFLAGS -DMDU_COMB \
	  -o $(abspath $(BUILD)/muldiv_mc_comb_tb) $(MULDIV_MC_SRC) \
	  $(abspath $(ROOT)/tb/cpp/muldiv_mc_tb.cpp)

muldiv_mc: $(BUILD)/muldiv_mc_tb $(BUILD)/muldiv_mc_comb_tb
	cd $(BUILD) && COV_FILE=cov_muldiv_mc.dat ./muldiv_mc_tb
	cd $(BUILD) && COV_FILE=cov_muldiv_mc_comb.dat ./muldiv_mc_comb_tb 100000

## ---- Decoder unit test -------------------------------------------------
$(BUILD)/decoder_tb: $(ROOT)/tb/cpp/decoder_tb.cpp $(PKG) $(RTL)/sigil_decoder.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/decoder --top-module sigil_decoder \
	  -o $(abspath $(BUILD)/decoder_tb) $(PKG) $(RTL)/sigil_decoder.sv \
	  $(abspath $(ROOT)/tb/cpp/decoder_tb.cpp)

decoder: $(BUILD)/decoder_tb
	cd $(BUILD) && COV_FILE=cov_decoder.dat ./decoder_tb

## ---- Register file unit test --------------------------------------------
$(BUILD)/regfile_tb: $(ROOT)/tb/cpp/regfile_tb.cpp $(RTL)/sigil_regfile.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/regfile --top-module sigil_regfile \
	  -o $(abspath $(BUILD)/regfile_tb) $(RTL)/sigil_regfile.sv \
	  $(abspath $(ROOT)/tb/cpp/regfile_tb.cpp)

regfile: $(BUILD)/regfile_tb
	cd $(BUILD) && COV_FILE=cov_regfile.dat ./regfile_tb

## ---- CSR / privileged unit test ------------------------------------------
$(BUILD)/csr_tb: $(ROOT)/tb/cpp/csr_tb.cpp $(RTL)/sigil_csr.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/csr --top-module sigil_csr \
	  -o $(abspath $(BUILD)/csr_tb) $(RTL)/sigil_csr.sv \
	  $(abspath $(ROOT)/tb/cpp/csr_tb.cpp)

csr: $(BUILD)/csr_tb
	cd $(BUILD) && COV_FILE=cov_csr.dat ./csr_tb

## ---- RTL PLIC unit test (claim arbitration vs a reference model) ----
$(BUILD)/plic_tb: $(ROOT)/tb/cpp/plic_tb.cpp $(ROOT)/rtl/soc/sigil_plic.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/plic --top-module sigil_plic \
	  -o $(abspath $(BUILD)/plic_tb) $(ROOT)/rtl/soc/sigil_plic.sv \
	  $(abspath $(ROOT)/tb/cpp/plic_tb.cpp)

plic: $(BUILD)/plic_tb
	cd $(BUILD) && COV_FILE=cov_plic.dat ./plic_tb

## ---- MMU unit test -------------------------------------------------------
$(BUILD)/mmu_tb: $(ROOT)/tb/cpp/mmu_tb.cpp $(RTL)/sigil_mmu.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/mmu --top-module sigil_mmu \
	  -o $(abspath $(BUILD)/mmu_tb) $(RTL)/sigil_mmu.sv \
	  $(abspath $(ROOT)/tb/cpp/mmu_tb.cpp)

mmu: $(BUILD)/mmu_tb
	cd $(BUILD) && COV_FILE=cov_mmu.dat ./mmu_tb

## ---- FPU unit test --------------------------------------------------------
SOFTFLOAT := $(ROOT)/third_party/berkeley-softfloat-3
SF_HOST   := $(ROOT)/build/softfloat-host
$(SF_HOST)/softfloat.a: softfloat-host/Makefile softfloat-host/platform.h
	mkdir -p $(SF_HOST)
	cp softfloat-host/Makefile softfloat-host/platform.h $(SF_HOST)/
	cd $(SF_HOST) && sed -i.bak 's|../../source|../../third_party/berkeley-softfloat-3/source|' Makefile && $(MAKE) -j8
$(BUILD)/fpu_tb: $(ROOT)/tb/cpp/fpu_tb.cpp $(FPU_INC) \
                 $(RTL)/sigil_fpu_pkg.sv $(RTL)/sigil_fpu.sv \
                 $(SF_HOST)/softfloat.a | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/fpu --top-module sigil_fpu \
	  -CFLAGS "-I$(abspath $(SOFTFLOAT))/source/include -I$(abspath $(SF_HOST))" \
	  -LDFLAGS "$(abspath $(SF_HOST))/softfloat.a" \
	  -o $(abspath $(BUILD)/fpu_tb) $(RTL)/sigil_fpu_pkg.sv \
	  $(RTL)/sigil_fpu.sv \
	  $(abspath $(ROOT)/tb/cpp/fpu_tb.cpp)

fpu: $(BUILD)/fpu_tb
	cd $(BUILD) && COV_FILE=cov_fpu.dat ./fpu_tb

# Same TB on the FPU_DS_BITS=1 configuration (one div/sqrt step
# per cycle: the shorter-critical-path alternative).
$(BUILD)/fpu_tb_ds1: $(ROOT)/tb/cpp/fpu_tb.cpp $(FPU_INC) \
                 $(RTL)/sigil_fpu_pkg.sv $(RTL)/sigil_fpu.sv \
                 $(SF_HOST)/softfloat.a | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/fpu_ds1 --top-module sigil_fpu \
	  +define+SIGIL_FPU_DS_BITS=1 -CFLAGS -DFPU_DS_BITS=1 \
	  -CFLAGS "-I$(abspath $(SOFTFLOAT))/source/include -I$(abspath $(SF_HOST))" \
	  -LDFLAGS "$(abspath $(SF_HOST))/softfloat.a" \
	  -o $(abspath $(BUILD)/fpu_tb_ds1) $(RTL)/sigil_fpu_pkg.sv \
	  $(RTL)/sigil_fpu.sv \
	  $(abspath $(ROOT)/tb/cpp/fpu_tb.cpp)

fpu-ds1: $(BUILD)/fpu_tb_ds1
	cd $(BUILD) && COV_FILE=cov_fpu_ds1.dat ./fpu_tb_ds1

## ---- B/crypto unit test ---------------------------------------------------
$(BUILD)/bext_tb: $(ROOT)/tb/cpp/bext_tb.cpp \
                  $(RTL)/sigil_bext_pkg.sv $(RTL)/sigil_bext.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/bext --top-module sigil_bext \
	  -o $(abspath $(BUILD)/bext_tb) $(RTL)/sigil_bext_pkg.sv \
	  $(RTL)/sigil_bext.sv \
            $(RTL)/sigil_rvc.sv \
	  $(abspath $(ROOT)/tb/cpp/bext_tb.cpp)

bext: $(BUILD)/bext_tb
	cd $(BUILD) && COV_FILE=cov_bext.dat ./bext_tb

## ---- RVC decompressor unit test --------------------------------------------
$(BUILD)/rvc_tb: $(ROOT)/tb/cpp/rvc_tb.cpp $(RTL)/sigil_rvc.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/rvc --top-module sigil_rvc \
	  -o $(abspath $(BUILD)/rvc_tb) $(RTL)/sigil_rvc.sv \
	  $(abspath $(ROOT)/tb/cpp/rvc_tb.cpp)

rvc: $(BUILD)/rvc_tb
	cd $(BUILD) && COV_FILE=cov_rvc.dat ./rvc_tb

## ---- Vector unit test ------------------------------------------------------
# Harness = sigil_vec + banked sigil_vregfile + TB backdoor.
$(BUILD)/vec_tb: $(ROOT)/tb/cpp/vec_tb.cpp $(PKG) $(RTL)/sigil_cache_pkg.sv $(FPU_INC) \
                 $(RTL)/sigil_vec_pkg.sv $(RTL)/sigil_fpu_pkg.sv \
                 $(RTL)/sigil_fpu.sv \
                 $(RTL)/sigil_vregfile.sv $(RTL)/sigil_vec.sv \
                 $(ROOT)/tb/sv/sigil_vec_harness.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/vec --top-module sigil_vec_harness \
	  -o $(abspath $(BUILD)/vec_tb) $(PKG) $(RTL)/sigil_cache_pkg.sv \
	  $(RTL)/sigil_vec_pkg.sv $(RTL)/sigil_fpu_pkg.sv \
	  $(RTL)/sigil_fpu.sv \
	  $(RTL)/sigil_vregfile.sv $(RTL)/sigil_vec.sv \
	  $(ROOT)/tb/sv/sigil_vec_harness.sv \
	  $(abspath $(ROOT)/tb/cpp/vec_tb.cpp)

vec: $(BUILD)/vec_tb
	cd $(BUILD) && COV_FILE=cov_vec.dat ./vec_tb

# Same harness with randomized initial state (--x-initial unique,
# +verilator+rand+reset+2): the simulation cross-checks must stay
# quiet until reset. Short runs; seeds 1, 2 and 4 each fired a
# cross-check at time 0 before the reset gating. No coverage.
$(BUILD)/vec_tb_xinit: $(ROOT)/tb/cpp/vec_tb.cpp $(PKG) $(RTL)/sigil_cache_pkg.sv $(FPU_INC) \
                 $(RTL)/sigil_vec_pkg.sv $(RTL)/sigil_fpu_pkg.sv \
                 $(RTL)/sigil_fpu.sv \
                 $(RTL)/sigil_vregfile.sv $(RTL)/sigil_vec.sv \
                 $(ROOT)/tb/sv/sigil_vec_harness.sv | $(BUILD) $(OBJ)
	$(VERILATOR) --cc --exe --build -j $(VJOBS) -Wall -Wno-DECLFILENAME --assert --coverage-line \
	  --x-initial unique -I$(RTL) -CFLAGS "-std=c++17 -O2" \
	  --Mdir $(OBJ)/vec_xinit --top-module sigil_vec_harness \
	  -o $(abspath $(BUILD)/vec_tb_xinit) $(PKG) $(RTL)/sigil_cache_pkg.sv \
	  $(RTL)/sigil_vec_pkg.sv $(RTL)/sigil_fpu_pkg.sv \
	  $(RTL)/sigil_fpu.sv \
	  $(RTL)/sigil_vregfile.sv $(RTL)/sigil_vec.sv \
	  $(ROOT)/tb/sv/sigil_vec_harness.sv \
	  $(abspath $(ROOT)/tb/cpp/vec_tb.cpp)

vec-xinit: $(BUILD)/vec_tb_xinit
	cd $(BUILD) && for s in 1 2 4; do \
	  ./vec_tb_xinit 20 +verilator+rand+reset+2 +verilator+seed+$$s > vec_xinit.log 2>&1 \
	    || { cat vec_xinit.log; exit 1; }; \
	  tail -1 vec_xinit.log | sed "s/^VEC TB PASS/VEC TB PASS [random initial state, seed $$s]/"; \
	done

## ---- L1 cache unit tests ----------------------------------------------
# Small geometry (4 sets x 2 ways x 32 B lines) so the random
# streams hit every miss/evict/write-back path constantly; two
# cacheable windows with I/O around them.
CACHE_TB_G := -GSETS=4 -GWAYS=2 -GLINE_BYTES=32 \
              "-GC0_BASE=64'h1000" "-GC0_SIZE=64'h2000" \
              "-GC1_BASE=64'h0080000000000000" "-GC1_SIZE=64'h0080000000000000"
$(BUILD)/dcache_tb: $(ROOT)/tb/cpp/dcache_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CACHE_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/dcache --top-module sigil_dcache $(CACHE_TB_G) \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/dcache_tb) $(CACHE_RTL) \
	  $(abspath $(ROOT)/tb/cpp/dcache_tb.cpp)

dcache: $(BUILD)/dcache_tb
	cd $(BUILD) && COV_FILE=cov_dcache.dat ./dcache_tb

$(BUILD)/icache_tb: $(ROOT)/tb/cpp/icache_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CACHE_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/icache --top-module sigil_icache $(CACHE_TB_G) \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/icache_tb) $(CACHE_RTL) \
	  $(abspath $(ROOT)/tb/cpp/icache_tb.cpp)

icache: $(BUILD)/icache_tb
	cd $(BUILD) && COV_FILE=cov_icache.dat ./icache_tb

## ---- Crypto accelerator KATs (issue #19) --------------------------------
$(BUILD)/sha256_tb: $(ROOT)/tb/cpp/sha256_tb.cpp $(CRYPTO)/sha256_block.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/sha256 --top-module sha256_block \
	  -o $(abspath $(BUILD)/sha256_tb) $(CRYPTO)/sha256_block.sv \
	  $(abspath $(ROOT)/tb/cpp/sha256_tb.cpp)

sha256: $(BUILD)/sha256_tb
	cd $(BUILD) && COV_FILE=cov_sha256.dat ./sha256_tb

$(BUILD)/sha512_tb: $(ROOT)/tb/cpp/sha512_tb.cpp $(CRYPTO)/sha512_block.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/sha512 --top-module sha512_block \
	  -o $(abspath $(BUILD)/sha512_tb) $(CRYPTO)/sha512_block.sv \
	  $(abspath $(ROOT)/tb/cpp/sha512_tb.cpp)

sha512: $(BUILD)/sha512_tb
	cd $(BUILD) && COV_FILE=cov_sha512.dat ./sha512_tb

$(BUILD)/keccak_tb: $(ROOT)/tb/cpp/keccak_tb.cpp $(CRYPTO)/keccak_f1600.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/keccak --top-module keccak_f1600 \
	  -o $(abspath $(BUILD)/keccak_tb) $(CRYPTO)/keccak_f1600.sv \
	  $(abspath $(ROOT)/tb/cpp/keccak_tb.cpp)

keccak: $(BUILD)/keccak_tb
	cd $(BUILD) && COV_FILE=cov_keccak.dat ./keccak_tb

$(BUILD)/ec_field_tb: $(ROOT)/tb/cpp/ec_field_tb.cpp $(CRYPTO)/ec_field.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/ecfield --top-module ec_field \
	  -o $(abspath $(BUILD)/ec_field_tb) $(CRYPTO)/ec_field.sv \
	  $(abspath $(ROOT)/tb/cpp/ec_field_tb.cpp)

ecfield: $(BUILD)/ec_field_tb
	cd $(BUILD) && COV_FILE=cov_ecfield.dat ./ec_field_tb

CRYPTO_TOP_RTL := $(CRYPTO)/sha256_block.sv $(CRYPTO)/sha512_block.sv \
                  $(CRYPTO)/keccak_f1600.sv $(CRYPTO)/sigil_hash_stream.sv \
                  $(CRYPTO)/ec_field.sv $(CRYPTO)/sigil_crypto_top.sv
$(BUILD)/crypto_top_tb: $(ROOT)/tb/cpp/crypto_top_tb.cpp \
                     $(CRYPTO_TOP_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/cryptotop --top-module sigil_crypto_top \
	  -o $(abspath $(BUILD)/crypto_top_tb) $(CRYPTO_TOP_RTL) \
	  $(abspath $(ROOT)/tb/cpp/crypto_top_tb.cpp)

cryptotop: $(BUILD)/crypto_top_tb
	cd $(BUILD) && COV_FILE=cov_cryptotop.dat ./crypto_top_tb

# Streaming SHA-512 / SHA3-256 / Keccak-256 / SHAKE256 through the
# AXI-Lite top (issue #6). Vectors are generated at build time from
# Python hashlib + the in-repo Keccak-256 sponge (sw/hash_kat.py).
$(BUILD)/hash_stream_kats.h: $(ROOT)/sw/hash_kat.py $(ROOT)/sw/golden.py | $(BUILD)
	python3 $(ROOT)/sw/hash_kat.py --header $@

$(BUILD)/hash_stream_tb: $(ROOT)/tb/cpp/hash_stream_tb.cpp \
                     $(BUILD)/hash_stream_kats.h \
                     $(CRYPTO_TOP_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/hashstream --top-module sigil_crypto_top \
	  -CFLAGS -I$(abspath $(BUILD)) \
	  -o $(abspath $(BUILD)/hash_stream_tb) $(CRYPTO_TOP_RTL) \
	  $(abspath $(ROOT)/tb/cpp/hash_stream_tb.cpp)

hashstream: $(BUILD)/hash_stream_tb
	cd $(BUILD) && COV_FILE=cov_hashstream.dat ./hash_stream_tb

crypto: sha256 sha512 keccak ecfield cryptotop hashstream

## ---- Core harness + directed software ---------------------------------
# core_tb cacheability: [0, 0x1000_0000) (directed tests at PA 0)
# plus the default DRAM window at 0x8000_0000 (ELF tests).
$(BUILD)/core_tb: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core --top-module sigil_cpu \
	  "-GC1_BASE=64'h0" "-GC1_SIZE=64'h10000000" \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/core_tb) $(CPU_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

## ---- SoC platform harness (Linux/OpenSBI boot, issue #21) --------------
# Default cacheability: DRAM 0x8000_0000.. only; ROM/CLINT/PLIC/UART are I/O.
$(BUILD)/soc_tb: $(ROOT)/tb/cpp/soc_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS_FAST) $(OBJ)/soc --top-module sigil_cpu \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/soc_tb) $(CPU_RTL) \
	  $(abspath $(ROOT)/tb/cpp/soc_tb.cpp)

$(ROOT)/build/linux/boot_stub.bin: $(ROOT)/sw/linux/boot_stub.S
	mkdir -p $(ROOT)/build/linux
	$(RISCV_GCC) -march=rv64imac -mabi=lp64 -nostdlib -Wl,-Ttext=0x1000 $< -o $(ROOT)/build/linux/boot_stub.elf
	$(RISCV_OBJCOPY) -O binary $(ROOT)/build/linux/boot_stub.elf $@

$(ROOT)/build/linux/s_hello.bin: $(ROOT)/sw/linux/s_hello.S
	mkdir -p $(ROOT)/build/linux
	$(RISCV_GCC) -march=rv64imac -mabi=lp64 -nostdlib -Wl,-Ttext=0x80200000 $< -o $(ROOT)/build/linux/s_hello.elf
	$(RISCV_OBJCOPY) -O binary $(ROOT)/build/linux/s_hello.elf $@

soc: $(BUILD)/soc_tb $(ROOT)/build/linux/boot_stub.bin $(ROOT)/build/linux/s_hello.bin

## ---- RTL SoC harness (synthesizable SoC, issue #4) ---------------------
SOCDIR    := $(ROOT)/rtl/soc
HASH_RTL  := $(CRYPTO)/sha512_block.sv $(CRYPTO)/keccak_f1600.sv \
             $(CRYPTO)/sigil_hash_stream.sv
SOC_RTL   := $(CPU_RTL) $(CRYPTO)/sha256_block.sv $(HASH_RTL) \
             $(CRYPTO)/ec_field.sv $(CRYPTO)/sigil_crypto_top.sv \
             $(SOCDIR)/sigil_clint.sv $(SOCDIR)/sigil_plic.sv \
             $(SOCDIR)/sigil_uart16550.sv \
             $(SOCDIR)/sigil_bootrom.sv \
             $(SOCDIR)/sigil_crypto_bridge.sv \
             $(SOCDIR)/sigil_soc_fabric.sv \
             $(SOCDIR)/sigil_soc_top.sv
# Absolute: recipes below cd into $(BUILD), where ROOT-relative paths break.
SOCFW     := $(abspath $(ROOT)/build/soc-tests)

# Long firmware runs: no coverage instrumentation (as soc_tb).
$(BUILD)/soc_rtl_tb: $(ROOT)/tb/cpp/soc_rtl_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(SOC_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS_FAST) $(OBJ)/socrtl --top-module sigil_soc_top \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/soc_rtl_tb) $(SOC_RTL) \
	  $(abspath $(ROOT)/tb/cpp/soc_rtl_tb.cpp)

SOCFW_DEPS := $(ROOT)/sw/soc-tests/crt.S $(ROOT)/sw/soc-tests/link.ld \
  $(ROOT)/sw/soc-tests/soc_crypto_drv.h $(ROOT)/sw/sigil_crypto.h

# crypto_soc_test: SHA-256 + secp256k1 ECDSA verify (+ tamper).
# ed25519_soc_test: Ed25519 verify of the RFC 8032 vectors (+ tamper),
# SHA-512 in software on the core. Both: field ops on the accelerator.
$(SOCFW)/%.bin: $(ROOT)/sw/soc-tests/%.c $(SOCFW_DEPS)
	mkdir -p $(SOCFW)
	$(RISCV_GCC) -march=rv64imafdc -mabi=lp64 -mcmodel=medany \
	  -nostdlib -ffreestanding -fno-builtin -O1 \
	  -T $(ROOT)/sw/soc-tests/link.ld \
	  $(ROOT)/sw/soc-tests/crt.S $< -o $(SOCFW)/$*.elf
	$(RISCV_OBJCOPY) -O binary $(SOCFW)/$*.elf $@

# Both firmware images on the RTL SoC. SOCRTL_ARGS=--no-cache runs
# them with the L1 caches off.
SOCRTL_ARGS ?=
SOC_CRYPTO_FW := crypto_soc_test ed25519_soc_test
socrtl: $(BUILD)/soc_rtl_tb $(addprefix $(SOCFW)/,$(addsuffix .bin,$(SOC_CRYPTO_FW)))
	cd $(BUILD) && for fw in $(SOC_CRYPTO_FW); do \
	  ./soc_rtl_tb 400000000 $(CORE_RAND_ARGS) $(SOCRTL_ARGS) \
	    --load 0x80000000=$(abspath $(SOCFW))/$$fw.bin \
	    --exit-string "SOC CRYPTO PASS" || exit 1; \
	done

# Streaming hash engine on the RTL SoC (issue #6); shares the
# soc-tests startup code and link script.
$(SOCFW)/hash_soc_test.bin: $(ROOT)/sw/hash-tests/hash_soc_test.c \
		$(ROOT)/sw/soc-tests/crt.S $(ROOT)/sw/soc-tests/link.ld \
		$(ROOT)/sw/sigil_crypto.h
	mkdir -p $(SOCFW)
	$(RISCV_GCC) -march=rv64imafdc -mabi=lp64 -mcmodel=medany \
	  -nostdlib -ffreestanding -fno-builtin -O1 \
	  -T $(ROOT)/sw/soc-tests/link.ld \
	  $(ROOT)/sw/soc-tests/crt.S $< -o $(SOCFW)/hash_soc_test.elf
	$(RISCV_OBJCOPY) -O binary $(SOCFW)/hash_soc_test.elf $@

sochash: $(BUILD)/soc_rtl_tb $(SOCFW)/hash_soc_test.bin
	cd $(BUILD) && ./soc_rtl_tb 50000000 $(CORE_RAND_ARGS) \
	  --load 0x80000000=$(abspath $(SOCFW))/hash_soc_test.bin \
	  --exit-string "SOC HASH PASS"

$(BUILD)/%.bin: $(ROOT)/sw/core-tests/%.S $(ROOT)/sw/core-tests/link.ld | $(BUILD)
	$(RISCV_GCC) $(SWFLAGS) $< -o $(BUILD)/$*.elf
	$(RISCV_OBJCOPY) -O binary $(BUILD)/$*.elf $@

# Every directed test runs twice: caches on with seeded random bus
# latency/gaps/backpressure, and caches off (all accesses uncached
# single beats, minimum latency).
core: $(BUILD)/core_tb $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS)))
	bash $(ROOT)/sim/run_directed.sh rand $(CORE_RAND_ARGS)
	bash $(ROOT)/sim/run_directed.sh nocache --no-cache

## ---- M unit in COMB=1 (legacy single-cycle) mode: whole directed suite --
# Proves the core still elaborates and runs with the combinational M
# unit behind the handshake (+define+SIGIL_MULDIV_COMB). No coverage
# is written (the main `core` run owns the cov_*.dat files).
MDCOMB_RUNS := rv64i_directed.bin rv64m_directed.bin md_directed.bin md_kill_directed.bin \
  amo_directed.bin fp_directed.bin fp_stall_directed.bin bext_directed.bin \
  rvc_directed.bin pipeline_directed.bin "priv_directed.bin 6000000 --irq-timer-after 2000" "irq_exc_race_directed.bin --irq-timer-after 40" \
  vm_directed.bin "trap_illegal.bin 100000 --expect-trap 2" \
  "trap_misalign.bin 100000 --expect-trap 4" "trap_ecall.bin 100000 --expect-trap 11" \
  "trap_ebreak.bin 100000 --expect-trap 3" "trap_store_misalign.bin 100000 --expect-trap 6" \
  "trap_younger_store.bin 100000 --expect-trap 4" trap_younger_csr.bin \
  irq_seip_rmw.bin irq_mip_rmw_variants.bin \
  counter_time_directed.bin hyp_directed.bin vec_directed.bin \
  fpvec_directed.bin "vec_trap_directed.bin --irq-timer-after 2000" \
  "trap_pa_fetch.bin 100000 --expect-trap 1" "trap_pa_load.bin 100000 --expect-trap 5"
$(BUILD)/core_tb_mdcomb: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core_mdcomb --top-module sigil_cpu \
	  +define+SIGIL_MULDIV_COMB \
	  "-GC1_BASE=64'h0" "-GC1_SIZE=64'h10000000" \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/core_tb_mdcomb) $(CPU_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

core-mdcomb: $(BUILD)/core_tb_mdcomb $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS)))
	cd $(BUILD) && for r in $(MDCOMB_RUNS); do \
	  ./core_tb_mdcomb $$r $(CORE_RAND_ARGS) > mdcomb.log 2>&1 || { cat mdcomb.log; exit 1; }; \
	  tail -1 mdcomb.log | sed 's/^CORE TB PASS/CORE TB PASS [M COMB=1]/'; \
	done
	cd $(BUILD) && for o in $$(seq 100 7 171); do \
	  ./core_tb_mdcomb md_irq_directed.bin --irq-timer-after $$o $(CORE_RAND_ARGS) > mdcomb.log 2>&1 \
	    || { cat mdcomb.log; exit 1; }; \
	done; echo "CORE TB PASS [M COMB=1] md_irq_directed.bin (11 IRQ offsets 100..170)"

## ---- Core with random initial state -----------------------------------
# --x-initial unique build: the whole directed suite (run_directed.sh,
# caches on, random bus latency) with +verilator+rand+reset+2 at two
# seeds. Every simulation check must stay quiet until reset, and the
# core and the test programs must not depend on initial register
# contents (e.g. a test using sp without setting it).
$(BUILD)/core_tb_xinit: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core_xinit --top-module sigil_cpu \
	  --x-initial unique \
	  "-GC1_BASE=64'h0" "-GC1_SIZE=64'h10000000" \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/core_tb_xinit) $(CPU_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

core-xinit: $(BUILD)/core_tb_xinit $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS)))
	for s in 1 3; do \
	  CORE_TB=./core_tb_xinit bash $(ROOT)/sim/run_directed.sh xinit$$s $(CORE_RAND_ARGS) \
	    +verilator+rand+reset+2 +verilator+seed+$$s || exit 1; \
	done

## ---- SRAM-macro builds (ORFS flows) ---------------------------------
# Under SIGIL_SRAM_FAKERAM45 (nangate45) / SIGIL_SRAM_SKY130
# (sky130hd) the VRF banks and the L1 data/tag ways instantiate SRAM
# macros. Rebuild the vector unit TB, the core TB (sigil_cpu with
# the real cache geometry) and the RTL SoC on each macro family's
# behavioural models (which, like the real macros, do not hold read
# data) and rerun the vector TB, every directed core test (random bus
# latency) and the SoC crypto firmware, so the wrappers (masks,
# selects, half select, read capture) are checked bit-exactly.
# The sky130 builds use the sky130 SoC configuration (registered SRAM
# outputs, SRAM_OREG, and the cache geometry in
# SIGIL_SOC_PARAMS_SKY130). The "oreg" family is the default
# behavioural arrays and cache geometry with SIGIL_SRAM_OREG: the
# two-cycle read pipelines with multi-way caches; srammacro also
# reruns the small-geometry I$/D$ unit tests with that latency.
include $(ROOT)/rtl/sigil_soc_files.mk
SRAM_DEF_fakeram45 := +define+SIGIL_SRAM_FAKERAM45
SRAM_DEF_sky130    := +define+SIGIL_SRAM_SKY130
SRAM_DEF_oreg      := +define+SIGIL_SRAM_OREG
# Cache geometry overrides (sigil_cpu / sigil_soc_top parameters).
SRAM_GEO_sky130    := $(addprefix -G,$(SIGIL_SOC_PARAMS_SKY130))
SRAM_MOD_fakeram45 := $(addprefix $(ROOT)/flow/designs/nangate45/sigil_soc/sram/,\
  fakeram45_256x64_1r1w.v fakeram45_512x64.v fakeram45_64x44.v)
SRAM_MOD_sky130 := $(addprefix $(ROOT)/flow/designs/sky130hd/sigil_soc/sram/,\
  sky130_sram_1rw1r_64x256_8.v sky130_sram_1rw1r_128x256_8.v sky130_sram_1rw1r_44x64_8.v)
SRAM_MOD_oreg :=
SRAM_MACROS := fakeram45 sky130 oreg
.SECONDEXPANSION:
$(BUILD)/vec_tb_%: $(ROOT)/tb/cpp/vec_tb.cpp $(PKG) $(RTL)/sigil_cache_pkg.sv $(FPU_INC) $(RTL)/sigil_vec_pkg.sv \
                 $(RTL)/sigil_fpu_pkg.sv $(RTL)/sigil_fpu.sv \
                 $(RTL)/sigil_vregfile.sv $(RTL)/sigil_vec.sv \
                 $(ROOT)/tb/sv/sigil_vec_harness.sv $$(SRAM_MOD_$$*) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/vec_$* --top-module sigil_vec_harness \
	  $(SRAM_DEF_$*) $(SRAM_MOD_$*) -o $(abspath $@) $(PKG) $(RTL)/sigil_cache_pkg.sv \
	  $(RTL)/sigil_vec_pkg.sv $(RTL)/sigil_fpu_pkg.sv \
	  $(RTL)/sigil_fpu.sv \
	  $(RTL)/sigil_vregfile.sv $(RTL)/sigil_vec.sv \
	  $(ROOT)/tb/sv/sigil_vec_harness.sv \
	  $(abspath $(ROOT)/tb/cpp/vec_tb.cpp)

$(BUILD)/core_tb_%: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) \
                  $$(SRAM_MOD_$$*) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core_$* --top-module sigil_cpu \
	  $(SRAM_DEF_$*) $(SRAM_GEO_$*) $(SRAM_MOD_$*) \
	  "-GC1_BASE=64'h0" "-GC1_SIZE=64'h10000000" \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $@) $(CPU_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

$(BUILD)/soc_rtl_tb_%: $(ROOT)/tb/cpp/soc_rtl_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(SOC_RTL) $(FPU_INC) \
                     $$(SRAM_MOD_$$*) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS_FAST) $(OBJ)/socrtl_$* --top-module sigil_soc_top \
	  $(SRAM_DEF_$*) $(SRAM_GEO_$*) $(SRAM_MOD_$*) \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $@) $(SOC_RTL) \
	  $(abspath $(ROOT)/tb/cpp/soc_rtl_tb.cpp)

# All directed-test binaries (used by vendor_model_check.sh).
directed-bins: $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS)))

# I$/D$ unit tests (small geometry) with two-cycle array reads.
$(BUILD)/%cache_tb_oreg: $(ROOT)/tb/cpp/%cache_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CACHE_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/$*cache_oreg --top-module sigil_$*cache $(CACHE_TB_G) \
	  $(SRAM_DEF_oreg) -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $@) $(CACHE_RTL) \
	  $(abspath $(ROOT)/tb/cpp/$*cache_tb.cpp)

srammacro: $(addprefix $(BUILD)/vec_tb_,$(SRAM_MACROS)) $(addprefix $(BUILD)/core_tb_,$(SRAM_MACROS)) \
           $(addprefix $(BUILD)/soc_rtl_tb_,$(SRAM_MACROS)) \
           $(BUILD)/dcache_tb_oreg $(BUILD)/icache_tb_oreg \
           $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS))) $(SOCFW)/crypto_soc_test.bin
	cd $(BUILD) && for c in dcache icache; do \
	  COV_FILE=nocov_$${c}_oreg.dat ./$${c}_tb_oreg > srammacro.log 2>&1 || { cat srammacro.log; exit 1; }; \
	  tail -1 srammacro.log | sed "s/$$/ [SRAM_OREG]/"; \
	done; \
	for m in $(SRAM_MACROS); do \
	  ./vec_tb_$$m > srammacro.log 2>&1 || { cat srammacro.log; exit 1; }; \
	  tail -1 srammacro.log | sed "s/$$/ [SRAM macro $$m]/"; \
	  CORE_TB=./core_tb_$$m COV_PREFIX=nocov bash $(abspath $(ROOT))/sim/run_directed.sh $$m $(CORE_RAND_ARGS) \
	    > srammacro_core_$$m.log 2>&1 || { tail -40 srammacro_core_$$m.log; exit 1; }; \
	  echo "CORE TB PASS: $$(grep -c 'CORE TB PASS' srammacro_core_$$m.log) directed runs, 0 FAIL [SRAM macro $$m]"; \
	  ./soc_rtl_tb_$$m 400000000 $(CORE_RAND_ARGS) \
	    --load 0x80000000=$(abspath $(SOCFW))/crypto_soc_test.bin \
	    --exit-string "SOC CRYPTO PASS" > srammacro.log 2>&1 || { tail -20 srammacro.log; exit 1; }; \
	  tail -1 srammacro.log | sed "s/$$/ [SRAM macro $$m]/"; \
	done

## ---- FPU_DS_BITS=1 core build: FP directed suites ---------------------
$(BUILD)/core_tb_ds1: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core_ds1 --top-module sigil_cpu \
	  +define+SIGIL_FPU_DS_BITS=1 \
	  "-GC1_BASE=64'h0" "-GC1_SIZE=64'h10000000" \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/core_tb_ds1) $(CPU_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

core-ds1: $(BUILD)/core_tb_ds1 $(BUILD)/fp_directed.bin $(BUILD)/fp_stall_directed.bin $(BUILD)/fp_irq_directed.bin $(BUILD)/fpvec_directed.bin
	cd $(BUILD) && ./core_tb_ds1 fp_directed.bin $(CORE_RAND_ARGS)
	cd $(BUILD) && ./core_tb_ds1 fp_stall_directed.bin $(CORE_RAND_ARGS)
	cd $(BUILD) && ./core_tb_ds1 fpvec_directed.bin $(CORE_RAND_ARGS)
	cd $(BUILD) && for o in $$(seq 100 3 172); do \
	  ./core_tb_ds1 fp_irq_directed.bin --irq-timer-after $$o $(CORE_RAND_ARGS) \
	    > fp_irq_ds1_$$o.log 2>&1 || { cat fp_irq_ds1_$$o.log; exit 1; }; \
	done; echo "CORE TB PASS fp_irq_directed.bin on FPU_DS_BITS=1 (25 IRQ offsets 100..172)"

## ---- Coverage ----------------------------------------------------------
# Annotate from this directory: the .dat files record source paths
# relative to sim/, where verilator was invoked.
# Every cov_*.dat written by this build's runs (globbed at recipe
# time; the merged output is excluded so it never feeds back).
coverage:
	@rm -f $(BUILD)/cov_merged.dat
	@verilator_coverage --write $(BUILD)/cov_merged.dat $$(ls $(BUILD)/cov_*.dat | grep -v cov_merged)
	@verilator_coverage --annotate $(BUILD)/coverage $(BUILD)/cov_merged.dat | tail -5

clean:
	rm -rf $(BUILD)
