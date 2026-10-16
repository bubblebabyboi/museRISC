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
VFLAGS    := --cc --exe --build -j 0 -Wall -Wno-DECLFILENAME \
             --coverage-line --coverage-toggle --assert -I$(RTL) \
             -CFLAGS "-std=c++17 -O2" --Mdir
# The platform harness writes no coverage; build it without the
# (expensive) coverage instrumentation for long OS boots.
VFLAGS_FAST := --cc --exe --build -j 0 -Wall -Wno-DECLFILENAME --assert -O3 -I$(RTL) \
               -CFLAGS "-std=c++17 -O2" --Mdir
PKG       := $(RTL)/muserisc_pkg.sv
# `included by muserisc_fpu_pkg.sv and muserisc_fpu.sv (dependency only)
FPU_INC   := $(RTL)/muserisc_fpu_ops.svh
# Harness bus timing for the randomized-latency runs (core_tb).
CORE_RAND_ARGS := --mem-lat 1:6 --mem-gap 2 --mem-ready 70

RISCV_PREFIX ?= $(shell command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 \
                  && echo riscv64-unknown-elf- || echo riscv64-elf-)
RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
SWFLAGS       := -march=rv64imafdc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh_zicsr_zifencei -mabi=lp64 -nostdlib -T $(ROOT)/sw/core-tests/link.ld

CORE_RTL := $(PKG) $(RTL)/muserisc_regfile.sv \
            $(RTL)/muserisc_fpregfile.sv $(RTL)/muserisc_alu.sv \
            $(RTL)/muserisc_muldiv.sv \
            $(RTL)/muserisc_muldiv_mc.sv \
            $(RTL)/muserisc_fpu_pkg.sv $(RTL)/muserisc_fpu.sv \
            $(RTL)/muserisc_bext_pkg.sv $(RTL)/muserisc_bext.sv \
            $(RTL)/muserisc_vregfile.sv \
            $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_vec.sv \
            $(RTL)/muserisc_rvc.sv \
            $(RTL)/muserisc_decoder.sv \
            $(RTL)/muserisc_csr.sv $(RTL)/muserisc_mmu.sv \
            $(RTL)/muserisc_cache_pkg.sv $(RTL)/muserisc_core.sv
# L1 caches + CPU wrapper (muserisc_cpu is the harness top).
CACHE_RTL := $(RTL)/muserisc_cache_pkg.sv $(RTL)/muserisc_sram_sp.sv \
             $(RTL)/muserisc_icache.sv $(RTL)/muserisc_dcache.sv \
             $(RTL)/muserisc_bus_arb.sv
CPU_RTL  := $(CORE_RTL) $(filter-out $(RTL)/muserisc_cache_pkg.sv,$(CACHE_RTL)) \
            $(RTL)/muserisc_cpu.sv
TESTS    := rv64i_directed rv64m_directed md_directed md_irq_directed md_kill_directed irq_exc_race_directed amo_directed fp_directed fp_stall_directed fp_irq_directed bext_directed rvc_directed pipeline_directed priv_directed counter_time_directed hyp_directed vec_directed fpvec_directed vec_trap_directed \
            vm_directed \
            trap_illegal trap_misalign trap_ecall trap_ebreak \
            trap_store_misalign trap_younger_store trap_younger_csr \
            trap_pa_fetch trap_pa_load \
            smc_fencei_directed amo_cache_directed mmio_bypass_directed \
            vm_sfence_cache_directed fp_hold_cache_directed ptw_drop_directed

.PHONY: all alu muldiv muldiv_mc decoder regfile csr mmu fpu fpu-ds1 bext rvc vec vec-xinit icache dcache core core-ds1 sw coverage clean riscv-tests \
        crypto sha256 sha512 keccak ecfield cryptotop core-mdcomb
all: alu muldiv muldiv_mc decoder regfile csr mmu fpu fpu-ds1 bext rvc vec vec-xinit icache dcache core core-ds1 core-mdcomb coverage

## ---- Stage gate: upstream riscv-tests (not part of `all`) -------------
# Caches on, seeded random bus latency/gaps/backpressure.
riscv-tests: $(BUILD)/core_tb
	CORE_TB_ARGS="$(CORE_RAND_ARGS)" bash $(ROOT)/sim/run_riscv_tests.sh

$(BUILD) $(OBJ):
	mkdir -p $@

