# Synthesis script for the Sigil CL (issue #54), sourced by the HDK's
# build_all.tcl (aws-fpga v2.3.5) via aws_build_dcp_from_cl.py; run it
# through fpga/scripts/build_cl_sigil.sh, which sets CL_DIR and links
# the HDK build scripts. Follows the HDK cl_mem_perf synth script.
#
# Sources: the CL glue in $CL_DIR/design (copied to src_post_encryption
# by encrypt.tcl; never encrypted -- the AFI is meant to be public and
# rebuildable from this repository) plus the SoC RTL read straight
# from the repository (rtl/sigil_soc_files.mk + rtl/fpga).

source ${HDK_SHELL_DIR}/build/scripts/synth_cl_header.tcl

set repo_root [file normalize ${CL_DIR}/../..]
set rtl_dir   ${repo_root}/rtl

# Core clock = AWS_CLK_GEN clk_extra_b1; its frequency per group-B
# recipe (HDK docs/Clock_Recipes_User_Guide.md), exposed to the host
# as the OCL CLK_KHZ register.
switch $clock_recipe_b {
  "B0" { set core_khz 125000 }
  "B1" { set core_khz 62500 }
  "B2" { set core_khz 225000 }
  "B3" { set core_khz 62500 }
  "B4" { set core_khz 75000 }
  "B5" { set core_khz 100000 }
  default { error "unknown clock_recipe_b $clock_recipe_b" }
}
print "Sigil core clock: clk_extra_b1, recipe $clock_recipe_b = ${core_khz} kHz"

print "Reading Sigil SoC RTL from ${rtl_dir}"
set fh [open ${rtl_dir}/sigil_soc_files.mk r]; set mk [read $fh]; close $fh
set soc_files {}
foreach tok [regexp -all -inline {[A-Za-z0-9_/]+\.sv} $mk] { lappend soc_files ${rtl_dir}/$tok }
lappend soc_files \
  ${rtl_dir}/fpga/sigil_fifo.sv \
  ${rtl_dir}/fpga/sigil_mbus_axi4.sv \
  ${rtl_dir}/fpga/sigil_axi_memeng.sv \
  ${rtl_dir}/fpga/sigil_fpga_top.sv \
  ${rtl_dir}/fpga/sigil_ocl_regs.sv \
  ${rtl_dir}/fpga/sigil_fpga_ocl.sv \
  ${rtl_dir}/fpga/sigil_axi_decerr.sv
read_verilog -sv $soc_files

print "Reading CL glue (src_post_encryption, not encrypted)"
read_verilog -sv [glob ${src_post_enc_dir}/*.{s,}v]
read_verilog -sv [glob ${src_post_enc_dir}/cl_sigil_defines.vh]
set_property file_type {Verilog Header} [get_files ${src_post_enc_dir}/cl_sigil_defines.vh]
set_property is_global_include true     [get_files ${src_post_enc_dir}/cl_sigil_defines.vh]

print "Reading CL IP blocks"
read_ip [ list \
  ${HDK_IP_SRC_DIR}/cl_ddr4_32g/cl_ddr4_32g.xci \
  ${HDK_IP_SRC_DIR}/cl_ddr4_32g_ap/cl_ddr4_32g_ap.xci \
  ${HDK_IP_SRC_DIR}/cl_ddr4/cl_ddr4.xci \
  ${HDK_IP_SRC_DIR}/cl_ddr4_64g_ap/cl_ddr4_64g_ap.xci \
]
read_ip [ list \
  ${HDK_IP_SRC_DIR}/clk_mmcm_a/clk_mmcm_a.xci \
  ${HDK_IP_SRC_DIR}/clk_mmcm_b/clk_mmcm_b.xci \
  ${HDK_IP_SRC_DIR}/clk_mmcm_c/clk_mmcm_c.xci \
  ${HDK_IP_SRC_DIR}/clk_mmcm_hbm/clk_mmcm_hbm.xci \
  ${HDK_IP_SRC_DIR}/cl_clk_axil_xbar/cl_clk_axil_xbar.xci \
  ${HDK_IP_SRC_DIR}/cl_axi_register_slice_light/cl_axi_register_slice_light.xci \
]
read_ip [ list \
  ${HDK_IP_SRC_DIR}/axi_register_slice/axi_register_slice.xci \
  ${HDK_IP_SRC_DIR}/cl_axi_clock_converter/cl_axi_clock_converter.xci \
  ${HDK_IP_SRC_DIR}/cl_axi_clock_converter_light/cl_axi_clock_converter_light.xci \
]
read_ip [ list \
  ${HDK_IP_SRC_DIR}/cl_hbm/cl_hbm.xci \
  ${HDK_IP_SRC_DIR}/cl_axi3_256b_reg_slice/cl_axi3_256b_reg_slice.xci \
]
add_files [ list \
  ${HDK_BD_SRC_DIR}/cl_axi_sc_1x1/cl_axi_sc_1x1.bd \
  ${HDK_BD_SRC_DIR}/cl_axi_sc_2x2/cl_axi_sc_2x2.bd \
]
read_verilog [ list \
  ${HDK_BD_GEN_DIR}/cl_axi_sc_1x1/hdl/cl_axi_sc_1x1_wrapper.v \
  ${HDK_BD_GEN_DIR}/cl_axi_sc_2x2/hdl/cl_axi_sc_2x2_wrapper.v \
]

# HBM (issue #66): the HDK cl_mem_perf example's HBM wrapper (cl_hbm IP on
# AWS_CLK_GEN's clk_hbm_axi), read from the pinned aws-fpga checkout.
set hdk_mem_perf [file normalize ${HDK_SHELL_DESIGN_DIR}/../../../cl/examples/cl_mem_perf/design]
print "Reading HBM wrapper from ${hdk_mem_perf}"
read_verilog -sv [ list ${hdk_mem_perf}/cl_mem_hbm_wrapper.sv ]

print "Reading user constraints"
read_xdc [ list \
  ${constraints_dir}/cl_synth_user.xdc \
  ${constraints_dir}/cl_timing_user.xdc
]
set_property PROCESSING_ORDER LATE [get_files cl_synth_user.xdc]
set_property PROCESSING_ORDER LATE [get_files cl_timing_user.xdc]

print "Starting synthesizing customer design ${CL}"
update_compile_order -fileset sources_1

synth_design -mode out_of_context \
             -top ${CL} \
             -verilog_define XSDB_SLV_DIS \
             -verilog_define SYNTHESIS \
             -verilog_define SIGIL_CORE_CLK_KHZ=${core_khz} \
             -include_dirs [list ${rtl_dir}/core ${src_post_enc_dir}] \
             -part ${DEVICE_TYPE} \
             -keep_equivalent_registers

report_utilization -hierarchical -hierarchical_depth 4 \
  -file ${reports_dir}/${CL}.${TAG}.post_synth_util_hier.rpt

source ${HDK_SHELL_DIR}/build/scripts/synth_cl_footer.tcl
