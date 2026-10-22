# FPGA F0 (#51): out-of-context Vivado synthesis + implementation of the
# whole SoC (sigil_soc_top) for the AWS F2 part, to get real utilization
# and timing before any CL/Shell work.
#   vivado -mode batch -source fpga/f0/f0_ooc.tcl -tclargs <out_dir> [period_ns] [DEFINE ...]
# Extra DEFINEs are passed to synthesis (e.g. SIGIL_VRF_OREG, #53).
# Run from the repo root. SRAMs use the behavioural models (no ASIC macro
# defines), so Vivado infers BRAM/LUTRAM.
set out    [lindex $argv 0]
set period [expr {[llength $argv] > 1 ? [lindex $argv 1] : 10.0}]
set defines [concat SYNTHESIS [lrange $argv 2 end]]
# Part of the F2 Small Shell, aws-fpga HDK v2.3.5 (shell 0x10212415).
set part   xcvu47p-fsvh2892-2-e
file mkdir $out
set_param general.maxThreads 8

# File list shared with the ORFS flows (packages first).
set fh [open rtl/sigil_soc_files.mk r]; set mk [read $fh]; close $fh
set files {}
foreach tok [regexp -all -inline {[A-Za-z0-9_/]+\.sv} $mk] { lappend files rtl/$tok }
read_verilog -sv $files

synth_design -top sigil_soc_top -part $part -mode out_of_context \
  -include_dirs rtl/core -verilog_define $defines -flatten_hierarchy rebuilt
create_clock -name core_clock -period $period [get_ports clk_i]
report_utilization -file $out/synth_util.rpt
report_utilization -hierarchical -hierarchical_depth 4 -file $out/synth_util_hier.rpt
report_timing_summary -file $out/synth_timing.rpt
write_checkpoint -force $out/post_synth.dcp

opt_design
place_design
phys_opt_design
route_design
report_utilization -file $out/impl_util.rpt
report_utilization -hierarchical -hierarchical_depth 4 -file $out/impl_util_hier.rpt
report_timing_summary -max_paths 20 -file $out/impl_timing.rpt
report_timing -max_paths 30 -nworst 1 -unique_pins -sort_by group -file $out/impl_top_paths.rpt
report_drc -file $out/impl_drc.rpt
write_checkpoint -force $out/post_route.dcp
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "F0_RESULT defines=$defines period=$period wns=$wns fmax_est=[format %.1f [expr {1000.0 / ($period - $wns)}]]MHz"
# All failing endpoints, grouped (#53); also writes impl_logic_levels.rpt.
source fpga/f0/f0_timing_reports.tcl
