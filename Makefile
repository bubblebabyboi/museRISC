# Sigil Phase-0 make targets. See docs/ROADMAP.md for phased goals.
RTL := rtl/crypto/sha256_block.sv rtl/crypto/sha512_block.sv \
       rtl/crypto/keccak_f1600.sv rtl/crypto/sigil_hash_stream.sv \
       rtl/crypto/ec_field.sv rtl/crypto/sigil_crypto_top.sv \
       rtl/soc/sigil_clint.sv rtl/soc/sigil_plic.sv \
       rtl/soc/sigil_uart16550.sv rtl/soc/sigil_bootrom.sv \
       rtl/soc/sigil_crypto_bridge.sv \
       rtl/soc/sigil_soc_fabric.sv rtl/soc/sigil_soc_top.sv
BUILD := build
# FPGA SoC top + mbus->AXI4 bridge (issue #52).
FPGA_RTL := rtl/fpga/sigil_fifo.sv rtl/fpga/sigil_mbus_axi4.sv \
            rtl/fpga/sigil_fpga_top.sv
# AWS F2 CL core-clock half: OCL registers + FPGA top (issue #54).
# The CL top fpga/cl_sigil/design/cl_sigil.sv instantiates Xilinx IP
# (clock converters, SmartConnect, AWS_CLK_GEN, sh_ddr, XPM) and is
# not Verilator-linted; it is checked by the HDK XSIM/Vivado flows.
FPGA_OCL_RTL := $(FPGA_RTL) rtl/fpga/sigil_ocl_regs.sv rtl/fpga/sigil_fpga_ocl.sv

CORE_RTL := rtl/core/sigil_pkg.sv rtl/core/sigil_cache_pkg.sv rtl/core/sigil_regfile.sv \
            rtl/core/sigil_fpregfile.sv rtl/core/sigil_alu.sv \
            rtl/core/sigil_muldiv.sv \
            rtl/core/sigil_muldiv_mc.sv \
            rtl/core/sigil_fpu_pkg.sv rtl/core/sigil_fpu.sv \
            rtl/core/sigil_bext_pkg.sv rtl/core/sigil_bext.sv \
            rtl/core/sigil_vregfile.sv \
            rtl/core/sigil_vec_pkg.sv rtl/core/sigil_vec.sv \
            rtl/core/sigil_rvc.sv \
            rtl/core/sigil_decoder.sv rtl/core/sigil_csr.sv \
            rtl/core/sigil_mmu.sv \
            rtl/core/sigil_core.sv
# L1 caches + CPU wrapper (top: sigil_cpu); the cache package
# is already in CORE_RTL.
CACHE_RTL := rtl/core/sigil_sram_sp.sv \
             rtl/core/sigil_icache.sv rtl/core/sigil_dcache.sv \
             rtl/core/sigil_bus_arb.sv rtl/core/sigil_cpu.sv

.PHONY: test lint core-test riscv-tests openroad compliance clean
test: ## Python golden self-check + Verilator C++ crypto KATs (needs python3, verilator)
	python3 sw/golden.py
	python3 sw/ec_ops.py
	python3 sw/hash_kat.py --self-check
	$(MAKE) -C sim crypto
	@echo "ALL PHASE-0 KATs PASS"

# sky130 SoC parameter overrides (SIGIL_SOC_PARAMS_SKY130).
include rtl/sigil_soc_files.mk
# Behavioural models of the ORFS SRAM macros (VRF + L1 arrays).
SRAM_MODELS_FAKERAM45 := $(addprefix flow/designs/nangate45/sigil_soc/sram/,\
  fakeram45_256x64_1r1w.v fakeram45_512x64.v fakeram45_64x44.v)
SRAM_MODELS_SKY130 := $(addprefix flow/designs/sky130hd/sigil_soc/sram/,\
  sky130_sram_1rw1r_64x256_8.v sky130_sram_1rw1r_128x256_8.v sky130_sram_1rw1r_44x64_8.v)

lint: ## Verilator lint on all synthesizable RTL
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_soc_top $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module keccak_f1600 rtl/crypto/keccak_f1600.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sha512_block rtl/crypto/sha512_block.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_core $(CORE_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sigil_muldiv_mc rtl/core/sigil_muldiv.sv rtl/core/sigil_muldiv_mc.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sigil_muldiv_mc -GCOMB=1 rtl/core/sigil_muldiv.sv rtl/core/sigil_muldiv_mc.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_cpu $(CORE_RTL) $(CACHE_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_cpu +define+SIGIL_COMMIT_TRACE $(CORE_RTL) $(CACHE_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_soc_top +define+SIGIL_SRAM_FAKERAM45 $(SRAM_MODELS_FAKERAM45) $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_soc_top +define+SIGIL_SRAM_SKY130 $(addprefix -G,$(SIGIL_SOC_PARAMS_SKY130)) $(SRAM_MODELS_SKY130) $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_soc_top +define+SIGIL_SRAM_SKY130 $(SRAM_MODELS_SKY130) $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_soc_top +define+SIGIL_SRAM_OREG $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_soc_top +define+SIGIL_VRF_OREG $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_fpga_top $(CORE_RTL) $(CACHE_RTL) $(RTL) $(FPGA_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_fpga_top -GAXI_DATA_W=512 $(CORE_RTL) $(CACHE_RTL) $(RTL) $(FPGA_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sigil_mbus_axi4 -GAXI_DATA_W=128 rtl/fpga/sigil_mbus_axi4.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module sigil_fpga_ocl $(CORE_RTL) $(CACHE_RTL) $(RTL) $(FPGA_OCL_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sigil_axi_decerr rtl/fpga/sigil_axi_decerr.sv

core-test: ## In-house core C++ Verilator TBs + directed asm + coverage (issue #18)
	$(MAKE) -C sim

riscv-tests: ## Stage gate: upstream riscv-tests rv64ui/um on the in-house core (#18)
	$(MAKE) -C sim riscv-tests

riscv-dv: ## riscv-dv random-instruction regression vs Spike (#8; TESTS= SEEDS= JOBS=)
	$(MAKE) -C sim riscv-dv

openroad: ## Dockerized OpenROAD-flow-scripts run on the crypto macro
	./scripts/openroad_docker.sh

compliance: ## ACT4 riscv-arch-test RV64I on Sail (harness validation)
	./scripts/run_compliance.sh

clean:
	rm -rf $(BUILD)