## ---- ALU unit test ----------------------------------------------------
$(BUILD)/alu_tb: $(ROOT)/tb/cpp/alu_tb.cpp $(PKG) $(RTL)/muserisc_alu.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/alu --top-module muserisc_alu \
	  -o $(abspath $(BUILD)/alu_tb) $(PKG) $(RTL)/muserisc_alu.sv \
	  $(abspath $(ROOT)/tb/cpp/alu_tb.cpp)

alu: $(BUILD)/alu_tb
	cd $(BUILD) && COV_FILE=cov_alu.dat ./alu_tb

## ---- Muldiv unit test ---------------------------------------------------
$(BUILD)/muldiv_tb: $(ROOT)/tb/cpp/muldiv_tb.cpp $(ROOT)/tb/cpp/muldiv_golden.h \
                    $(RTL)/muserisc_muldiv.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/muldiv --top-module muserisc_muldiv \
	  -o $(abspath $(BUILD)/muldiv_tb) $(RTL)/muserisc_muldiv.sv \
	  $(abspath $(ROOT)/tb/cpp/muldiv_tb.cpp)

muldiv: $(BUILD)/muldiv_tb
	cd $(BUILD) && COV_FILE=cov_muldiv.dat ./muldiv_tb

## ---- Multi-cycle muldiv unit test (COMB=0 and the COMB=1 legacy mode) ----
MULDIV_MC_SRC := $(RTL)/muserisc_muldiv.sv $(RTL)/muserisc_muldiv_mc.sv
MULDIV_MC_DEP := $(ROOT)/tb/cpp/muldiv_mc_tb.cpp $(ROOT)/tb/cpp/muldiv_golden.h $(MULDIV_MC_SRC)
$(BUILD)/muldiv_mc_tb: $(MULDIV_MC_DEP) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/muldiv_mc --top-module muserisc_muldiv_mc \
	  -o $(abspath $(BUILD)/muldiv_mc_tb) $(MULDIV_MC_SRC) \
	  $(abspath $(ROOT)/tb/cpp/muldiv_mc_tb.cpp)

$(BUILD)/muldiv_mc_comb_tb: $(MULDIV_MC_DEP) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/muldiv_mc_comb --top-module muserisc_muldiv_mc \
	  -GCOMB=1 -CFLAGS -DMDU_COMB \
	  -o $(abspath $(BUILD)/muldiv_mc_comb_tb) $(MULDIV_MC_SRC) \
	  $(abspath $(ROOT)/tb/cpp/muldiv_mc_tb.cpp)

muldiv_mc: $(BUILD)/muldiv_mc_tb $(BUILD)/muldiv_mc_comb_tb
	cd $(BUILD) && COV_FILE=cov_muldiv_mc.dat ./muldiv_mc_tb
	cd $(BUILD) && COV_FILE=cov_muldiv_mc_comb.dat ./muldiv_mc_comb_tb 100000

## ---- Decoder unit test -------------------------------------------------
$(BUILD)/decoder_tb: $(ROOT)/tb/cpp/decoder_tb.cpp $(PKG) $(RTL)/muserisc_decoder.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/decoder --top-module muserisc_decoder \
	  -o $(abspath $(BUILD)/decoder_tb) $(PKG) $(RTL)/muserisc_decoder.sv \
	  $(abspath $(ROOT)/tb/cpp/decoder_tb.cpp)

decoder: $(BUILD)/decoder_tb
	cd $(BUILD) && COV_FILE=cov_decoder.dat ./decoder_tb

## ---- Register file unit test --------------------------------------------
$(BUILD)/regfile_tb: $(ROOT)/tb/cpp/regfile_tb.cpp $(RTL)/muserisc_regfile.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/regfile --top-module muserisc_regfile \
	  -o $(abspath $(BUILD)/regfile_tb) $(RTL)/muserisc_regfile.sv \
	  $(abspath $(ROOT)/tb/cpp/regfile_tb.cpp)

regfile: $(BUILD)/regfile_tb
	cd $(BUILD) && COV_FILE=cov_regfile.dat ./regfile_tb

## ---- CSR / privileged unit test ------------------------------------------
$(BUILD)/csr_tb: $(ROOT)/tb/cpp/csr_tb.cpp $(RTL)/muserisc_csr.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/csr --top-module muserisc_csr \
	  -o $(abspath $(BUILD)/csr_tb) $(RTL)/muserisc_csr.sv \
	  $(abspath $(ROOT)/tb/cpp/csr_tb.cpp)

