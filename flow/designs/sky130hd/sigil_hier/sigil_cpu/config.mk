# Hard block: sigil_cpu (in-house RV64GCV core + vector unit + 4 KiB
# direct-mapped L1 I$/D$ + bus arbiter) with its 7 OpenRAM macros, for
# the hierarchical sky130hd flow of sigil_soc_top (#11, see
# ../config.mk). Same RTL and sky130 configuration as the flat
# sky130hd/sigil_soc run (SIGIL_SRAM_SKY130 + SIGIL_SOC_PARAMS_SKY130).
#
# Block conventions (sky130 Caravel-style macro):
#  - signals route on met1-met4 only (MAX_ROUTING_LAYER met4), so the
#    abstract leaves met5 free for the top-level PDN and signals;
#  - power: met1 rails + met4 straps (std cells) and met4 straps over
#    the OpenRAM met3 vdd/gnd pin columns (pdn.tcl); all met4 power
#    straps are block pins, the top's met5 stripes connect to them.
export DESIGN_NICKNAME = sigil_hier_sigil_cpu
export DESIGN_NAME = sigil_cpu
export PLATFORM    = sky130hd
export SYNTH_HDL_FRONTEND = slang

SIGIL_HIER_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
include $(SIGIL_HIER_DIR)/../../src/sigil_soc/sigil_soc_files.mk

export SYNTH_SLANG_ARGS = --unroll-limit=200000 -DSYNTHESIS -DSIGIL_SRAM_SKY130 \
  $(foreach p,$(SIGIL_SOC_PARAMS_SKY130),-G $(p))
SKY130_RAM = $(FLOW_HOME)/platforms/sky130ram
SKY130_MACROS = sky130_sram_1rw1r_64x256_8 sky130_sram_1rw1r_128x256_8 \
                sky130_sram_1rw1r_44x64_8
export ADDITIONAL_LEFS = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m).lef)
export ADDITIONAL_LIBS = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m)_TT_1p8V_25C.lib)
export ADDITIONAL_GDS  = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m).gds)
export VERILOG_FILES = \
  $(foreach m,$(SKY130_MACROS),$(DESIGN_HOME)/$(PLATFORM)/sigil_soc/sram/$(m).v) \
  $(addprefix $(DESIGN_HOME)/src/sigil_soc/,$(filter core/%,$(SIGIL_SOC_RTL)))
export VERILOG_INCLUDE_DIRS = $(DESIGN_HOME)/src/sigil_soc/core
export SYNTH_MEMORY_MAX_BITS = 8192
export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_cpu/constraint.sdc

# Floorplan (non-Caravel die, see ../config.mk): 3400 x 3420 um =
# 11.63 mm^2, 3.6 % more than the 3400 x 3300 sizing run that
# global-routed with 177 overflowed gcells at 51.4 % usage (9.92 mm^2
# overflowed on 17,997; the Caravel share of 7.42 mm^2 on 45k-101k).
# Built together with a 3400 x 3680 (12.51 mm^2) variant:
#   DIE_AREA="0 0 3400 3680" CORE_AREA="5 5 3395 3675"
# Overridable from the command line for sizing runs.
export DIE_AREA  ?= 0 0 3400 3420
export CORE_AREA ?= 5 5 3395 3415
export MAX_ROUTING_LAYER = met4
# Macro halo. This ORFS version passes no halo option to
# rtl_macro_placer and no script reads MACRO_PLACE_HALO (setting it had
# no effect); RTLMP keeps half the minimum macro channel around each
# macro, so the halo is set through RTLMP_MIN_CHANNEL_SIZE. 80 80
# (= 40 um halos, "Area of macros with halos: 3698426.94" in
# 2_2_floorplan_macro.log for the 7 OpenRAM macros) is the platform
# default that every sizing run used.
export RTLMP_MIN_CHANNEL_SIZE ?= 80 80
export PLACE_DENSITY_LB_ADDON ?= 0.05
export IO_CONSTRAINTS = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_cpu/io.tcl
export PDN_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_cpu/pdn.tcl
export PRE_GLOBAL_ROUTE_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_cpu/pre_grt.tcl
export GLOBAL_ROUTE_ARGS ?= -congestion_iterations 30 -congestion_report_iter_step 5 -allow_congestion -verbose
export POST_PDN_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_cpu/post_pdn.tcl
