export DESIGN_NAME = sigil_crypto_top
export PLATFORM    = nangate45
export VERILOG_FILES = $(sort $(wildcard $(DESIGN_HOME)/src/sigil_crypto/*.sv))
export SDC_FILE      = $(DESIGN_HOME)/nangate45/sigil_crypto/constraint.sdc
export CORE_UTILIZATION = 28
export PLACE_DENSITY_LB_ADDON = 0.05
export CLOCK_PERIOD = 10
# Baseline run (2026-10-12) finished route-clean and timing-MET but
# with 51 post-route max-capacitance violations (wire cap growth
# after the placement-stage repair). Size drivers to 80% of the
# liberty max-cap during early sizing to leave routing headroom.
export EARLY_SIZING_CAP_RATIO = 0.8
# The weakest PMOS-stack gates (liberty max_cap 10-21 fF) still
# violate post-route even with the SDC guardband: their liberty
# limits sit below any usable SDC cap, so routed wire growth cannot
# be absorbed. Ban them (platform defaults first); synthesis and the
# resizer then use X2/X4 variants with 32-64 fF limits, which the
# 21 fF repair target covers with margin. AOI221_X1/OAI221_X1
# joined the list in the #31 rerun (2026-10-14): 3 liberty
# max-cap violators, all those two types; banning them made
# rerun2 liberty-clean (docs/evidence/openroad-nangate45-31-*).
# (override: platforms/nangate45/config.mk is included after this file
# and would otherwise clobber the list with its own assignment.)
override export DONT_USE_CELLS = TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1 \
                        AOI221_X1 OAI221_X1 NOR3_X1 NOR4_X1 NOR4_X2
