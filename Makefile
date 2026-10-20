# museRISC Phase-0 make targets. See docs/ROADMAP.md for phased goals.
RTL := rtl/crypto/sha256_block.sv rtl/crypto/keccak_f1600.sv \
       rtl/crypto/ec_field.sv rtl/crypto/muse_crypto_top.sv \
       rtl/soc/muserisc_clint.sv rtl/soc/muserisc_plic.sv \
       rtl/soc/muserisc_uart16550.sv rtl/soc/muserisc_bootrom.sv \
       rtl/soc/muserisc_crypto_bridge.sv \
       rtl/soc/muserisc_soc_fabric.sv rtl/soc/muserisc_soc_top.sv
BUILD := build

CORE_RTL := rtl/core/muserisc_pkg.sv rtl/core/muserisc_regfile.sv \
            rtl/core/muserisc_fpregfile.sv rtl/core/muserisc_alu.sv \
            rtl/core/muserisc_muldiv.sv \
            rtl/core/muserisc_muldiv_mc.sv \
            rtl/core/muserisc_fpu_pkg.sv rtl/core/muserisc_fpu.sv \
            rtl/core/muserisc_bext_pkg.sv rtl/core/muserisc_bext.sv \
            rtl/core/muserisc_vregfile.sv \
            rtl/core/muserisc_vec_pkg.sv rtl/core/muserisc_vec.sv \
            rtl/core/muserisc_rvc.sv \
            rtl/core/muserisc_decoder.sv rtl/core/muserisc_csr.sv \
            rtl/core/muserisc_mmu.sv rtl/core/muserisc_cache_pkg.sv \
            rtl/core/muserisc_core.sv
# L1 caches + CPU wrapper (top: muserisc_cpu); the cache package
# is already in CORE_RTL.
CACHE_RTL := rtl/core/muserisc_sram_sp.sv \
             rtl/core/muserisc_icache.sv rtl/core/muserisc_dcache.sv \
             rtl/core/muserisc_bus_arb.sv rtl/core/muserisc_cpu.sv

.PHONY: test lint core-test riscv-tests openroad compliance clean
test: ## Python golden self-check + Verilator C++ crypto KATs (needs python3, verilator)
	python3 sw/golden.py
	python3 sw/ec_ops.py
	$(MAKE) -C sim crypto
	@echo "ALL PHASE-0 KATs PASS"

# Behavioural models of the ORFS SRAM macros (VRF + L1 arrays).
SRAM_MODELS_FAKERAM45 := $(addprefix flow/designs/nangate45/muserisc_soc/sram/,\
  fakeram45_256x64_1r1w.v fakeram45_512x64.v fakeram45_64x44.v)
SRAM_MODELS_SKY130 := $(addprefix flow/designs/sky130hd/muserisc_soc/sram/,\
  sky130_sram_1rw1r_64x256_8.v sky130_sram_1rw1r_128x256_8.v sky130_sram_1rw1r_44x64_8.v)

lint: ## Verilator lint on all synthesizable RTL
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module muserisc_soc_top $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module keccak_f1600 rtl/crypto/keccak_f1600.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sha512_block rtl/crypto/sha512_block.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module muserisc_core $(CORE_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module muserisc_muldiv_mc rtl/core/muserisc_muldiv.sv rtl/core/muserisc_muldiv_mc.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module muserisc_muldiv_mc -GCOMB=1 rtl/core/muserisc_muldiv.sv rtl/core/muserisc_muldiv_mc.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module muserisc_cpu $(CORE_RTL) $(CACHE_RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module muserisc_soc_top +define+MUSERISC_SRAM_FAKERAM45 $(SRAM_MODELS_FAKERAM45) $(CORE_RTL) $(CACHE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module muserisc_soc_top +define+MUSERISC_SRAM_SKY130 $(SRAM_MODELS_SKY130) $(CORE_RTL) $(CACHE_RTL) $(RTL)

core-test: ## In-house core C++ Verilator TBs + directed asm + coverage (issue #18)
	$(MAKE) -C sim

riscv-tests: ## Stage gate: upstream riscv-tests rv64ui/um on the in-house core (#18)
	$(MAKE) -C sim riscv-tests

openroad: ## Dockerized OpenROAD-flow-scripts run on the crypto macro
	./scripts/openroad_docker.sh

compliance: ## ACT4 riscv-arch-test RV64I on Sail (harness validation)
	./scripts/run_compliance.sh

clean:
	rm -rf $(BUILD)
