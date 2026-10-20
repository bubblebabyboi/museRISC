# SoC RTL source list for the ORFS flows (paths relative to rtl/),
# shared by flow/designs/{nangate45,sky130hd}/sigil_soc/config.mk.
# It lives under rtl/ because openroad_docker.sh mounts this tree at
# designs/src/sigil_soc. Order matters for slang: packages first.
SIGIL_SOC_RTL = \
  core/sigil_pkg.sv \
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
  core/sigil_cache_pkg.sv \
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
  soc/sigil_crypto_bridge.sv \
  soc/sigil_soc_fabric.sv \
  soc/sigil_soc_top.sv