csr: $(BUILD)/csr_tb
	cd $(BUILD) && COV_FILE=cov_csr.dat ./csr_tb

## ---- MMU unit test -------------------------------------------------------
$(BUILD)/mmu_tb: $(ROOT)/tb/cpp/mmu_tb.cpp $(RTL)/muserisc_mmu.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/mmu --top-module muserisc_mmu \
	  -o $(abspath $(BUILD)/mmu_tb) $(RTL)/muserisc_mmu.sv \
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
                 $(RTL)/muserisc_fpu_pkg.sv $(RTL)/muserisc_fpu.sv \
                 $(SF_HOST)/softfloat.a | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/fpu --top-module muserisc_fpu \
	  -CFLAGS "-I$(abspath $(SOFTFLOAT))/source/include -I$(abspath $(SF_HOST))" \
	  -LDFLAGS "$(abspath $(SF_HOST))/softfloat.a" \
	  -o $(abspath $(BUILD)/fpu_tb) $(RTL)/muserisc_fpu_pkg.sv \
	  $(RTL)/muserisc_fpu.sv \
	  $(abspath $(ROOT)/tb/cpp/fpu_tb.cpp)

fpu: $(BUILD)/fpu_tb
	cd $(BUILD) && COV_FILE=cov_fpu.dat ./fpu_tb

# Same TB on the FPU_DS_BITS=1 configuration (one div/sqrt step
# per cycle: the shorter-critical-path alternative).
$(BUILD)/fpu_tb_ds1: $(ROOT)/tb/cpp/fpu_tb.cpp $(FPU_INC) \
                 $(RTL)/muserisc_fpu_pkg.sv $(RTL)/muserisc_fpu.sv \
                 $(SF_HOST)/softfloat.a | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/fpu_ds1 --top-module muserisc_fpu \
	  +define+MUSERISC_FPU_DS_BITS=1 -CFLAGS -DFPU_DS_BITS=1 \
	  -CFLAGS "-I$(abspath $(SOFTFLOAT))/source/include -I$(abspath $(SF_HOST))" \
	  -LDFLAGS "$(abspath $(SF_HOST))/softfloat.a" \
	  -o $(abspath $(BUILD)/fpu_tb_ds1) $(RTL)/muserisc_fpu_pkg.sv \
	  $(RTL)/muserisc_fpu.sv \
	  $(abspath $(ROOT)/tb/cpp/fpu_tb.cpp)

fpu-ds1: $(BUILD)/fpu_tb_ds1
	cd $(BUILD) && COV_FILE=cov_fpu_ds1.dat ./fpu_tb_ds1

## ---- B/crypto unit test ---------------------------------------------------
$(BUILD)/bext_tb: $(ROOT)/tb/cpp/bext_tb.cpp \
                  $(RTL)/muserisc_bext_pkg.sv $(RTL)/muserisc_bext.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/bext --top-module muserisc_bext \
	  -o $(abspath $(BUILD)/bext_tb) $(RTL)/muserisc_bext_pkg.sv \
	  $(RTL)/muserisc_bext.sv \
            $(RTL)/muserisc_rvc.sv \
	  $(abspath $(ROOT)/tb/cpp/bext_tb.cpp)

bext: $(BUILD)/bext_tb
	cd $(BUILD) && COV_FILE=cov_bext.dat ./bext_tb

## ---- RVC decompressor unit test --------------------------------------------
$(BUILD)/rvc_tb: $(ROOT)/tb/cpp/rvc_tb.cpp $(RTL)/muserisc_rvc.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/rvc --top-module muserisc_rvc \
	  -o $(abspath $(BUILD)/rvc_tb) $(RTL)/muserisc_rvc.sv \
	  $(abspath $(ROOT)/tb/cpp/rvc_tb.cpp)

rvc: $(BUILD)/rvc_tb
	cd $(BUILD) && COV_FILE=cov_rvc.dat ./rvc_tb

