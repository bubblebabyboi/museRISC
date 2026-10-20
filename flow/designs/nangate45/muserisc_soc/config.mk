export DESIGN_NAME = muserisc_soc_top
export PLATFORM    = nangate45
# Core RTL is full SystemVerilog (packages/imports): the
# default Yosys Verilog-2005 frontend rejects it, use the
# slang frontend built into the ORFS Yosys.
export SYNTH_HDL_FRONTEND = slang
# Whole-vector/FPU combinational loops exceed slang's
# default 4000 unroll limit (fp_eval + 512-wide vec).
export SYNTH_SLANG_ARGS = --unroll-limit=200000
# Source order matters (packages first); tree is the repo rtl/
# mounted at designs/src/muserisc_soc by openroad_docker.sh.
export VERILOG_FILES = \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_pkg.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_regfile.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_fpregfile.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_alu.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_muldiv.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_fpu_pkg.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_fpu.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_bext_pkg.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_bext.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_vregfile.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_vec_pkg.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_vec.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_rvc.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_decoder.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_csr.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_mmu.sv \
  $(DESIGN_HOME)/src/muserisc_soc/core/muserisc_core.sv \
  $(DESIGN_HOME)/src/muserisc_soc/crypto/sha256_block.sv \
  $(DESIGN_HOME)/src/muserisc_soc/crypto/ec_field.sv \
  $(DESIGN_HOME)/src/muserisc_soc/crypto/muse_crypto_top.sv \
  $(DESIGN_HOME)/src/muserisc_soc/soc/muserisc_clint.sv \
  $(DESIGN_HOME)/src/muserisc_soc/soc/muserisc_plic.sv \
  $(DESIGN_HOME)/src/muserisc_soc/soc/muserisc_uart16550.sv \
  $(DESIGN_HOME)/src/muserisc_soc/soc/muserisc_bootrom.sv \
  $(DESIGN_HOME)/src/muserisc_soc/soc/muserisc_crypto_bridge.sv \
  $(DESIGN_HOME)/src/muserisc_soc/soc/muserisc_soc_top.sv
# muserisc_fpu_ops.svh is `included by muserisc_fpu_pkg.sv and
# muserisc_fpu.sv.
export VERILOG_INCLUDE_DIRS = $(DESIGN_HOME)/src/muserisc_soc/core
export SDC_FILE      = $(DESIGN_HOME)/nangate45/muserisc_soc/constraint.sdc
# First full-SoC closure attempt (issue #11 slice): start
# sparse; the combinational FPU/vector datapaths, not
# utilization, are expected to set Fmax. Report honestly.
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
export CLOCK_PERIOD = 10
export EARLY_SIZING_CAP_RATIO = 0.8
# Same weak-cell ban as the crypto macro (see muse_crypto
# config.mk for the liberty evidence, #31).
override export DONT_USE_CELLS = TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1 \
                        AOI221_X1 OAI221_X1 NOR3_X1 NOR4_X1 NOR4_X2
