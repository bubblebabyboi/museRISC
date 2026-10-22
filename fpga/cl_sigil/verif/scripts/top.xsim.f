# XSIM file list for the Sigil CL (issue #54). Maintained by hand:
# keep the SoC part in sync with rtl/sigil_soc_files.mk + rtl/fpga.

-define CL_NAME=cl_sigil
-define DISABLE_VJTAG_DEBUG
-define SIGIL_CORE_CLK_KHZ=62500

-include $CL_DIR/../../rtl/core
$CL_DIR/../../rtl/core/sigil_pkg.sv
$CL_DIR/../../rtl/core/sigil_cache_pkg.sv
$CL_DIR/../../rtl/core/sigil_regfile.sv
$CL_DIR/../../rtl/core/sigil_fpregfile.sv
$CL_DIR/../../rtl/core/sigil_alu.sv
$CL_DIR/../../rtl/core/sigil_muldiv.sv
$CL_DIR/../../rtl/core/sigil_muldiv_mc.sv
$CL_DIR/../../rtl/core/sigil_fpu_pkg.sv
$CL_DIR/../../rtl/core/sigil_fpu.sv
$CL_DIR/../../rtl/core/sigil_bext_pkg.sv
$CL_DIR/../../rtl/core/sigil_bext.sv
$CL_DIR/../../rtl/core/sigil_vregfile.sv
$CL_DIR/../../rtl/core/sigil_vec_pkg.sv
$CL_DIR/../../rtl/core/sigil_vec.sv
$CL_DIR/../../rtl/core/sigil_rvc.sv
$CL_DIR/../../rtl/core/sigil_decoder.sv
$CL_DIR/../../rtl/core/sigil_csr.sv
$CL_DIR/../../rtl/core/sigil_mmu.sv
$CL_DIR/../../rtl/core/sigil_core.sv
$CL_DIR/../../rtl/core/sigil_sram_sp.sv
$CL_DIR/../../rtl/core/sigil_icache.sv
$CL_DIR/../../rtl/core/sigil_dcache.sv
$CL_DIR/../../rtl/core/sigil_bus_arb.sv
$CL_DIR/../../rtl/core/sigil_cpu.sv
$CL_DIR/../../rtl/crypto/sha256_block.sv
$CL_DIR/../../rtl/crypto/sha512_block.sv
$CL_DIR/../../rtl/crypto/keccak_f1600.sv
$CL_DIR/../../rtl/crypto/sigil_hash_stream.sv
$CL_DIR/../../rtl/crypto/ec_field.sv
$CL_DIR/../../rtl/crypto/sigil_crypto_top.sv
$CL_DIR/../../rtl/soc/sigil_clint.sv
$CL_DIR/../../rtl/soc/sigil_plic.sv
$CL_DIR/../../rtl/soc/sigil_uart16550.sv
$CL_DIR/../../rtl/soc/sigil_bootrom.sv
$CL_DIR/../../rtl/soc/sigil_test_finisher.sv
$CL_DIR/../../rtl/soc/sigil_rtc_goldfish.sv
$CL_DIR/../../rtl/soc/sigil_crypto_bridge.sv
$CL_DIR/../../rtl/soc/sigil_soc_fabric.sv
$CL_DIR/../../rtl/soc/sigil_soc_top.sv
$CL_DIR/../../rtl/fpga/sigil_fifo.sv
$CL_DIR/../../rtl/fpga/sigil_mbus_axi4.sv
$CL_DIR/../../rtl/fpga/sigil_axi_memeng.sv
$CL_DIR/../../rtl/fpga/sigil_fpga_top.sv
$CL_DIR/../../rtl/fpga/sigil_ocl_regs.sv
$CL_DIR/../../rtl/fpga/sigil_fpga_ocl.sv
$CL_DIR/../../rtl/fpga/sigil_axi_decerr.sv

-include $CL_DIR/design
$CL_DIR/design/cl_sigil.sv

-include $CL_DIR/verif/tests
-f ${HDK_COMMON_DIR}/verif/tb/filelists/tb.${SIMULATOR}.f
${TEST_NAME}