## ---- Vector unit test ------------------------------------------------------
# Harness = muserisc_vec + banked muserisc_vregfile + TB backdoor.
$(BUILD)/vec_tb: $(ROOT)/tb/cpp/vec_tb.cpp $(PKG) $(FPU_INC) \
                 $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_fpu_pkg.sv \
                 $(RTL)/muserisc_fpu.sv \
                 $(RTL)/muserisc_vregfile.sv $(RTL)/muserisc_vec.sv \
                 $(ROOT)/tb/sv/muserisc_vec_harness.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/vec --top-module muserisc_vec_harness \
	  -o $(abspath $(BUILD)/vec_tb) $(PKG) \
	  $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_fpu_pkg.sv \
	  $(RTL)/muserisc_fpu.sv \
	  $(RTL)/muserisc_vregfile.sv $(RTL)/muserisc_vec.sv \
	  $(ROOT)/tb/sv/muserisc_vec_harness.sv \
	  $(abspath $(ROOT)/tb/cpp/vec_tb.cpp)

vec: $(BUILD)/vec_tb
	cd $(BUILD) && COV_FILE=cov_vec.dat ./vec_tb

# Same harness with randomized initial state (--x-initial unique,
# +verilator+rand+reset+2): the simulation cross-checks must stay
# quiet until reset. Short runs; seeds 1, 2 and 4 each fired a
# cross-check at time 0 before the reset gating. No coverage.
$(BUILD)/vec_tb_xinit: $(ROOT)/tb/cpp/vec_tb.cpp $(PKG) $(FPU_INC) \
                 $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_fpu_pkg.sv \
                 $(RTL)/muserisc_fpu.sv \
                 $(RTL)/muserisc_vregfile.sv $(RTL)/muserisc_vec.sv \
                 $(ROOT)/tb/sv/muserisc_vec_harness.sv | $(BUILD) $(OBJ)
	$(VERILATOR) --cc --exe --build -j 0 -Wall -Wno-DECLFILENAME --assert --coverage-line \
	  --x-initial unique -I$(RTL) -CFLAGS "-std=c++17 -O2" \
	  --Mdir $(OBJ)/vec_xinit --top-module muserisc_vec_harness \
	  -o $(abspath $(BUILD)/vec_tb_xinit) $(PKG) \
	  $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_fpu_pkg.sv \
	  $(RTL)/muserisc_fpu.sv \
	  $(RTL)/muserisc_vregfile.sv $(RTL)/muserisc_vec.sv \
	  $(ROOT)/tb/sv/muserisc_vec_harness.sv \
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
	$(VERILATOR) $(VFLAGS) $(OBJ)/dcache --top-module muserisc_dcache $(CACHE_TB_G) \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/dcache_tb) $(CACHE_RTL) \
	  $(abspath $(ROOT)/tb/cpp/dcache_tb.cpp)

dcache: $(BUILD)/dcache_tb
	cd $(BUILD) && COV_FILE=cov_dcache.dat ./dcache_tb

$(BUILD)/icache_tb: $(ROOT)/tb/cpp/icache_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CACHE_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/icache --top-module muserisc_icache $(CACHE_TB_G) \
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

$(BUILD)/crypto_top_tb: $(ROOT)/tb/cpp/crypto_top_tb.cpp \
                     $(CRYPTO)/sha256_block.sv $(CRYPTO)/ec_field.sv \
                     $(CRYPTO)/muse_crypto_top.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/cryptotop --top-module muse_crypto_top \
	  -o $(abspath $(BUILD)/crypto_top_tb) \
	  $(CRYPTO)/sha256_block.sv $(CRYPTO)/ec_field.sv \
	  $(CRYPTO)/muse_crypto_top.sv \
	  $(abspath $(ROOT)/tb/cpp/crypto_top_tb.cpp)

cryptotop: $(BUILD)/crypto_top_tb
	cd $(BUILD) && COV_FILE=cov_cryptotop.dat ./crypto_top_tb

crypto: sha256 sha512 keccak ecfield cryptotop

