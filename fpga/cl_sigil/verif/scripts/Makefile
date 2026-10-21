# HDK XSIM environment for the Sigil CL (issue #54); based on the
# aws-fpga v2.3.5 CL_TEMPLATE verif Makefile. Run through
# fpga/scripts/sim_cl_sigil.sh, or: export CL_DIR=.../fpga/cl_sigil;
# source aws-fpga/hdk_setup.sh; cd $CL_DIR/verif/scripts; make <test>.
#
# The fast AXI memory model replaces the Micron DDR4 model by default
# (AXI_MEMORY_MODEL=1, HDK FAST_SIM_MODE + NO_DDR): the DDR controller
# calibration and DRAM timing are not simulated, the AXI path from
# PCIS and the SoC through the SmartConnect into sh_ddr is.

ifndef HDK_COMMON_DIR
  $(error Environment variable HDK_COMMON_DIR not set. Please source hdk_setup.sh)
endif

AXI_MEMORY_MODEL ?= 1
# top.xsim.f is maintained by hand (the SoC RTL lives outside
# $CL_DIR/design), so skip the HDK's file-list generator.
export DONT_GENERATE_FILE_LIST = 1

include $(HDK_COMMON_DIR)/verif/tb/scripts/Makefile.header.inc

C_FILES = $(C_SDK_USR_UTILS_DIR)/sh_dpi_tasks.c $(C_COMMON_DIR)/src/fpga_pci_sv.c
C_INCLUDE_DIRS = $(C_SDK_USR_INC_DIR) $(C_SDK_USR_UTILS_DIR) $(C_COMMON_DIR)/include $(C_COMMON_DIR)/src $(C_INC_DIR) $(C_HEADER_INCLUDE_DIR)

REGRESSION_TEST_LIST = ${DEFAULT_REGRESSION_TEST_LIST_COLLECTION}

regression: run_regression log_regression_results print_regression_results

include $(HDK_COMMON_DIR)/verif/tb/scripts/Makefile.common.inc
