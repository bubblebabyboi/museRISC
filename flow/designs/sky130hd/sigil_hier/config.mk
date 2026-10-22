# sigil_soc_top on sky130hd, hierarchical flow (#11): the whole SoC in
# the Caravel user area (2920 x 3520 um) with two hard blocks, each
# built first with its own config in the subdirectory of the same name
# (`make DESIGN_CONFIG=.../<block>/config.mk generate_abstract` writes
# the LEF + timing LIB + GDS this config reads):
#   sigil_cpu        - core + vector unit + L1 I$/D$ + 7 OpenRAM macros
#   sigil_crypto_top - SHA-256/512, Keccak, EC field unit
# The top level keeps the reset synchronizer, the fabric, CLINT,
# PLIC, UART, boot ROM and the crypto MMIO bridge as std cells.
# Same RTL and sky130 configuration as the flat run in ../sigil_soc
# (SIGIL_SRAM_SKY130 + SIGIL_SOC_PARAMS_SKY130); the RTL is unchanged.
#
# Why not ORFS's BLOCKS variable: BLOCKS adds the block .libs to
# ADDITIONAL_LIBS for synthesis too, and ORFS then blackboxes the
# block modules from their liberty view. yosys-slang gives the
# blackboxed u_cpu cell all of sigil_cpu's parameters (IC_SETS ...
# C1_SIZE), which the liberty view does not have, so `hierarchy
# -check` fails ("does not have a parameter named 'C1_SIZE'"); the
# same happens with SYNTH_BLACKBOXES. Instead the top is synthesized
# from port-only stubs of the two blocks (stubs/, generated from the
# RTL headers by stubs/gen_stubs.sh) that slang keeps as blackboxes
# (--empty-blackboxes), without the block libs (SIGIL_TOP_SYNTH=1 on
# the synth run); every later stage reads the block abstracts below.
#
# Floorplan (um, die coordinates; core margin 2, block halos 5; RTLMP
# checks that every macro plus halo lies inside the core):
#   glue column       x 2..135, full height: reset synchronizer,
#                     fabric, CLINT, PLIC, UART, boot ROM, crypto
#                     bridge; all SoC pins on the left die edge
#   sigil_cpu         (140, 10)    2770 x 2680, pins on its left edge
#   sigil_crypto_top  (140, 2700)  2770 x 810,  pins on its left edge
# (v1 put the glue in a 90 um channel between the blocks with the
# CPU pins on its 2900 um top edge; global routing overflowed on
# 79k gcells: ~400 nets had to run sideways to the die-edge pins.)
export DESIGN_NICKNAME = sigil_hier
export DESIGN_NAME = sigil_soc_top
export PLATFORM    = sky130hd
export SYNTH_HDL_FRONTEND = slang

SIGIL_BLOCKS = sigil_cpu sigil_crypto_top
SIGIL_BLOCK_DIR = $(WORK_HOME)/results/$(PLATFORM)/sigil_hier_$(1)/$(FLOW_VARIANT)
export ADDITIONAL_LEFS = $(foreach b,$(SIGIL_BLOCKS),$(call SIGIL_BLOCK_DIR,$(b))/$(b).lef)
export ADDITIONAL_GDS  = $(foreach b,$(SIGIL_BLOCKS),$(call SIGIL_BLOCK_DIR,$(b))/6_final.gds)
ifneq ($(SIGIL_TOP_SYNTH),1)
export ADDITIONAL_LIBS = $(foreach b,$(SIGIL_BLOCKS),$(call SIGIL_BLOCK_DIR,$(b))/$(b)_typ.lib)
endif

SIGIL_HIER_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(SIGIL_HIER_DIR)/../../src/sigil_soc/sigil_soc_files.mk

export SYNTH_SLANG_ARGS = --unroll-limit=200000 -DSYNTHESIS -DSIGIL_SRAM_SKY130 \
  --empty-blackboxes $(foreach p,$(SIGIL_SOC_PARAMS_SKY130),-G $(p))
# Packages (the sigil_cpu header imports sigil_cache_pkg), the block
# stubs, and the SoC-level RTL.
export VERILOG_FILES = \
  $(addprefix $(DESIGN_HOME)/src/sigil_soc/,$(filter %_pkg.sv,$(filter core/%,$(SIGIL_SOC_RTL)))) \
  $(foreach b,$(SIGIL_BLOCKS),$(DESIGN_HOME)/$(PLATFORM)/sigil_hier/stubs/$(b)_stub.sv) \
  $(addprefix $(DESIGN_HOME)/src/sigil_soc/,$(filter soc/%,$(SIGIL_SOC_RTL)))
export VERILOG_INCLUDE_DIRS = $(DESIGN_HOME)/src/sigil_soc/core
export SYNTH_MEMORY_MAX_BITS = 8192
export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/sigil_soc/constraint.sdc

export DIE_AREA  = 0 0 2920 3520
export CORE_AREA = 2 2 2918 3518
export MACRO_PLACEMENT_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/macro_place.tcl
export MACRO_PLACE_HALO = 5 5
export IO_CONSTRAINTS = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/io.tcl
export PDN_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/pdn.tcl
export PLACE_DENSITY ?= 0.30
export GLOBAL_ROUTE_ARGS ?= -congestion_iterations 30 -congestion_report_iter_step 5 -allow_congestion -verbose
export SYNTH_CANONICALIZE_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/stubs/strip_params.tcl
