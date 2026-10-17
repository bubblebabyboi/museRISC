# muserisc_soc_top on sky130hd (area/timing estimate for the
# chip-size decision; same RTL as nangate45/muserisc_soc via the
# shared rtl/muserisc_soc_files.mk). SRAM macros
# (MUSERISC_SRAM_SKY130) are the OpenRAM macros shipped with ORFS:
#   VRF banks, 3x 256x64 1R1W byte-write: sky130_sram_1rw1r_64x256_8
#   L1 data ways, 6x 512x64: sky130_sram_1rw1r_128x256_8 as 256x128
#   L1 tag ways, 6x 64x44: sky130_sram_1rw1r_44x64_8
# The .v models (sram/gen_openram_models.py) give slang the ports;
# the .libs blackbox them.
export DESIGN_NAME = muserisc_soc_top
export PLATFORM    = sky130hd
export SYNTH_HDL_FRONTEND = slang
# -DSYNTHESIS: see nangate45/muserisc_soc/config.mk (ORFS also passes it).
export SYNTH_SLANG_ARGS = --unroll-limit=200000 -DSYNTHESIS -DMUSERISC_SRAM_SKY130
SKY130_RAM = $(FLOW_HOME)/platforms/sky130ram
SKY130_MACROS = sky130_sram_1rw1r_64x256_8 sky130_sram_1rw1r_128x256_8 \
                sky130_sram_1rw1r_44x64_8
export ADDITIONAL_LEFS = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m).lef)
export ADDITIONAL_LIBS = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m)_TT_1p8V_25C.lib)
export ADDITIONAL_GDS  = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m).gds)
# SoC RTL list shared with the other platform's config (located
# relative to this file: DESIGN_HOME is not yet set while ORFS reads
# the design config).
include $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../../src/muserisc_soc/muserisc_soc_files.mk)
export VERILOG_FILES = \
  $(foreach m,$(SKY130_MACROS),$(DESIGN_HOME)/$(PLATFORM)/muserisc_soc/sram/$(m).v) \
  $(addprefix $(DESIGN_HOME)/src/muserisc_soc/,$(MUSERISC_SOC_RTL))
# muserisc_fpu_ops.svh is `included by muserisc_fpu_pkg.sv and
# muserisc_fpu.sv.
export VERILOG_INCLUDE_DIRS = $(DESIGN_HOME)/src/muserisc_soc/core
export SDC_FILE      = $(DESIGN_HOME)/sky130hd/muserisc_soc/constraint.sdc
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
# The OpenRAM macros are up to ~1.1 mm x 0.6 mm; leave room around them.
export MACRO_PLACE_HALO = 40 40