## ---- Core harness + directed software ---------------------------------
# core_tb cacheability: [0, 0x1000_0000) (directed tests at PA 0)
# plus the default DRAM window at 0x8000_0000 (ELF tests).
$(BUILD)/core_tb: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core --top-module muserisc_cpu \
	  "-GC1_BASE=64'h0" "-GC1_SIZE=64'h10000000" \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/core_tb) $(CPU_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

## ---- SoC platform harness (Linux/OpenSBI boot, issue #21) --------------
# Default cacheability: DRAM 0x8000_0000.. only; ROM/CLINT/PLIC/UART are I/O.
$(BUILD)/soc_tb: $(ROOT)/tb/cpp/soc_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS_FAST) $(OBJ)/soc --top-module muserisc_cpu \
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
SOC_RTL   := $(CPU_RTL) $(CRYPTO)/sha256_block.sv \
             $(CRYPTO)/ec_field.sv $(CRYPTO)/muse_crypto_top.sv \
             $(SOCDIR)/muserisc_clint.sv $(SOCDIR)/muserisc_plic.sv \
             $(SOCDIR)/muserisc_uart16550.sv \
             $(SOCDIR)/muserisc_bootrom.sv \
             $(SOCDIR)/muserisc_crypto_bridge.sv \
             $(SOCDIR)/muserisc_soc_fabric.sv \
             $(SOCDIR)/muserisc_soc_top.sv
SOCFW     := $(ROOT)/build/soc-tests

# Long firmware runs: no coverage instrumentation (as soc_tb).
$(BUILD)/soc_rtl_tb: $(ROOT)/tb/cpp/soc_rtl_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(SOC_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS_FAST) $(OBJ)/socrtl --top-module muserisc_soc_top \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $(BUILD)/soc_rtl_tb) $(SOC_RTL) \
	  $(abspath $(ROOT)/tb/cpp/soc_rtl_tb.cpp)

$(SOCFW)/crypto_soc_test.bin: $(ROOT)/sw/soc-tests/crypto_soc_test.c \
		$(ROOT)/sw/soc-tests/crt.S $(ROOT)/sw/soc-tests/link.ld \
		$(ROOT)/sw/muse_crypto.h
	mkdir -p $(SOCFW)
	$(RISCV_GCC) -march=rv64imafdc -mabi=lp64 -mcmodel=medany \
	  -nostdlib -ffreestanding -fno-builtin -O1 \
	  -T $(ROOT)/sw/soc-tests/link.ld \
	  $(ROOT)/sw/soc-tests/crt.S $< -o $(SOCFW)/crypto_soc_test.elf
	$(RISCV_OBJCOPY) -O binary $(SOCFW)/crypto_soc_test.elf $@

socrtl: $(BUILD)/soc_rtl_tb $(SOCFW)/crypto_soc_test.bin
	cd $(BUILD) && ./soc_rtl_tb 400000000 $(CORE_RAND_ARGS) \
	  --load 0x80000000=$(abspath $(SOCFW))/crypto_soc_test.bin \
	  --exit-string "SOC CRYPTO PASS"

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
# unit behind the handshake (+define+MUSERISC_MULDIV_COMB). No coverage
# is written (the main `core` run owns the cov_*.dat files).
MDCOMB_RUNS := rv64i_directed.bin rv64m_directed.bin md_directed.bin md_kill_directed.bin \
  amo_directed.bin fp_directed.bin fp_stall_directed.bin bext_directed.bin \
  rvc_directed.bin pipeline_directed.bin "priv_directed.bin 6000000 --irq-timer-after 2000" "irq_exc_race_directed.bin --irq-timer-after 40" \
  vm_directed.bin "trap_illegal.bin 100000 --expect-trap 2" \
  "trap_misalign.bin 100000 --expect-trap 4" "trap_ecall.bin 100000 --expect-trap 11" \
  "trap_ebreak.bin 100000 --expect-trap 3" "trap_store_misalign.bin 100000 --expect-trap 6" \
  "trap_younger_store.bin 100000 --expect-trap 4" trap_younger_csr.bin \
  counter_time_directed.bin hyp_directed.bin vec_directed.bin \
  fpvec_directed.bin "vec_trap_directed.bin --irq-timer-after 2000" \
  "trap_pa_fetch.bin 100000 --expect-trap 1" "trap_pa_load.bin 100000 --expect-trap 5"
$(BUILD)/core_tb_mdcomb: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core_mdcomb --top-module muserisc_cpu \
	  +define+MUSERISC_MULDIV_COMB \
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

## ---- FPU_DS_BITS=1 core build: FP directed suites ---------------------
$(BUILD)/core_tb_ds1: $(ROOT)/tb/cpp/core_tb.cpp $(ROOT)/tb/cpp/mbus_model.h $(CPU_RTL) $(FPU_INC) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core_ds1 --top-module muserisc_cpu \
	  +define+MUSERISC_FPU_DS_BITS=1 \
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
