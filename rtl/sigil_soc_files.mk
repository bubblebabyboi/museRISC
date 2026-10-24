# SoC RTL source list for the ORFS flows (paths relative to rtl/),
# shared by flow/designs/{nangate45,sky130hd}/sigil_soc/config.mk.
# It lives under rtl/ because openroad_docker.sh mounts this tree at
# designs/src/sigil_soc. Order matters for slang: packages first.
SIGIL_SOC_RTL = \
  core/sigil_pkg.sv \
  core/sigil_cache_pkg.sv \
  core/sigil_regfile.sv \
  core/sigil_fpregfile.sv \
  core/sigil_alu.sv \
  core/sigil_muldiv.sv \
  core/sigil_muldiv_mc.sv \
  core/sigil_fpu_pkg.sv \
  core/sigil_fpu.sv \
  core/sigil_bext_pkg.sv \
  core/sigil_bext.sv \
  core/sigil_vregfile.sv \
  core/sigil_vec_pkg.sv \
  core/sigil_vec.sv \
  core/sigil_rvc.sv \
  core/sigil_decoder.sv \
  core/sigil_csr.sv \
  core/sigil_mmu.sv \
  core/sigil_core.sv \
  core/sigil_sram_sp.sv \
  core/sigil_icache.sv \
  core/sigil_dcache.sv \
  core/sigil_bus_arb.sv \
  core/sigil_cpu.sv \
  crypto/sha256_block.sv \
  crypto/sha512_block.sv \
  crypto/keccak_f1600.sv \
  crypto/sigil_hash_stream.sv \
  crypto/ec_field.sv \
  crypto/sigil_crypto_top.sv \
  soc/sigil_clint.sv \
  soc/sigil_plic.sv \
  soc/sigil_uart16550.sv \
  soc/sigil_bootrom.sv \
  soc/sigil_test_finisher.sv \
  soc/sigil_rtc_goldfish.sv \
  soc/sigil_crypto_bridge.sv \
  soc/sigil_soc_fabric.sv \
  soc/sigil_soc_top.sv

# sky130hd SoC configuration (W7, owner default, reversible): 4 KiB
# direct-mapped L1 I$ and D$ (64 sets x 64 B lines, one way each),
# set as sigil_soc_top / sigil_cpu parameter overrides by the
# sky130hd ORFS config and by the sky130 SRAM-macro simulation
# builds (sim/Makefile srammacro, make lint). Each way is the same
# 512x64 data / 64x44 tag geometry as the default caches, so the
# same OpenRAM macros map it: 2 data + 2 tag + 3 VRF = 7 macros
# instead of 15. Delete the overrides to get the default 8 KiB
# 2-way I$ / 16 KiB 4-way D$ back.
SIGIL_SOC_PARAMS_SKY130 = IC_WAYS=1 DC_WAYS=1

# MPW cut-down configuration (issue #13, owner decision 2026-10-24):
# the SoC without the vector unit. The define sets
# sigil_pkg::HAS_VECTOR = 0, which leaves out sigil_vec,
# sigil_vregfile and with it the 3 VRF SRAM macros (RV64GC + B + K +
# H, FPU, MMU, caches and the crypto engine are unchanged; misa.V = 0
# and every vector instruction or vector CSR access raises
# illegal-instruction). SIGIL_NO_VECTOR=1 on the ORFS make command
# line selects it in the sky130hd and nangate45 sigil_soc configs:
# the defines go to slang as -D and the VRF macro leaves the macro
# list. Simulation (sim/Makefile novec / sky130novec families) and
# `make lint` use the same lists. Unset, every list below is the
# default (vector) configuration.
SIGIL_SOC_DEFINES_NOVEC = SIGIL_NO_VECTOR
SIGIL_SOC_DEFINES = $(if $(filter 1,$(SIGIL_NO_VECTOR)),$(SIGIL_SOC_DEFINES_NOVEC))
# SRAM macros by role: VRF banks (3 instances) and L1 data + tag ways.
SIGIL_SKY130_VRF_MACROS = sky130_sram_1rw1r_64x256_8
SIGIL_SKY130_L1_MACROS = sky130_sram_1rw1r_128x256_8 sky130_sram_1rw1r_44x64_8
SIGIL_SKY130_MACROS = $(if $(filter 1,$(SIGIL_NO_VECTOR)),,$(SIGIL_SKY130_VRF_MACROS)) \
  $(SIGIL_SKY130_L1_MACROS)
SIGIL_FAKERAM45_VRF_MACROS = fakeram45_256x64_1r1w
