# sigil_soc_top on sky130hd, hierarchical flow (#11): the whole SoC in
# the Caravel user area (2920 x 3520 um) with two hard blocks built by
# ORFS's BLOCKS mechanism (each block's config.mk is in the
# subdirectory of the same name; `make ... generate_abstract` there
# writes the LEF + timing LIB this config reads):
#   sigil_cpu        - core + vector unit + L1 I$/D$ + 7 OpenRAM macros
#   sigil_crypto_top - SHA-256/512, Keccak, EC field unit
# The top level keeps the reset synchronizer, the fabric, CLINT,
# PLIC, UART, boot ROM and the crypto MMIO bridge as std cells.
# Same RTL and sky130 configuration as the flat run in ../sigil_soc
# (SIGIL_SRAM_SKY130 + SIGIL_SOC_PARAMS_SKY130). Synthesis
# blackboxes the two block modules automatically (ORFS passes every
# ADDITIONAL_LIBS cell to slang as --blackboxed-module), so the RTL is
# unchanged.
#
# Floorplan (um, die coordinates; core margin 10):
#   sigil_cpu         (10, 10)     2900 x 2560, pins on its top edge
#   glue channel      y 2570..2660, full width, plus 160 um columns
#                     left and right of the crypto block
#   sigil_crypto_top  (170, 2660)  2590 x 850, pins on its bottom edge
#   SoC pins          left and right die edges above the CPU block
export DESIGN_NICKNAME = sigil_hier
export DESIGN_NAME = sigil_soc_top
export PLATFORM    = sky130hd
export SYNTH_HDL_FRONTEND = slang

export BLOCKS = sigil_cpu sigil_crypto_top

SIGIL_HIER_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(SIGIL_HIER_DIR)/../../src/sigil_soc/sigil_soc_files.mk

export SYNTH_SLANG_ARGS = --unroll-limit=200000 -DSYNTHESIS -DSIGIL_SRAM_SKY130 \
  $(foreach p,$(SIGIL_SOC_PARAMS_SKY130),-G $(p))
export VERILOG_FILES = $(addprefix $(DESIGN_HOME)/src/sigil_soc/,$(SIGIL_SOC_RTL))
export VERILOG_INCLUDE_DIRS = $(DESIGN_HOME)/src/sigil_soc/core
export SYNTH_MEMORY_MAX_BITS = 8192
export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/sigil_soc/constraint.sdc

export DIE_AREA  = 0 0 2920 3520
export CORE_AREA = 10 10 2910 3510
export MACRO_PLACEMENT_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/macro_place.tcl
export MACRO_PLACE_HALO = 10 10
export IO_CONSTRAINTS = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/io.tcl
export PDN_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/pdn.tcl
export PLACE_DENSITY ?= 0.30
export ROUTING_LAYER_ADJUSTMENT ?= 0.3
export GLOBAL_ROUTE_ARGS ?= -congestion_iterations 30 -congestion_report_iter_step 5 -allow_congestion -verbose
