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
             --coverage-line --coverage-toggle --assert \
             -CFLAGS "-std=c++17 -O2" --Mdir
PKG       := $(RTL)/muserisc_pkg.sv

RISCV_PREFIX ?= $(shell command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 \
                  && echo riscv64-unknown-elf- || echo riscv64-elf-)
RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
SWFLAGS       := -march=rv64imafdc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh_zicsr_zifencei -mabi=lp64 -nostdlib -T $(ROOT)/sw/core-tests/link.ld

CORE_RTL := $(PKG) $(RTL)/muserisc_regfile.sv \
            $(RTL)/muserisc_fpregfile.sv $(RTL)/muserisc_alu.sv \
            $(RTL)/muserisc_muldiv.sv \
            $(RTL)/muserisc_fpu_pkg.sv $(RTL)/muserisc_fpu.sv \
            $(RTL)/muserisc_bext_pkg.sv $(RTL)/muserisc_bext.sv \
            $(RTL)/muserisc_vregfile.sv \
            $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_vec.sv \
            $(RTL)/muserisc_rvc.sv \
            $(RTL)/muserisc_decoder.sv \
            $(RTL)/muserisc_csr.sv $(RTL)/muserisc_mmu.sv \
            $(RTL)/muserisc_core.sv
TESTS    := rv64i_directed rv64m_directed irq_exc_race_directed amo_directed fp_directed bext_directed rvc_directed pipeline_directed priv_directed counter_time_directed hyp_directed vec_directed fpvec_directed \
            vm_directed \
            trap_illegal trap_misalign trap_ecall trap_ebreak \
            trap_store_misalign trap_younger_store trap_younger_csr \
            trap_pa_fetch trap_pa_load

.PHONY: all alu muldiv decoder regfile csr mmu fpu bext rvc vec core sw coverage clean riscv-tests \
        crypto sha256 sha512 keccak ecfield cryptotop
all: alu muldiv decoder regfile csr mmu fpu bext rvc vec core coverage

## ---- Stage gate: upstream riscv-tests (not part of `all`) -------------
riscv-tests: $(BUILD)/core_tb
	bash $(ROOT)/sim/run_riscv_tests.sh

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
$(BUILD)/muldiv_tb: $(ROOT)/tb/cpp/muldiv_tb.cpp $(RTL)/muserisc_muldiv.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/muldiv --top-module muserisc_muldiv \
	  -o $(abspath $(BUILD)/muldiv_tb) $(RTL)/muserisc_muldiv.sv \
	  $(abspath $(ROOT)/tb/cpp/muldiv_tb.cpp)

muldiv: $(BUILD)/muldiv_tb
	cd $(BUILD) && COV_FILE=cov_muldiv.dat ./muldiv_tb

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
$(BUILD)/fpu_tb: $(ROOT)/tb/cpp/fpu_tb.cpp \
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
$(BUILD)/vec_tb: $(ROOT)/tb/cpp/vec_tb.cpp $(PKG) \
                 $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_fpu_pkg.sv \
                 $(RTL)/muserisc_vec.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/vec --top-module muserisc_vec \
	  -o $(abspath $(BUILD)/vec_tb) $(PKG) \
	  $(RTL)/muserisc_vec_pkg.sv $(RTL)/muserisc_fpu_pkg.sv \
	  $(RTL)/muserisc_vec.sv \
	  $(abspath $(ROOT)/tb/cpp/vec_tb.cpp)

