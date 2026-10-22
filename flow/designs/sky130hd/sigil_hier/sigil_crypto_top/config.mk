# Hard block: sigil_crypto_top (SHA-256, SHA-512, Keccak/SHA3 hash
# stream, EC field unit, AXI4-Lite slave) for the hierarchical
# sky130hd flow of sigil_soc_top (#11, see ../config.mk). Block
# conventions as in ../sigil_cpu/config.mk (met1-met4 signals, met4
# power pins).
export DESIGN_NICKNAME = sigil_hier_sigil_crypto_top
export DESIGN_NAME = sigil_crypto_top
export PLATFORM    = sky130hd
export SYNTH_HDL_FRONTEND = slang

SIGIL_HIER_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
include $(SIGIL_HIER_DIR)/../../src/sigil_soc/sigil_soc_files.mk

export SYNTH_SLANG_ARGS = --unroll-limit=200000 -DSYNTHESIS
# sigil_pkg is not needed; the crypto sources are self-contained.
export VERILOG_FILES = \
  $(addprefix $(DESIGN_HOME)/src/sigil_soc/,$(filter crypto/%,$(SIGIL_SOC_RTL)))
# sha512_block: 80x64 schedule flops + 128x64 K table (see
# ../../sigil_soc/config.mk).
export SYNTH_MEMORY_MAX_BITS = 8192
export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_crypto_top/constraint.sdc

export DIE_AREA  ?= 0 0 2590 850
export CORE_AREA ?= 5 5 2585 845
export MAX_ROUTING_LAYER = met4
export PLACE_DENSITY_LB_ADDON ?= 0.05
export IO_CONSTRAINTS = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_crypto_top/io.tcl
export PDN_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/block_pdn.tcl
export PRE_GLOBAL_ROUTE_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/grt_layers.tcl
export GLOBAL_ROUTE_ARGS ?= -congestion_iterations 30 -congestion_report_iter_step 5 -allow_congestion -verbose
