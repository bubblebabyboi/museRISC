# museRISC Phase-0 make targets. See docs/ROADMAP.md for phased goals.
RTL := rtl/crypto/sha256_block.sv rtl/crypto/keccak_f1600.sv \
       rtl/crypto/ec_field.sv rtl/crypto/muse_crypto_top.sv \
       rtl/soc/muserisc_clint.sv rtl/soc/muserisc_plic.sv \
       rtl/soc/muserisc_uart16550.sv rtl/soc/muserisc_bootrom.sv \
       rtl/soc/muserisc_crypto_bridge.sv \
       rtl/soc/muserisc_soc_top.sv
BUILD := build

CORE_RTL := rtl/core/muserisc_pkg.sv rtl/core/muserisc_regfile.sv \
            rtl/core/muserisc_fpregfile.sv rtl/core/muserisc_alu.sv \
            rtl/core/muserisc_muldiv.sv \
            rtl/core/muserisc_fpu_pkg.sv rtl/core/muserisc_fpu.sv \
            rtl/core/muserisc_bext_pkg.sv rtl/core/muserisc_bext.sv \
            rtl/core/muserisc_vregfile.sv \
            rtl/core/muserisc_vec_pkg.sv rtl/core/muserisc_vec.sv \
            rtl/core/muserisc_rvc.sv \
            rtl/core/muserisc_decoder.sv rtl/core/muserisc_csr.sv \
            rtl/core/muserisc_mmu.sv rtl/core/muserisc_core.sv

.PHONY: test lint core-test riscv-tests openroad compliance clean
test: ## Python golden self-check + Verilator C++ crypto KATs (needs python3, verilator)
	python3 sw/golden.py
	python3 sw/ec_ops.py
	$(MAKE) -C sim crypto
	@echo "ALL PHASE-0 KATs PASS"

lint: ## Verilator lint on all synthesizable RTL
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module muserisc_soc_top $(CORE_RTL) $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module keccak_f1600 rtl/crypto/keccak_f1600.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sha512_block rtl/crypto/sha512_block.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core --top-module muserisc_core $(CORE_RTL)

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
