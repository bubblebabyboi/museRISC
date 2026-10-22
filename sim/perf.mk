## ---- Performance harness (issue #56, docs/PERFORMANCE.md) -----------
# Included by sim/Makefile.
#
#   make -C sim perf [BENCHES="dhrystone ..."] [CONFIG="default sky130 fpga"]
#                    [MEM="soc axi"] [JOBS=4] [REPEAT=1] [PERF_OUT=dir]
#
# Builds every benchmark under sw/bench/<name>/ (its Makefile on
# sw/sdk/sdk.mk plus bench.json; BENCHES= selects, default all) once,
# runs it on the testbench of every MEM x CONFIG pair (JOBS runs in
# parallel, each REPEAT times), validates every run (the exit string,
# the bench.json "expect" lines, the SIGIL_PERF record and its
# cross-checks; with REPEAT>1 also identical counts across repeats) and
# writes results.json, results.csv and report.md to PERF_OUT
# (scripts/perf_run.py, scripts/perf_report.py).
#
# CONFIG (RTL build; any of):
#   default  the default SoC build (8 KiB 2-way I$, 16 KiB 4-way D$)
#   sky130   the sky130hd chip configuration: SRAM macro models with
#            registered reads (SRAM_OREG) and 4 KiB direct-mapped L1s
#            (srammacro family "sky130", SIGIL_SOC_PARAMS_SKY130)
#   oreg     SRAM_OREG on the default arrays and cache geometry
#   fpga     the F2 build: SIGIL_VRF_OREG (srammacro family "vrforeg")
# MEM (testbench + external memory model; deterministic):
#   soc      soc_rtl_tb: memory-bus RAM model, PERF_SOC_ARGS (default a
#            fixed 1-cycle first-beat latency, 1 beat/cycle, always ready)
#   axi      fpga_top_tb: sigil_fpga_top through the mbus->AXI4 bridge
#            (64-bit AXI) to the AXI DDR model, PERF_AXI_ARGS (default a
#            fixed 24-cycle AR->R / W->B latency, no R gaps, always
#            ready; the host drains the virtual UART every cycle)
# ITER=N overrides every bench's "iterations" (quick checks only).
CONFIG   ?= default
MEM      ?= soc axi
BENCHES  ?=
JOBS     ?= 4
REPEAT   ?= 1
ITER     ?=
PERF_OUT ?= $(abspath $(ROOT)/build/perf/run)
PERF_SOC_ARGS ?= --mem-lat 1:1 --mem-gap 0 --mem-ready 100
PERF_AXI_ARGS ?= --axi-lat 24:24 --axi-gap 0 --axi-ready 100 --uart-pop 100

# CONFIG -> testbench build suffix (srammacro families, above).
PERF_FAM_default :=
PERF_FAM_sky130  := _sky130
PERF_FAM_oreg    := _oreg
PERF_FAM_fpga    := _vrforeg
PERF_TB_soc      := soc_rtl_tb
PERF_TB_axi      := fpga_top_tb
perf_tb = $(BUILD)/$(PERF_TB_$(1))$(PERF_FAM_$(2))
PERF_TB_FILES := $(sort $(foreach m,$(MEM),$(foreach c,$(CONFIG),$(call perf_tb,$m,$c))))

# FPGA top harness on the srammacro families (the default build and
# fpga_top_tb_w512 have their own rules above).
$(BUILD)/fpga_top_tb_%: $(ROOT)/tb/cpp/fpga_top_tb.cpp $(AXI_TB_H) $(FPGA_RTL) $(FPU_INC) \
                        $$(SRAM_MOD_$$*) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS_FAST) $(OBJ)/fpgatop_$* --top-module sigil_fpga_top \
	  $(SRAM_DEF_$*) $(SRAM_GEO_$*) $(SRAM_MOD_$*) \
	  -CFLAGS -I$(abspath $(ROOT)/tb/cpp) \
	  -o $(abspath $@) $(FPGA_RTL) $(abspath $(ROOT)/tb/cpp/fpga_top_tb.cpp)

.PHONY: perf
perf: $(PERF_TB_FILES)
	python3 $(abspath $(ROOT))/scripts/perf_run.py --root $(abspath $(ROOT)) \
	  --out $(PERF_OUT) --benches "$(BENCHES)" --jobs $(JOBS) --repeat $(REPEAT) \
	  $(if $(ITER),--iterations $(ITER)) --riscv-prefix $(RISCV_PREFIX) \
	  --soc-args "$(PERF_SOC_ARGS)" --axi-args "$(PERF_AXI_ARGS)" \
	  $(foreach m,$(MEM),$(foreach c,$(CONFIG),--run $m:$c=$(abspath $(call perf_tb,$m,$c))))
