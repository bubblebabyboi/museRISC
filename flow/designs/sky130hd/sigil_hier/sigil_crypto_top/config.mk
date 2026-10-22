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

# 3400 x 780 (non-Caravel die; ../config.mk): 44 % std-cell utilization
# routes clean in one detailed-route pass (14 iterations, run w34);
# the 2770 x 780 Caravel slot (53 %) was still at ~1,300 violations
# after 20 iterations (run v3).
export DIE_AREA  ?= 0 0 3400 780
export CORE_AREA ?= 5 5 3395 775
export MAX_ROUTING_LAYER = met4
export PLACE_DENSITY_LB_ADDON ?= 0.05
export IO_CONSTRAINTS = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/sigil_crypto_top/io.tcl
export PDN_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/block_pdn.tcl
export PRE_GLOBAL_ROUTE_TCL = $(DESIGN_HOME)/$(PLATFORM)/sigil_hier/grt_layers.tcl
export GLOBAL_ROUTE_ARGS ?= -congestion_iterations 30 -congestion_report_iter_step 5 -allow_congestion -verbose
# Max slew / max cap: the flow's last repair_design (global-route stage)
# times with global-route parasitic estimates. In w34 the routed
# block's OpenRCX SPEF gave 1.02-1.64x the estimated slew on the
# violating drivers (median 1.25), and 1,079 max-slew pins (202 nets)
# / 210 max-cap pins at TT after routing against 14 / 2 in the
# estimate. A 40 % margin (fix to 0.6 x the limit) covers the 1.64x.
export SLEW_MARGIN ?= 40
export CAP_MARGIN ?= 40
# No POST_GLOBAL_ROUTE_TCL: ../post_grt_repair.tcl (one more
# repair_design after the global-route stage's antenna repair) stopped
# that stage in the flow (run w34n: [ERROR EST-0104] inconsistent
# parasitics state), and w34m, this config without it, finished with
# 0 max-slew / max-cap / max-fanout violations on its routed SPEF.
# Post-detailed-route antenna rounds (platform default 5): w34's five
# rounds went 400 -> 79 -> 25 -> 7 -> 1 -> 3 nets and stopped there.
export MAX_REPAIR_ANTENNAS_ITER_DRT ?= 10
