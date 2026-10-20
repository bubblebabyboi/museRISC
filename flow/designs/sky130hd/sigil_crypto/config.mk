export DESIGN_NAME = sigil_crypto_top
export PLATFORM    = sky130hd
export VERILOG_FILES = $(sort $(wildcard $(DESIGN_HOME)/src/sigil_crypto/*.v))
export SDC_FILE      = $(DESIGN_HOME)/sky130hd/sigil_crypto/constraint.sdc
export CORE_UTILIZATION = 35
export PLACE_DENSITY_LB_ADDON = 0.10
export CLOCK_PERIOD = 20
