# SoC RTL source list for the ORFS flows (paths relative to rtl/),
# shared by flow/designs/{nangate45,sky130hd}/muserisc_soc/config.mk.
# It lives under rtl/ because openroad_docker.sh mounts this tree at
# designs/src/muserisc_soc. Order matters for slang: packages first.
MUSERISC_SOC_RTL = \
  core/muserisc_pkg.sv \
  core/muserisc_regfile.sv \
  core/muserisc_fpregfile.sv \
  core/muserisc_alu.sv \
  core/muserisc_muldiv.sv \
  core/muserisc_muldiv_mc.sv \
  core/muserisc_fpu_pkg.sv \
  core/muserisc_fpu.sv \
  core/muserisc_bext_pkg.sv \
  core/muserisc_bext.sv \
  core/muserisc_vregfile.sv \
  core/muserisc_vec_pkg.sv \
  core/muserisc_vec.sv \
  core/muserisc_rvc.sv \
  core/muserisc_decoder.sv \
  core/muserisc_csr.sv \
  core/muserisc_mmu.sv \
  core/muserisc_cache_pkg.sv \
  core/muserisc_core.sv \
  core/muserisc_sram_sp.sv \
  core/muserisc_icache.sv \
  core/muserisc_dcache.sv \
  core/muserisc_bus_arb.sv \
  core/muserisc_cpu.sv \
  crypto/sha256_block.sv \
  crypto/ec_field.sv \
  crypto/muse_crypto_top.sv \
  soc/muserisc_clint.sv \
  soc/muserisc_plic.sv \
  soc/muserisc_uart16550.sv \
  soc/muserisc_bootrom.sv \
  soc/muserisc_crypto_bridge.sv \
  soc/muserisc_soc_fabric.sv \
  soc/muserisc_soc_top.sv