vec: $(BUILD)/vec_tb
	cd $(BUILD) && COV_FILE=cov_vec.dat ./vec_tb

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
$(BUILD)/core_tb: $(ROOT)/tb/cpp/core_tb.cpp $(CORE_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core --top-module muserisc_core \
	  -o $(abspath $(BUILD)/core_tb) $(CORE_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

## ---- SoC platform harness (Linux/OpenSBI boot, issue #21) --------------
$(BUILD)/soc_tb: $(ROOT)/tb/cpp/soc_tb.cpp $(CORE_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/soc --top-module muserisc_core \
	  -o $(abspath $(BUILD)/soc_tb) $(CORE_RTL) \
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
SOC_RTL   := $(CORE_RTL) $(CRYPTO)/sha256_block.sv \
             $(CRYPTO)/ec_field.sv $(CRYPTO)/muse_crypto_top.sv \
             $(SOCDIR)/muserisc_clint.sv $(SOCDIR)/muserisc_plic.sv \
             $(SOCDIR)/muserisc_uart16550.sv \
             $(SOCDIR)/muserisc_bootrom.sv \
             $(SOCDIR)/muserisc_crypto_bridge.sv \
             $(SOCDIR)/muserisc_soc_top.sv
SOCFW     := $(ROOT)/build/soc-tests

$(BUILD)/soc_rtl_tb: $(ROOT)/tb/cpp/soc_rtl_tb.cpp $(SOC_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/socrtl --top-module muserisc_soc_top \
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
	cd $(BUILD) && COV_FILE=cov_socrtl.dat ./soc_rtl_tb 200000000 \
	  --load 0x80000000=$(SOCFW)/crypto_soc_test.bin \
	  --exit-string "SOC CRYPTO PASS"

$(BUILD)/%.bin: $(ROOT)/sw/core-tests/%.S $(ROOT)/sw/core-tests/link.ld | $(BUILD)
	$(RISCV_GCC) $(SWFLAGS) $< -o $(BUILD)/$*.elf
	$(RISCV_OBJCOPY) -O binary $(BUILD)/$*.elf $@

core: $(BUILD)/core_tb $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS)))
	cd $(BUILD) && COV_FILE=cov_rv64i.dat ./core_tb rv64i_directed.bin
	cd $(BUILD) && COV_FILE=cov_rv64m.dat ./core_tb rv64m_directed.bin
	cd $(BUILD) && COV_FILE=cov_amo.dat ./core_tb amo_directed.bin
	cd $(BUILD) && COV_FILE=cov_fp.dat ./core_tb fp_directed.bin
	cd $(BUILD) && COV_FILE=cov_bextsw.dat ./core_tb bext_directed.bin
	cd $(BUILD) && COV_FILE=cov_rvcsw.dat ./core_tb rvc_directed.bin
	cd $(BUILD) && COV_FILE=cov_pipeline.dat ./core_tb pipeline_directed.bin
	cd $(BUILD) && COV_FILE=cov_priv.dat ./core_tb priv_directed.bin --irq-timer-after 2000
	@# Timer IRQ at every offset across a run of trapping misaligned
	@# loads: the interrupt must survive exceptions taken while it
	@# is pending.
	cd $(BUILD) && for o in $$(seq 20 120); do \
	  COV_FILE=cov_irqexc_$$o.dat ./core_tb irq_exc_race_directed.bin --irq-timer-after $$o \
	    > irq_exc_$$o.log 2>&1 || { echo "offset $$o:"; cat irq_exc_$$o.log; exit 1; }; \
	done; echo "CORE TB PASS irq_exc_race_directed.bin (101/101 IRQ offsets 20..120)"
	cd $(BUILD) && verilator_coverage --write cov_irqexc.dat cov_irqexc_*.dat
	cd $(BUILD) && COV_FILE=cov_vm.dat ./core_tb vm_directed.bin
	cd $(BUILD) && COV_FILE=cov_trap_illegal.dat ./core_tb trap_illegal.bin 100000 --expect-trap 2
	cd $(BUILD) && COV_FILE=cov_trap_misalign.dat ./core_tb trap_misalign.bin 100000 --expect-trap 4
	cd $(BUILD) && COV_FILE=cov_trap_ecall.dat ./core_tb trap_ecall.bin 100000 --expect-trap 11
	cd $(BUILD) && COV_FILE=cov_trap_ebreak.dat ./core_tb trap_ebreak.bin 100000 --expect-trap 3
	cd $(BUILD) && COV_FILE=cov_trap_smisalign.dat ./core_tb trap_store_misalign.bin 100000 --expect-trap 6
	cd $(BUILD) && COV_FILE=cov_trap_ystore.dat ./core_tb trap_younger_store.bin 100000 --expect-trap 4
	cd $(BUILD) && COV_FILE=cov_trap_ycsr.dat ./core_tb trap_younger_csr.bin
	cd $(BUILD) && COV_FILE=cov_counter_time.dat ./core_tb counter_time_directed.bin
	cd $(BUILD) && COV_FILE=cov_hyp.dat ./core_tb hyp_directed.bin
	cd $(BUILD) && COV_FILE=cov_vecsw.dat ./core_tb vec_directed.bin
	cd $(BUILD) && COV_FILE=cov_fpvecsw.dat ./core_tb fpvec_directed.bin
	cd $(BUILD) && COV_FILE=cov_trap_pa_fetch.dat ./core_tb trap_pa_fetch.bin 100000 --expect-trap 1
	cd $(BUILD) && COV_FILE=cov_trap_pa_load.dat ./core_tb trap_pa_load.bin 100000 --expect-trap 5

## ---- Coverage ----------------------------------------------------------
# Annotate from this directory: the .dat files record source paths
# relative to sim/, where verilator was invoked. Inputs are listed
# explicitly so a stale merged file can never feed back into a merge.
COV_INPUTS := $(wildcard $(BUILD)/cov_rvtest.dat) \
              $(wildcard $(BUILD)/cov_sha256.dat) \
              $(wildcard $(BUILD)/cov_sha512.dat) \
              $(wildcard $(BUILD)/cov_keccak.dat) \
              $(wildcard $(BUILD)/cov_ecfield.dat) \
              $(wildcard $(BUILD)/cov_cryptotop.dat) \
              $(BUILD)/cov_alu.dat $(BUILD)/cov_muldiv.dat \
              $(BUILD)/cov_decoder.dat $(BUILD)/cov_regfile.dat \
              $(BUILD)/cov_csr.dat $(BUILD)/cov_mmu.dat \
              $(BUILD)/cov_fpu.dat \
              $(BUILD)/cov_rv64i.dat $(BUILD)/cov_rv64m.dat \
              $(BUILD)/cov_amo.dat $(BUILD)/cov_fp.dat \
              $(BUILD)/cov_bext.dat $(BUILD)/cov_bextsw.dat \
              $(BUILD)/cov_rvc.dat $(BUILD)/cov_rvcsw.dat \
              $(BUILD)/cov_pipeline.dat $(BUILD)/cov_priv.dat $(BUILD)/cov_irqexc.dat \
              $(BUILD)/cov_vm.dat \
              $(BUILD)/cov_trap_illegal.dat $(BUILD)/cov_trap_misalign.dat \
              $(BUILD)/cov_trap_ecall.dat $(BUILD)/cov_trap_ebreak.dat \
              $(BUILD)/cov_trap_smisalign.dat $(BUILD)/cov_trap_ystore.dat \
              $(BUILD)/cov_vec.dat $(BUILD)/cov_vecsw.dat \
              $(BUILD)/cov_trap_ycsr.dat $(BUILD)/cov_counter_time.dat $(BUILD)/cov_hyp.dat \
              $(BUILD)/cov_trap_pa_fetch.dat \
              $(BUILD)/cov_trap_pa_load.dat
coverage:
	@rm -f $(BUILD)/cov_merged.dat
	@verilator_coverage --write $(BUILD)/cov_merged.dat $(COV_INPUTS)
	@verilator_coverage --annotate $(BUILD)/coverage $(BUILD)/cov_merged.dat | tail -5

clean:
	rm -rf $(BUILD)
